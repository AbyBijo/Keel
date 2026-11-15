import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'db.dart';

const _uuid = Uuid();

String newId() => _uuid.v4();

/// Thrown when removing a team leader without naming a replacement.
class LeaderRemovalNeedsReplacement implements Exception {
  final String teamId;
  LeaderRemovalNeedsReplacement(this.teamId);
}

/// Thrown when a team would be left without a leader.
class LeaderRequiredException implements Exception {
  final String message;
  LeaderRequiredException(this.message);
}

/// Thrown when a leader is not a member of their own team (rule 4).
class LeaderNotMemberException implements Exception {
  final String message;
  LeaderNotMemberException(this.message);
}

bool isOverdue(Task task, {DateTime? now}) {
  if (task.isDone || task.dueDate == null) return false;
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final d = task.dueDate!;
  return DateTime(d.year, d.month, d.day).isBefore(today);
}

bool isDueSoon(Task task, {DateTime? now}) {
  if (task.isDone || task.dueDate == null) return false;
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final d = DateTime(
    task.dueDate!.year,
    task.dueDate!.month,
    task.dueDate!.day,
  );
  final diff = d.difference(today).inDays;
  return diff >= 0 && diff <= 2;
}

/// A deleted entity plus everything needed to put it back (Undo, rule 10).
class DeleteSnapshot {
  final String kind; // 'task' | 'person' | 'team'
  final Map<String, dynamic> data;
  DeleteSnapshot(this.kind, this.data);

  String toJson() => jsonEncode({'kind': kind, 'data': data});
  factory DeleteSnapshot.fromJson(String s) {
    final m = jsonDecode(s) as Map<String, dynamic>;
    return DeleteSnapshot(
      m['kind'] as String,
      Map<String, dynamic>.from(m['data'] as Map),
    );
  }
}

/// All data access + the 10 logic rules. The UI never touches the DB
/// directly; every change goes through here and is saved immediately.
class KeelRepository {
  final AppDatabase db;
  KeelRepository(this.db);

  // -- profile & organizations -------------------------------------------

  Future<Profile?> getProfile() =>
      (db.select(db.profiles)..where((t) => t.id.equals('profile')))
          .getSingleOrNull();

  Stream<Profile?> watchProfile() =>
      (db.select(db.profiles)..where((t) => t.id.equals('profile')))
          .watchSingleOrNull();

  Future<void> saveProfile({required String name, required String role}) {
    return db.into(db.profiles).insertOnConflictUpdate(
          ProfilesCompanion.insert(id: 'profile', name: name, role: role),
        );
  }

