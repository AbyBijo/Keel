import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/db.dart';
import 'package:keel/repo.dart';

Future<KeelRepository> freshRepo() async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  return KeelRepository(db);
}

Future<({KeelRepository repo, String orgId})> freshOrg() async {
  final repo = await freshRepo();
  final org = await repo.createOrganization(name: 'Northwind', kind: 'Studio');
  return (repo: repo, orgId: org.id);
}

Future<(String a, String b, String c)> threePeople(
  KeelRepository repo,
  String orgId,
) async {
  final a = await repo.createPerson(orgId: orgId, name: 'Ann A', roleTitle: 'Lead');
  final b = await repo.createPerson(orgId: orgId, name: 'Ben B', roleTitle: 'Dev');
  final c = await repo.createPerson(orgId: orgId, name: 'Cat C', roleTitle: 'Ops');
  return (a.id, b.id, c.id);
}

void main() {
  group('Rule 1 — assignment is reflexive (TaskAssignee only)', () {
    test('assign from task side shows on person side and back', () async {
      final (repo: repo, orgId: orgId) = await freshOrg();
      final (a, _, _) = await threePeople(repo, orgId);
      final task = await repo.createTask(orgId: orgId, title: 'Ship it');
      await repo.assignPersonToTask(task.id, a);
      expect((await repo.getTasksForPerson(a)).map((t) => t.id), [task.id]);
      expect((await repo.getTaskAssignees(task.id)).map((p) => p.id), [a]);
      // Removing from the person side removes it from the task side.
      await repo.unassignPersonFromTask(task.id, a);
      expect(await repo.getTasksForPerson(a), isEmpty);
      expect(await repo.getTaskAssignees(task.id), isEmpty);
    });
  });

  group('Rule 2 & 3 — teams are many-to-many, person may be in no team', () {
    test('membership written from either side is the same row', () async {
      final (repo: repo, orgId: orgId) = await freshOrg();
      final (a, b, _) = await threePeople(repo, orgId);
      final team = await repo.createTeam(
        orgId: orgId,
        name: 'Design',
        colorHex: '#E5604D',
        leaderPersonId: a,
      );
      await repo.addTeamMember(team.id, b);
      expect((await repo.getTeamMembers(team.id)).map((p) => p.id), containsAll([a, b]));
      expect(
        (await repo.getTeamsForPerson(b)).map((t) => t.id),
        [team.id],
      );
      // A person can be in no team.
      final solo = await repo.createPerson(orgId: orgId, name: 'Solo', roleTitle: '');
      expect(await repo.getTeamsForPerson(solo.id), isEmpty);
    });
  });

  group('Rule 4 — exactly one leader, must be a member', () {
    test('creating a team without a leader throws', () async {
      final (repo: repo, orgId: orgId) = await freshOrg();
      expect(
        () => repo.createTeam(
          orgId: orgId,
          name: 'NoLead',
          colorHex: '#E5604D',
          leaderPersonId: '',
        ),
        throwsA(isA<LeaderRequiredException>()),
      );
    });

    test('leader is auto-added as a member', () async {
      final (repo: repo, orgId: orgId) = await freshOrg();
      final (a, _, _) = await threePeople(repo, orgId);
      final team = await repo.createTeam(
        orgId: orgId,
        name: 'Design',
        colorHex: '#E5604D',
        leaderPersonId: a,
      );
      expect((await repo.getTeamMembers(team.id)).map((p) => p.id), [a]);
    });

    test('removing the leader without a replacement throws', () async {
      final (repo: repo, orgId: orgId) = await freshOrg();
      final (a, b, _) = await threePeople(repo, orgId);
      final team = await repo.createTeam(
        orgId: orgId,
        name: 'Design',
        colorHex: '#E5604D',
        leaderPersonId: a,
        memberIds: [b],
      );
      expect(
        () => repo.removeTeamMember(team.id, a),
        throwsA(isA<LeaderRemovalNeedsReplacement>()),
      );
      // With a replacement it works, and the replacement becomes a member.
      await repo.removeTeamMember(team.id, a, newLeaderId: b);
      final updated = await repo.getTeam(team.id);
      expect(updated!.leaderPersonId, b);
      expect((await repo.getTeamMembers(team.id)).map((p) => p.id), [b]);
    });

    test('deleting the leader person requires replacements', () async {
      final (repo: repo, orgId: orgId) = await freshOrg();
      final (a, b, _) = await threePeople(repo, orgId);
      final team = await repo.createTeam(
        orgId: orgId,
        name: 'Design',
        colorHex: '#E5604D',
        leaderPersonId: a,
        memberIds: [b],
      );
      expect(
        () => repo.deletePerson(a),
        throwsA(isA<LeaderRemovalNeedsReplacement>()),
      );
      await repo.deletePerson(a, leaderReplacements: {team.id: b});
      final updated = await repo.getTeam(team.id);
      expect(updated!.leaderPersonId, b);
      expect(await repo.getPerson(a), isNull);
    });
  });

  group('Rule 5 — at most one main task; progress = done / all', () {
    test('setting a second main task replaces the first', () async {
      final (repo: repo, orgId: orgId) = await freshOrg();
      final (a, _, _) = await threePeople(repo, orgId);
      final team = await repo.createTeam(
        orgId: orgId,
        name: 'Design',
        colorHex: '#E5604D',
        leaderPersonId: a,
      );
      final t1 = await repo.createTask(orgId: orgId, title: 'One', teamId: team.id);
      final t2 = await repo.createTask(orgId: orgId, title: 'Two', teamId: team.id);
      await repo.setMainTask(team.id, t1.id);
      await repo.setMainTask(team.id, t2.id);
      expect((await repo.getTeam(team.id))!.mainTaskId, t2.id);
      expect(await repo.teamProgress(team.id), 0);
      await repo.setTaskDone(t1.id, true);
      expect(await repo.teamProgress(team.id), 0.5);
      await repo.setTaskDone(t2.id, true);
      expect(await repo.teamProgress(team.id), 1.0);
    });
  });

  group('Rule 6 — task can exist alone, team only, people only, or both', () {
    test('all four combinations persist', () async {
      final (repo: repo, orgId: orgId) = await freshOrg();
      final (a, _, _) = await threePeople(repo, orgId);
      final team = await repo.createTeam(
        orgId: orgId,
        name: 'Design',
        colorHex: '#E5604D',
        leaderPersonId: a,
      );
      final alone = await repo.createTask(orgId: orgId, title: 'Alone');
      final teamOnly = await repo.createTask(
        orgId: orgId,
        title: 'Team only',
        teamId: team.id,
      );
      final peopleOnly = await repo.createTask(
        orgId: orgId,
        title: 'People only',
        assigneeIds: [a],
      );
      final both = await repo.createTask(
        orgId: orgId,
        title: 'Both',
        teamId: team.id,
        assigneeIds: [a],
      );
      expect(alone.teamId, isNull);
      expect((await repo.getTaskAssignees(alone.id)), isEmpty);
      expect(teamOnly.teamId, team.id);
      expect(peopleOnly.teamId, isNull);
      expect((await repo.getTaskAssignees(peopleOnly.id)).length, 1);
      expect(both.teamId, team.id);
      expect((await repo.getTaskAssignees(both.id)).length, 1);
    });
  });

  group('Rule 7 — sub-todos and parent completion', () {
    test('all sub-todos done signals the prompt; reopen reopens parent', () async {
      final (repo: repo, orgId: orgId) = await freshOrg();
      final task = await repo.createTask(
        orgId: orgId,
        title: 'Launch',
        subTodoTitles: ['A', 'B'],
      );
      final subs = await repo.getSubTodos(task.id);
      var res = await repo.toggleSubTodo(subs[0].id, true);
      expect(res.allDone, isFalse);
      res = await repo.toggleSubTodo(subs[1].id, true);
      expect(res.allDone, isTrue);
      // Parent is NOT auto-completed — the UI offers the prompt instead.
      expect((await repo.getTask(task.id))!.isDone, isFalse);
      await repo.setTaskDone(task.id, true);
      expect((await repo.getTask(task.id))!.completedAt, isNotNull);
      // Reopening a sub-todo reopens the parent.
      res = await repo.toggleSubTodo(subs[0].id, false);
      expect(res.parentReopened, isTrue);
      final parent = await repo.getTask(task.id);
      expect(parent!.isDone, isFalse);
      expect(parent.completedAt, isNull);
    });
  });

  group('Rule 8 — overdue / due soon', () {
    test('classification by due date', () async {
      final (repo: repo, orgId: orgId) = await freshOrg();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final overdue = await repo.createTask(
        orgId: orgId,
        title: 'Late',
        dueDate: today.subtract(const Duration(days: 1)),
      );
      final soon = await repo.createTask(
        orgId: orgId,
        title: 'Soon',
        dueDate: today.add(const Duration(days: 2)),
      );
      final later = await repo.createTask(
        orgId: orgId,
        title: 'Later',
        dueDate: today.add(const Duration(days: 9)),
      );
      final doneLate = await repo.createTask(
        orgId: orgId,
        title: 'Done late',
        dueDate: today.subtract(const Duration(days: 3)),
      );
      await repo.setTaskDone(doneLate.id, true);
      // Re-fetch: the local object is stale after setTaskDone.
      final doneLateNow = await repo.getTask(doneLate.id);
      expect(isOverdue(overdue), isTrue);
      expect(isOverdue(soon), isFalse);
      expect(isDueSoon(soon), isTrue);
      expect(isDueSoon(later), isFalse);
      expect(isOverdue(doneLateNow!), isFalse); // done tasks are never overdue
      final stats = await repo.homeStats(orgId);
      expect(stats.overdue, 1);
      expect(stats.dueSoon, 1);
    });
  });

  group('Rule 9 — everything is scoped to the active organization', () {
    test('org B sees none of org A data; switching swaps lists', () async {
      final repo = await freshRepo();
      final orgA = await repo.createOrganization(name: 'A', kind: 'Studio');
      final orgB = await repo.createOrganization(name: 'B', kind: 'Club');
      await repo.createTask(orgId: orgA.id, title: 'Only in A');
      await repo.createPerson(orgId: orgA.id, name: 'Only in A', roleTitle: '');
      expect((await repo.getTasks(orgB.id)), isEmpty);
      expect((await repo.getPeople(orgB.id)), isEmpty);
      expect((await repo.getTasks(orgA.id)).length, 1);
      final statsB = await repo.homeStats(orgB.id);
      expect(statsB.total, 0);
    });
  });

  group('Rule 10 — soft delete with Undo; team delete keeps people/tasks', () {
    test('task delete + restore round-trips assignees and sub-todos', () async {
      final (repo: repo, orgId: orgId) = await freshOrg();
      final (a, _, _) = await threePeople(repo, orgId);
      final task = await repo.createTask(
        orgId: orgId,
        title: 'Gone?',
        assigneeIds: [a],
        subTodoTitles: ['Step'],
      );
      final snap = await repo.deleteTask(task.id);
      expect(await repo.getTask(task.id), isNull);
      await repo.restoreSnapshot(snap);
      final restored = await repo.getTask(task.id);
      expect(restored!.title, 'Gone?');
      expect((await repo.getTaskAssignees(task.id)).length, 1);
      expect((await repo.getSubTodos(task.id)).length, 1);
    });

    test('team delete keeps people and tasks (tasks lose the team)', () async {
      final (repo: repo, orgId: orgId) = await freshOrg();
      final (a, b, _) = await threePeople(repo, orgId);
      final team = await repo.createTeam(
        orgId: orgId,
        name: 'Design',
        colorHex: '#E5604D',
        leaderPersonId: a,
        memberIds: [b],
      );
      final task = await repo.createTask(
        orgId: orgId,
        title: 'Survivor',
        teamId: team.id,
      );
      await repo.deleteTeam(team.id);
      expect(await repo.getTeam(team.id), isNull);
      expect(await repo.getPerson(a), isNotNull);
      expect(await repo.getPerson(b), isNotNull);
      final kept = await repo.getTask(task.id);
      expect(kept, isNotNull);
      expect(kept!.teamId, isNull);
    });

    test('person delete removes only assignments and memberships', () async {
      final (repo: repo, orgId: orgId) = await freshOrg();
      final (a, b, _) = await threePeople(repo, orgId);
      final team = await repo.createTeam(
        orgId: orgId,
        name: 'Design',
        colorHex: '#E5604D',
        leaderPersonId: b,
        memberIds: [a],
      );
      final task = await repo.createTask(
        orgId: orgId,
        title: 'Shared',
        teamId: team.id,
        assigneeIds: [a, b],
      );
      await repo.deletePerson(a);
      expect(await repo.getPerson(a), isNull);
      expect(await repo.getPerson(b), isNotNull);
      expect(await repo.getTeam(team.id), isNotNull);
      expect(await repo.getTask(task.id), isNotNull);
      expect(
        (await repo.getTaskAssignees(task.id)).map((p) => p.id),
        [b],
      );
      expect((await repo.getTeamMembers(team.id)).map((p) => p.id), [b]);
    });
  });

  group('Backup validation', () {
    test('invalid payloads are rejected before any data changes', () {
      expect(
        KeelRepository.validateBackup({'format': 'other'}),
        isNotNull,
      );
      expect(
        KeelRepository.validateBackup({'format': 'keel-backup', 'version': 99}),
        isNotNull,
      );
      expect(
        KeelRepository.validateBackup({
          'format': 'keel-backup',
          'version': 1,
          'organizations': [],
          'people': [],
          'teams': [],
          'tasks': [],
          'taskAssignees': [],
          'teamMembers': [],
          'subTodos': [],
        }),
        isNull,
      );
    });

    test('export then import round-trips the dataset', () async {
      final (repo: repo, orgId: orgId) = await freshOrg();
      final (a, _, _) = await threePeople(repo, orgId);
      await repo.createTask(orgId: orgId, title: 'Keep', assigneeIds: [a]);
      final data = await repo.exportAll();
      final repo2 = await freshRepo();
      final summary = await repo2.importAll(data);
      expect(summary.tasks, 1);
      expect(summary.people, 3);
      expect((await repo2.getTasks(orgId)).first.title, 'Keep');
    });
  });
}
