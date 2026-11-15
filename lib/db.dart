import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'db.g.dart';

// ---------------------------------------------------------------------------
// Tables — exactly the data model in section 4 of the master prompt.
// ---------------------------------------------------------------------------

class Organizations extends Table {
  TextColumn get id => text()();

  TextColumn get name => text()();

  /// Studio, Company, Club, Family, Other
  TextColumn get kind => text()();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class Profiles extends Table {
  /// Single row, id = 'profile'.
  TextColumn get id => text()();

  TextColumn get name => text()();

  /// Single, global role.
  TextColumn get role => text()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Person')
class People extends Table {
  TextColumn get id => text()();

  TextColumn get orgId => text().references(Organizations, #id)();

  TextColumn get name => text()();

  TextColumn get roleTitle => text()();

  /// App-private file path only; the photo itself lives in app storage.
  TextColumn get photoPath => text().nullable()();

  TextColumn get notes => text().withDefault(const Constant(''))();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class PersonPhones extends Table {
  TextColumn get id => text()();

  TextColumn get personId =>
      text().references(People, #id, onDelete: KeyAction.cascade)();

  /// mobile, work, home, other
  TextColumn get label => text()();

  TextColumn get number => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class PersonEmails extends Table {
  TextColumn get id => text()();

  TextColumn get personId =>
      text().references(People, #id, onDelete: KeyAction.cascade)();

  TextColumn get label => text()();

  TextColumn get address => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class Teams extends Table {
  TextColumn get id => text()();

  TextColumn get orgId => text().references(Organizations, #id)();

  TextColumn get name => text()();

  TextColumn get colorHex => text()();

  /// Required; must be a member (enforced in the repository).
  TextColumn get leaderPersonId => text().references(People, #id)();

  TextColumn get mainTaskId =>
      text().nullable().references(Tasks, #id, onDelete: KeyAction.setNull)();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class TeamMembers extends Table {
  TextColumn get teamId =>
      text().references(Teams, #id, onDelete: KeyAction.cascade)();

  TextColumn get personId =>
      text().references(People, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {teamId, personId};
}

class Tasks extends Table {
  TextColumn get id => text()();

  TextColumn get orgId => text().references(Organizations, #id)();

  TextColumn get title => text()();

  TextColumn get notes => text().withDefault(const Constant(''))();

  DateTimeColumn get dueDate => dateTime().nullable()();

  /// none, low, medium, high
  TextColumn get priority => text().withDefault(const Constant('none'))();

  /// Nullable. Deleting a team sets this to NULL (tasks survive).
  TextColumn get teamId =>
      text().nullable().references(Teams, #id, onDelete: KeyAction.setNull)();

  BoolColumn get isDone => boolean().withDefault(const Constant(false))();

  DateTimeColumn get completedAt => dateTime().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// The ONLY assignment table (logic rule 1).
class TaskAssignees extends Table {
  TextColumn get taskId =>
      text().references(Tasks, #id, onDelete: KeyAction.cascade)();

  TextColumn get personId =>
      text().references(People, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {taskId, personId};
}

class SubTodos extends Table {
  TextColumn get id => text()();

  TextColumn get taskId =>
      text().references(Tasks, #id, onDelete: KeyAction.cascade)();

  TextColumn get title => text()();

  BoolColumn get isDone => boolean().withDefault(const Constant(false))();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Database
// ---------------------------------------------------------------------------

@DriftDatabase(
  tables: [
    Organizations,
    Profiles,
    People,
    PersonPhones,
    PersonEmails,
    Teams,
    TeamMembers,
    Tasks,
    TaskAssignees,
    SubTodos,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  static LazyDatabase _openConnection() {
    return LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'keel.sqlite'));
      // Queries run on a background isolate, never on the UI thread:
      // scrolling a 1000-task list must never wait on SQLite. (Drift's
      // plain NativeDatabase runs on the calling — UI — isolate.)
      return NativeDatabase.createInBackground(file);
    });
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createIndexes(m);
        },
        onUpgrade: (m, from, to) async {
          // v1 is the first shipped schema; future versions add steps here
          // and must never drop user data.
          if (from < 1) {
            await m.createAll();
            await _createIndexes(m);
          }
        },
        beforeOpen: (details) async {
          // Foreign keys on: every relation above depends on them.
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  Future<void> _createIndexes(Migrator m) async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_tasks_org_done ON tasks (org_id, is_done)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_tasks_org_due ON tasks (org_id, due_date)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_tasks_team ON tasks (team_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_people_org ON people (org_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_teams_org ON teams (org_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_team_members_person ON team_members (person_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_task_assignees_person ON task_assignees (person_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_subtodos_task ON sub_todos (task_id, sort_order)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_phones_person ON person_phones (person_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_emails_person ON person_emails (person_id)',
    );
  }
}