  Future<List<Organization>> getOrganizations() =>
      (db.select(db.organizations)
            ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
          .get();

  Stream<List<Organization>> watchOrganizations() =>
      (db.select(db.organizations)
            ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
          .watch();

  Future<Organization> createOrganization({
    required String name,
    required String kind,
  }) async {
    final org = Organization(
      id: newId(),
      name: name.trim(),
      kind: kind,
      createdAt: DateTime.now(),
    );
    await db.into(db.organizations).insert(org);
    return org;
  }

  Future<void> renameOrganization(String orgId, String name) async {
    await (db.update(db.organizations)..where((t) => t.id.equals(orgId)))
        .write(OrganizationsCompanion(name: Value(name.trim())));
  }

  /// Deleting an organization deletes everything inside it. The UI must
  /// confirm first; there is no undo for this one (it is explicit).
  Future<void> deleteOrganization(String orgId) {
    return db.transaction(() async {
      final tasks =
          await (db.select(db.tasks)..where((t) => t.orgId.equals(orgId)))
              .get();
      for (final t in tasks) {
        await _deleteTaskRows(t.id);
      }
      await (db.delete(db.teams)..where((t) => t.orgId.equals(orgId))).go();
      await (db.delete(db.people)..where((t) => t.orgId.equals(orgId))).go();
      await (db.delete(db.organizations)..where((t) => t.id.equals(orgId)))
          .go();
    });
  }

  // -- people ---------------------------------------------------------------

  Stream<List<Person>> watchPeople(String orgId) =>
      (db.select(db.people)
            ..where((t) => t.orgId.equals(orgId))
            ..orderBy([(t) => OrderingTerm(expression: t.name)]))
          .watch();

  Future<List<Person>> getPeople(String orgId) =>
      (db.select(db.people)
            ..where((t) => t.orgId.equals(orgId))
            ..orderBy([(t) => OrderingTerm(expression: t.name)]))
          .get();

  Future<Person?> getPerson(String id) =>
      (db.select(db.people)..where((t) => t.id.equals(id))).getSingleOrNull();

  Stream<Person?> watchPerson(String id) =>
      (db.select(db.people)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Future<Person> createPerson({
    required String orgId,
    required String name,
    required String roleTitle,
    String? photoPath,
    String notes = '',
    List<({String label, String number})> phones = const [],
    List<({String label, String address})> emails = const [],
    List<String> teamIds = const [],
  }) async {
    final person = Person(
      id: newId(),
      orgId: orgId,
      name: name.trim(),
      roleTitle: roleTitle.trim(),
      photoPath: photoPath,
      notes: notes,
      createdAt: DateTime.now(),
    );
    await db.transaction(() async {
      await db.into(db.people).insert(person);
      for (final ph in phones) {
        await db.into(db.personPhones).insert(
              PersonPhone(
                id: newId(),
                personId: person.id,
                label: ph.label,
                number: ph.number,
              ),
            );
      }
      for (final em in emails) {
        await db.into(db.personEmails).insert(
              PersonEmail(
                id: newId(),
                personId: person.id,
                label: em.label,
                address: em.address,
              ),
            );
      }
      for (final teamId in teamIds) {
        await db.into(db.teamMembers).insert(
              TeamMember(teamId: teamId, personId: person.id),
            );
      }
    });
    return person;
  }

  Future<void> updatePerson(
    String id, {
    String? name,
    String? roleTitle,
    String? notes,
    Value<String?> photoPath = const Value.absent(),
  }) async {
    await (db.update(db.people)..where((t) => t.id.equals(id))).write(
      PeopleCompanion(
        name: name == null ? const Value.absent() : Value(name.trim()),
        roleTitle: roleTitle == null
            ? const Value.absent()
            : Value(roleTitle.trim()),
        notes: notes == null ? const Value.absent() : Value(notes),
        photoPath: photoPath,
      ),
    );
  }

  Future<List<PersonPhone>> getPhones(String personId) =>
      (db.select(db.personPhones)
            ..where((t) => t.personId.equals(personId)))
          .get();

  Stream<List<PersonPhone>> watchPhones(String personId) =>
      (db.select(db.personPhones)
            ..where((t) => t.personId.equals(personId)))
          .watch();

  Future<List<PersonEmail>> getEmails(String personId) =>
      (db.select(db.personEmails)
            ..where((t) => t.personId.equals(personId)))
          .get();

  Stream<List<PersonEmail>> watchEmails(String personId) =>
      (db.select(db.personEmails)
            ..where((t) => t.personId.equals(personId)))
          .watch();

  Future<void> addPhone(String personId, String label, String number) =>
      db.into(db.personPhones).insert(
            PersonPhone(
              id: newId(),
              personId: personId,
              label: label,
              number: number.trim(),
            ),
          );

  Future<void> addEmail(String personId, String label, String address) =>
      db.into(db.personEmails).insert(
            PersonEmail(
              id: newId(),
              personId: personId,
              label: label,
              address: address.trim(),
            ),
          );

  Future<void> deletePhone(String id) =>
      (db.delete(db.personPhones)..where((t) => t.id.equals(id))).go();

  Future<void> deleteEmail(String id) =>
      (db.delete(db.personEmails)..where((t) => t.id.equals(id))).go();

  /// Rule 10: deleting a person removes only their assignments and
  /// memberships — never other people, teams or tasks. If they lead any
  /// team, [leaderReplacements] must name a new leader per team id,
  /// otherwise [LeaderRemovalNeedsReplacement] is thrown.
  Future<DeleteSnapshot> deletePerson(
    String personId, {
    Map<String, String> leaderReplacements = const {},
  }) async {
    final person = await getPerson(personId);
    if (person == null) {
      throw StateError('Person not found: $personId');
    }
    final ledTeams =
        await (db.select(db.teams)
              ..where((t) => t.leaderPersonId.equals(personId)))
            .get();
    for (final team in ledTeams) {
      if (!leaderReplacements.containsKey(team.id)) {
        throw LeaderRemovalNeedsReplacement(team.id);
      }
    }
    final phones = await getPhones(personId);
    final emails = await getEmails(personId);
    final memberships =
        await (db.select(db.teamMembers)
              ..where((t) => t.personId.equals(personId)))
            .get();
    final assignments =
        await (db.select(db.taskAssignees)
              ..where((t) => t.personId.equals(personId)))
            .get();
    final snapshot = DeleteSnapshot('person', {
      'person': person.toJson(),
      'phones': phones.map((e) => e.toJson()).toList(),
      'emails': emails.map((e) => e.toJson()).toList(),
      'memberships': memberships.map((e) => e.toJson()).toList(),
      'assignments': assignments.map((e) => e.toJson()).toList(),
      'ledTeams': ledTeams.map((e) => e.id).toList(),
    });
    await db.transaction(() async {
      for (final team in ledTeams) {
        final replacement = leaderReplacements[team.id]!;
        await (db.update(db.teams)..where((t) => t.id.equals(team.id)))
            .write(TeamsCompanion(leaderPersonId: Value(replacement)));
        // The new leader must be a member (rule 4).
        await db.into(db.teamMembers).insertOnConflictUpdate(
              TeamMember(teamId: team.id, personId: replacement),
            );
      }
      await (db.delete(db.people)..where((t) => t.id.equals(personId))).go();
    });
    return snapshot;
  }

  // -- teams ----------------------------------------------------------------

  Stream<List<Team>> watchTeams(String orgId) =>
      (db.select(db.teams)
            ..where((t) => t.orgId.equals(orgId))
            ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
          .watch();

  Future<List<Team>> getTeams(String orgId) =>
      (db.select(db.teams)
            ..where((t) => t.orgId.equals(orgId))
            ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
          .get();

  Future<Team?> getTeam(String id) =>
      (db.select(db.teams)..where((t) => t.id.equals(id))).getSingleOrNull();

  Stream<Team?> watchTeam(String id) =>
      (db.select(db.teams)..where((t) => t.id.equals(id))).watchSingleOrNull();

  /// Rule 4: a team is created with exactly one leader, who must be a
  /// member. The leader is added as a member automatically.
  Future<Team> createTeam({
    required String orgId,
    required String name,
    required String colorHex,
    required String leaderPersonId,
    List<String> memberIds = const [],
    String? mainTaskId,
  }) async {
    if (leaderPersonId.isEmpty) {
      throw LeaderRequiredException('A team needs a leader.');
    }
    final team = Team(
      id: newId(),
      orgId: orgId,
      name: name.trim(),
      colorHex: colorHex,
      leaderPersonId: leaderPersonId,
      mainTaskId: mainTaskId,
      createdAt: DateTime.now(),
    );
    await db.transaction(() async {
      await db.into(db.teams).insert(team);
      final members = {...memberIds, leaderPersonId};
      for (final m in members) {
        await db.into(db.teamMembers).insert(
              TeamMember(teamId: team.id, personId: m),
            );
      }
    });
    return team;
  }

  Future<void> updateTeam(
    String id, {
    String? name,
    String? colorHex,
    String? leaderPersonId,
  }) async {
    if (leaderPersonId != null) {
      final isMember =
          await (db.select(db.teamMembers)
                ..where(
                  (t) =>
                      t.teamId.equals(id) &
                      t.personId.equals(leaderPersonId),
                ))
              .getSingleOrNull();
      if (isMember == null) {
        throw LeaderNotMemberException('The leader must be a team member.');
      }
    }
    await (db.update(db.teams)..where((t) => t.id.equals(id))).write(
      TeamsCompanion(
        name: name == null ? const Value.absent() : Value(name.trim()),
        colorHex: colorHex == null
            ? const Value.absent()
            : Value(colorHex),
        leaderPersonId: leaderPersonId == null
            ? const Value.absent()
            : Value(leaderPersonId),
      ),
    );
  }

  /// Rule 2: membership is one table, written from either side.
  Future<void> addTeamMember(String teamId, String personId) =>
      db.into(db.teamMembers).insertOnConflictUpdate(
            TeamMember(teamId: teamId, personId: personId),
          );

  /// Rule 4: removing the leader requires [newLeaderId]; otherwise throws.
  Future<void> removeTeamMember(
    String teamId,
    String personId, {
    String? newLeaderId,
  }) async {
    final team = await getTeam(teamId);
    if (team == null) return;
    if (team.leaderPersonId == personId) {
      if (newLeaderId == null || newLeaderId.isEmpty) {
        throw LeaderRemovalNeedsReplacement(teamId);
      }
      await db.transaction(() async {
        await (db.update(db.teams)..where((t) => t.id.equals(teamId))).write(
          TeamsCompanion(leaderPersonId: Value(newLeaderId)),
        );
        await db.into(db.teamMembers).insertOnConflictUpdate(
              TeamMember(teamId: teamId, personId: newLeaderId),
            );
        await (db.delete(db.teamMembers)
              ..where(
                (t) =>
                    t.teamId.equals(teamId) & t.personId.equals(personId),
              ))
            .go();
      });
      return;
    }
    await (db.delete(db.teamMembers)
          ..where(
            (t) => t.teamId.equals(teamId) & t.personId.equals(personId),
          ))
        .go();
  }

  /// One JOIN, not one query per member (N+1): a 200-person team used
  /// to fire 200 getPerson queries every time it rendered.
  Future<List<Person>> getTeamMembers(String teamId) async {
    final q = db.select(db.people).join([
      innerJoin(
        db.teamMembers,
        db.teamMembers.personId.equalsExp(db.people.id),
      ),
    ])
      ..where(db.teamMembers.teamId.equals(teamId))
      ..orderBy([OrderingTerm(expression: db.people.name)]);
    final rows = await q.get();
    return rows.map((r) => r.readTable(db.people)).toList();
  }

  Stream<List<TeamMember>> watchTeamMembers(String teamId) =>
      (db.select(db.teamMembers)..where((t) => t.teamId.equals(teamId)))
          .watch();

  /// One JOIN, not one query per team (N+1).
  Future<List<Team>> getTeamsForPerson(String personId) async {
    final q = db.select(db.teams).join([
      innerJoin(
        db.teamMembers,
        db.teamMembers.teamId.equalsExp(db.teams.id),
      ),
    ])..where(db.teamMembers.personId.equals(personId));
    final rows = await q.get();
    return rows.map((r) => r.readTable(db.teams)).toList();
  }

  Stream<List<Team>> watchTeamsForPerson(String personId) {
    final q = db.select(db.teams).join([
      innerJoin(
        db.teamMembers,
        db.teamMembers.teamId.equalsExp(db.teams.id),
      ),
    ])..where(db.teamMembers.personId.equals(personId));
    return q.watch().map((rows) => rows.map((r) => r.readTable(db.teams)).toList());
  }

  /// Rule 5: at most one main task per team — setting one clears the old.
  Future<void> setMainTask(String teamId, String? taskId) async {
    await db.transaction(() async {
      if (taskId != null) {
        final task = await getTask(taskId);
        if (task != null && task.teamId != teamId) {
          await (db.update(db.tasks)..where((t) => t.id.equals(taskId)))
              .write(const TasksCompanion(teamId: Value(null)));
          // Re-assign the task to this team so "main task" is meaningful.
          await (db.update(db.tasks)..where((t) => t.id.equals(taskId)))
              .write(TasksCompanion(teamId: Value(teamId)));
        }
      }
      await (db.update(db.teams)..where((t) => t.id.equals(teamId))).write(
        TeamsCompanion(mainTaskId: Value(taskId)),
      );
    });
  }

  /// Rule 5: team progress = done tasks / all its tasks.
  Future<double> teamProgress(String teamId) async {
    final tasks = await getTasksForTeam(teamId);
    if (tasks.isEmpty) return 0;
    return tasks.where((t) => t.isDone).length / tasks.length;
  }

  /// Rule 10: deleting a team does NOT delete its people or tasks.
  /// Its tasks keep existing with no team.
  Future<DeleteSnapshot> deleteTeam(String teamId) async {
    final team = await getTeam(teamId);
    if (team == null) throw StateError('Team not found: $teamId');
    final members =
        await (db.select(db.teamMembers)
              ..where((t) => t.teamId.equals(teamId)))
            .get();
    final tasks = await getTasksForTeam(teamId);
    final snapshot = DeleteSnapshot('team', {
      'team': team.toJson(),
      'members': members.map((e) => e.toJson()).toList(),
      'taskIds': tasks.map((e) => e.id).toList(),
    });
    await db.transaction(() async {
      await (db.update(db.tasks)..where((t) => t.teamId.equals(teamId)))
          .write(const TasksCompanion(teamId: Value(null)));
      await (db.delete(db.teams)..where((t) => t.id.equals(teamId))).go();
    });
    return snapshot;
  }

  // -- tasks ----------------------------------------------------------------

  Stream<List<Task>> watchTasks(String orgId) =>
      (db.select(db.tasks)
            ..where((t) => t.orgId.equals(orgId))
            ..orderBy([
              (t) => OrderingTerm(expression: t.isDone),
              (t) => OrderingTerm(expression: t.dueDate),
              (t) => OrderingTerm(
                    expression: t.createdAt,
                    mode: OrderingMode.desc,
                  ),
            ]))
          .watch();

  Future<List<Task>> getTasks(String orgId) =>
      (db.select(db.tasks)..where((t) => t.orgId.equals(orgId))).get();

  Future<List<Task>> getTasksForTeam(String teamId) =>
      (db.select(db.tasks)..where((t) => t.teamId.equals(teamId))).get();

  Stream<List<Task>> watchTasksForTeam(String teamId) =>
      (db.select(db.tasks)..where((t) => t.teamId.equals(teamId))).watch();

  Future<Task?> getTask(String id) =>
      (db.select(db.tasks)..where((t) => t.id.equals(id))).getSingleOrNull();

  Stream<Task?> watchTask(String id) =>
      (db.select(db.tasks)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Future<Task> createTask({
    required String orgId,
    required String title,
    String notes = '',
    DateTime? dueDate,
    String priority = 'none',
    String? teamId,
    List<String> assigneeIds = const [],
    List<String> subTodoTitles = const [],
  }) async {
    final task = Task(
      id: newId(),
      orgId: orgId,
      title: title.trim(),
      notes: notes,
      dueDate: dueDate,
      priority: priority,
      teamId: teamId,
      isDone: false,
      completedAt: null,
      createdAt: DateTime.now(),
    );
    await db.transaction(() async {
      await db.into(db.tasks).insert(task);
      for (final a in assigneeIds) {
        await db.into(db.taskAssignees).insert(
              TaskAssignee(taskId: task.id, personId: a),
            );
      }
      for (var i = 0; i < subTodoTitles.length; i++) {
        final title = subTodoTitles[i].trim();
        if (title.isEmpty) continue;
        await db.into(db.subTodos).insert(
              SubTodo(
                id: newId(),
                taskId: task.id,
                title: title,
                isDone: false,
                sortOrder: i,
              ),
            );
      }
    });
    return task;
  }

  Future<void> updateTask(
    String id, {
    String? title,
    String? notes,
    Value<DateTime?> dueDate = const Value.absent(),
    String? priority,
    Value<String?> teamId = const Value.absent(),
  }) async {
    await (db.update(db.tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        title: title == null ? const Value.absent() : Value(title.trim()),
        notes: notes == null ? const Value.absent() : Value(notes),
        dueDate: dueDate,
        priority: priority == null
            ? const Value.absent()
            : Value(priority),
        teamId: teamId,
      ),
    );
  }

  /// Rule 1: assignment is reflexive — one table, read from both sides.
  Future<void> assignPersonToTask(String taskId, String personId) =>
      db.into(db.taskAssignees).insertOnConflictUpdate(
            TaskAssignee(taskId: taskId, personId: personId),
          );

  Future<void> unassignPersonFromTask(String taskId, String personId) =>
      (db.delete(db.taskAssignees)
            ..where(
              (t) => t.taskId.equals(taskId) & t.personId.equals(personId),
            ))
          .go();

  /// One JOIN, not one query per assignee (N+1).
  Future<List<Person>> getTaskAssignees(String taskId) async {
    final q = db.select(db.people).join([
      innerJoin(
        db.taskAssignees,
        db.taskAssignees.personId.equalsExp(db.people.id),
      ),
    ])
      ..where(db.taskAssignees.taskId.equals(taskId))
      ..orderBy([OrderingTerm(expression: db.people.name)]);
    final rows = await q.get();
    return rows.map((r) => r.readTable(db.people)).toList();
  }

  Stream<List<TaskAssignee>> watchTaskAssignees(String taskId) =>
      (db.select(db.taskAssignees)..where((t) => t.taskId.equals(taskId)))
          .watch();

  /// One JOIN, not one query per task (N+1). Undated tasks sort last,
  /// as before.
  Future<List<Task>> getTasksForPerson(String personId) async {
    final q = db.select(db.tasks).join([
      innerJoin(
        db.taskAssignees,
        db.taskAssignees.taskId.equalsExp(db.tasks.id),
      ),
    ])..where(db.taskAssignees.personId.equals(personId));
    final rows = await q.get();
    final tasks = rows.map((r) => r.readTable(db.tasks)).toList();
    tasks.sort((a, b) {
      final da = a.dueDate, dbb = b.dueDate;
      if (da == null && dbb == null) return 0;
      if (da == null) return 1;
      if (dbb == null) return -1;
      return da.compareTo(dbb);
    });
    return tasks;
  }

  /// Rule 7: completing a task sets completedAt; reopening clears it.
  Future<void> setTaskDone(String taskId, bool done) async {
    await (db.update(db.tasks)..where((t) => t.id.equals(taskId))).write(
      TasksCompanion(
        isDone: Value(done),
        completedAt: Value(done ? DateTime.now() : null),
      ),
    );
  }

  Future<DeleteSnapshot> deleteTask(String taskId) async {
    final task = await getTask(taskId);
    if (task == null) throw StateError('Task not found: $taskId');
    final assignees =
        await (db.select(db.taskAssignees)
              ..where((t) => t.taskId.equals(taskId)))
            .get();
    final subs = await getSubTodos(taskId);
    final snapshot = DeleteSnapshot('task', {
      'task': task.toJson(),
      'assignees': assignees.map((e) => e.toJson()).toList(),
      'subTodos': subs.map((e) => e.toJson()).toList(),
    });
    await _deleteTaskRows(taskId);
    return snapshot;
  }

  Future<void> _deleteTaskRows(String taskId) async {
    // Clear "main task" pointers explicitly: the Teams <-> Tasks foreign
    // keys are circular, so Drift drops the Tasks.teamId FK (see
    // DECISIONS.md). Never rely on the DB to clean this up.
    await (db.update(db.teams)..where((t) => t.mainTaskId.equals(taskId)))
        .write(const TeamsCompanion(mainTaskId: Value(null)));
    await (db.delete(db.tasks)..where((t) => t.id.equals(taskId))).go();
  }

  /// Restore a snapshot taken by deleteTask / deletePerson / deleteTeam.
  Future<void> restoreSnapshot(DeleteSnapshot snap) async {
    await db.transaction(() async {
      switch (snap.kind) {
        case 'task':
          final task = Task.fromJson(snap.data['task'] as Map<String, dynamic>);
          await db.into(db.tasks).insertOnConflictUpdate(task);
          for (final a in snap.data['assignees'] as List) {
            await db.into(db.taskAssignees).insertOnConflictUpdate(
                  TaskAssignee.fromJson(a as Map<String, dynamic>),
                );
          }
          for (final s in snap.data['subTodos'] as List) {
            await db.into(db.subTodos).insertOnConflictUpdate(
                  SubTodo.fromJson(s as Map<String, dynamic>),
                );
          }
        case 'person':
          final person =
              Person.fromJson(snap.data['person'] as Map<String, dynamic>);
          await db.into(db.people).insertOnConflictUpdate(person);
          for (final e in snap.data['phones'] as List) {
            await db.into(db.personPhones).insertOnConflictUpdate(
                  PersonPhone.fromJson(e as Map<String, dynamic>),
                );
          }
          for (final e in snap.data['emails'] as List) {
            await db.into(db.personEmails).insertOnConflictUpdate(
                  PersonEmail.fromJson(e as Map<String, dynamic>),
                );
          }
          for (final e in snap.data['memberships'] as List) {
            await db.into(db.teamMembers).insertOnConflictUpdate(
                  TeamMember.fromJson(e as Map<String, dynamic>),
                );
          }
          for (final e in snap.data['assignments'] as List) {
            await db.into(db.taskAssignees).insertOnConflictUpdate(
                  TaskAssignee.fromJson(e as Map<String, dynamic>),
                );
          }
          // Leadership was handed to replacements at delete time; restoring
          // the person does not silently take leadership back.
        case 'team':
          final team = Team.fromJson(snap.data['team'] as Map<String, dynamic>);
          await db.into(db.teams).insertOnConflictUpdate(team);
          for (final e in snap.data['members'] as List) {
            await db.into(db.teamMembers).insertOnConflictUpdate(
                  TeamMember.fromJson(e as Map<String, dynamic>),
                );
          }
          for (final id in snap.data['taskIds'] as List) {
            await (db.update(db.tasks)..where((t) => t.id.equals(id as String)))
                .write(TasksCompanion(teamId: Value(team.id)));
          }
      }
    });
  }

  Future<int> clearCompletedTasks(String orgId) async {
    final done =
        await (db.select(db.tasks)
              ..where((t) => t.orgId.equals(orgId) & t.isDone.equals(true)))
            .get();
    for (final t in done) {
      await _deleteTaskRows(t.id);
    }
    return done.length;
  }

  // -- sub-todos --------------------------------------------------------------

  Future<List<SubTodo>> getSubTodos(String taskId) =>
      (db.select(db.subTodos)
            ..where((t) => t.taskId.equals(taskId))
            ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
          .get();

  Stream<List<SubTodo>> watchSubTodos(String taskId) =>
      (db.select(db.subTodos)
            ..where((t) => t.taskId.equals(taskId))
            ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
          .watch();

  Future<SubTodo> addSubTodo(String taskId, String title) async {
    final existing = await getSubTodos(taskId);
    final sub = SubTodo(
      id: newId(),
      taskId: taskId,
      title: title.trim(),
      isDone: false,
      sortOrder: existing.length,
    );
    await db.into(db.subTodos).insert(sub);
    return sub;
  }

  /// Rule 7 result: toggling a sub-todo reports whether all sub-todos are
  /// now done (so the UI can offer the inline "complete parent" prompt)
  /// and whether the parent was reopened.
  Future<({bool allDone, bool parentReopened})> toggleSubTodo(
    String subTodoId,
    bool done,
  ) async {
    final sub =
        await (db.select(db.subTodos)..where((t) => t.id.equals(subTodoId)))
            .getSingleOrNull();
    if (sub == null) {
      return (allDone: false, parentReopened: false);
    }
    var parentReopened = false;
    await db.transaction(() async {
      await (db.update(db.subTodos)..where((t) => t.id.equals(subTodoId)))
          .write(SubTodosCompanion(isDone: Value(done)));
      if (!done) {
        // Reopening a sub-todo reopens the parent (rule 7).
        final parent = await getTask(sub.taskId);
        if (parent != null && parent.isDone) {
          await setTaskDone(parent.id, false);
          parentReopened = true;
        }
      }
    });
    final subs = await getSubTodos(sub.taskId);
    final allDone = subs.isNotEmpty && subs.every((s) => s.isDone);
    return (allDone: allDone, parentReopened: parentReopened);
  }

  Future<void> deleteSubTodo(String id) =>
      (db.delete(db.subTodos)..where((t) => t.id.equals(id))).go();

  Future<void> reorderSubTodos(String taskId, List<String> orderedIds) async {
    await db.transaction(() async {
      for (var i = 0; i < orderedIds.length; i++) {
        await (db.update(db.subTodos)
              ..where((t) => t.id.equals(orderedIds[i])))
            .write(SubTodosCompanion(sortOrder: Value(i)));
      }
    });
  }

  // -- search & stats ---------------------------------------------------------

  /// Global search on Home: tasks, people, teams in the active org.
  /// One bulk fetch per table — the old version ran 3 queries per
  /// person (phones, emails, teams) on every keystroke.
  Future<({List<Task> tasks, List<Person> people, List<Team> teams})>
  search(String orgId, String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return (tasks: <Task>[], people: <Person>[], teams: <Team>[]);
    final allTasks = await getTasks(orgId);
    final allPeople = await getPeople(orgId);
    final allTeams = await getTeams(orgId);
    final tasks = allTasks
        .where((t) => t.title.toLowerCase().contains(q))
        .toList();
    final teams = allTeams
        .where((t) => t.name.toLowerCase().contains(q))
        .toList();

    final phones = await (db.select(db.personPhones)).get();
    final emails = await (db.select(db.personEmails)).get();
    final memberships = await (db.select(db.teamMembers)).get();
    final phonesByPerson = <String, List<String>>{};
    for (final ph in phones) {
      (phonesByPerson[ph.personId] ??= []).add(ph.number);
    }
    final emailsByPerson = <String, List<String>>{};
    for (final em in emails) {
      (emailsByPerson[em.personId] ??= []).add(em.address);
    }
    final teamNameById = {for (final t in allTeams) t.id: t.name};
    final teamNamesByPerson = <String, List<String>>{};
    for (final m in memberships) {
      final name = teamNameById[m.teamId];
      if (name != null) (teamNamesByPerson[m.personId] ??= []).add(name);
    }

    // Name matches first, then role/phone/email/team matches.
    final people = allPeople
        .where((p) => p.name.toLowerCase().contains(q))
        .toList();
    final extraPeople = <Person>[];
    for (final p in allPeople) {
      if (people.contains(p)) continue;
      final hay = [
        p.roleTitle,
        ...(phonesByPerson[p.id] ?? const []),
        ...(emailsByPerson[p.id] ?? const []),
        ...(teamNamesByPerson[p.id] ?? const []),
      ].join(' ').toLowerCase();
      if (hay.contains(q)) extraPeople.add(p);
    }
    return (
      tasks: tasks,
      people: [...people, ...extraPeople],
      teams: teams,
    );
  }

  Future<({int total, int done, int overdue, int dueSoon})> homeStats(
    String orgId,
  ) async {
    final tasks = await getTasks(orgId);
    final now = DateTime.now();
    return (
      total: tasks.length,
      done: tasks.where((t) => t.isDone).length,
      overdue: tasks.where((t) => isOverdue(t, now: now)).length,
      dueSoon: tasks.where((t) => isDueSoon(t, now: now)).length,
    );
  }

  /// Up next: 2–3 most urgent open tasks — overdue first, then soonest due.
  Future<List<Task>> upNext(String orgId, {int limit = 3}) async {
    final tasks = (await getTasks(orgId)).where((t) => !t.isDone).toList();
    final now = DateTime.now();
    tasks.sort((a, b) {
      final ao = isOverdue(a, now: now) ? 0 : 1;
      final bo = isOverdue(b, now: now) ? 0 : 1;
      if (ao != bo) return ao - bo;
      final da = a.dueDate, dbb = b.dueDate;
      if (da == null && dbb == null) return 0;
      if (da == null) return 1;
      if (dbb == null) return -1;
      return da.compareTo(dbb);
    });
    return tasks.take(limit).toList();
  }

  // -- backup / restore -------------------------------------------------------

  /// Everything, as plain JSON maps, for backup. Photos are handled by the
  /// backup service (files copied into the zip next to this JSON).
  Future<Map<String, dynamic>> exportAll() async {
    Future<List<Map<String, dynamic>>> rows(
      Future<List<dynamic>> Function() get,
    ) async =>
        (await get()).map((e) => (e as dynamic).toJson() as Map<String, dynamic>).toList();
    return {
      'format': 'keel-backup',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'organizations': await rows(getOrganizations),
      'profile': (await getProfile())?.toJson(),
      'people': await rows(
        () => (db.select(db.people)).get(),
      ),
      'phones': await rows(() => (db.select(db.personPhones)).get()),
      'emails': await rows(() => (db.select(db.personEmails)).get()),
      'teams': await rows(() => (db.select(db.teams)).get()),
      'teamMembers': await rows(() => (db.select(db.teamMembers)).get()),
      'tasks': await rows(() => (db.select(db.tasks)).get()),
      'taskAssignees': await rows(() => (db.select(db.taskAssignees)).get()),
      'subTodos': await rows(() => (db.select(db.subTodos)).get()),
    };
  }

  /// Validate the file BEFORE replacing any data (see docs/security.md).
  /// Returns null when the payload is valid, otherwise an error message.
  /// Every list the restore reads must be present AND contain only
  /// row maps — a foreign file with the right header but a damaged
  /// row used to crash the restore with a raw TypeError instead of a
  /// readable message.
  static String? validateBackup(Map<String, dynamic> data) {
    if (data['format'] != 'keel-backup') {
      return 'This file is not a Keel backup.';
    }
    if (data['version'] != 1) {
      return 'Unsupported backup version (${data['version']}).';
    }
    for (final key in [
      'organizations',
      'people',
      'phones',
      'emails',
      'teams',
      'tasks',
      'taskAssignees',
      'teamMembers',
      'subTodos',
    ]) {
      final v = data[key];
      if (v is! List) return 'Backup is missing its $key list.';
      for (final row in v) {
        if (row is! Map) return 'Backup $key has a damaged entry.';
      }
    }
    return null;
  }

  /// Replace ALL data with a validated backup. Returns a summary.
  Future<({int orgs, int people, int teams, int tasks})> importAll(
    Map<String, dynamic> data,
  ) async {
    final error = validateBackup(data);
    if (error != null) throw FormatException(error);
    int count(List? l) => l?.length ?? 0;
    await db.transaction(() async {
      await db.delete(db.subTodos).go();
      await db.delete(db.taskAssignees).go();
      await db.delete(db.tasks).go();
      await db.delete(db.teamMembers).go();
      await db.delete(db.teams).go();
      await db.delete(db.personPhones).go();
      await db.delete(db.personEmails).go();
      await db.delete(db.people).go();
      await db.delete(db.organizations).go();
      await db.delete(db.profiles).go();

      Future<void> insertAll<T extends Table, D extends Insertable<D>>(
        TableInfo<T, D> table,
        List list,
        D Function(Map<String, dynamic>) fromJson,
      ) async {
        for (final row in list) {
          await db.into(table).insertOnConflictUpdate(
                fromJson(Map<String, dynamic>.from(row as Map)),
              );
        }
      }

      await insertAll(db.organizations, data['organizations'] as List,
          Organization.fromJson);
      final profile = data['profile'];
      if (profile != null) {
        await db.into(db.profiles).insertOnConflictUpdate(
              Profile.fromJson(Map<String, dynamic>.from(profile as Map)),
            );
      }
      await insertAll(db.people, data['people'] as List, Person.fromJson);
      await insertAll(
          db.personPhones, data['phones'] as List, PersonPhone.fromJson);
      await insertAll(
          db.personEmails, data['emails'] as List, PersonEmail.fromJson);
      await insertAll(db.teams, data['teams'] as List, Team.fromJson);
      await insertAll(
          db.teamMembers, data['teamMembers'] as List, TeamMember.fromJson);
      await insertAll(db.tasks, data['tasks'] as List, Task.fromJson);
      await insertAll(db.taskAssignees, data['taskAssignees'] as List,
          TaskAssignee.fromJson);
      await insertAll(db.subTodos, data['subTodos'] as List, SubTodo.fromJson);
    });
    return (
      orgs: count(data['organizations'] as List?),
      people: count(data['people'] as List?),
      teams: count(data['teams'] as List?),
      tasks: count(data['tasks'] as List?),
    );
  }
}
