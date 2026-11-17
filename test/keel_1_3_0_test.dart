import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/calendar.dart';
import 'package:keel/db.dart';
import 'package:keel/providers.dart';
import 'package:keel/repo.dart';
import 'package:keel/sheets.dart';
import 'package:keel/task_card.dart';
import 'package:keel/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widget_smoke_test.dart' show pumpKeel, unmountKeel;

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

Task task(
  String id, {
  bool isDone = false,
  DateTime? dueDate,
  DateTime? completedAt,
}) {
  return Task(
    id: id,
    orgId: 'o',
    title: 'Task $id',
    notes: '',
    priority: 'none',
    isDone: isDone,
    completedAt: completedAt,
    dueDate: dueDate,
    createdAt: DateTime(2026, 11, 17),
  );
}

void main() {
  group('1.3.0 — Up next keeps recently completed tasks for ~24h', () {
    test('open tasks first, recently done at the bottom, old done gone', () {
      final now = DateTime(2026, 11, 17, 12);
      final tasks = [
        task('done-recent', isDone: true,
            completedAt: now.subtract(const Duration(hours: 2))),
        task('done-old', isDone: true,
            completedAt: now.subtract(const Duration(hours: 25))),
        task('open-undated'),
        task('open-due-later', dueDate: now.add(const Duration(days: 3))),
        task('open-overdue', dueDate: now.subtract(const Duration(days: 1))),
        task('open-due-tomorrow', dueDate: now.add(const Duration(days: 1))),
      ];
      final result = selectUpNext(tasks, now: now, limit: 10);
      final ids = result.map((t) => t.id).toList();
      // Overdue first, then soonest due, undated last among open tasks.
      expect(ids.sublist(0, 4), [
        'open-overdue',
        'open-due-tomorrow',
        'open-due-later',
        'open-undated',
      ]);
      // The recently completed task drops to the bottom, shown as done.
      expect(ids.last, 'done-recent');
      expect(result.last.isDone, isTrue);
      // Completed more than 24h ago is gone.
      expect(ids, isNot(contains('done-old')));
    });

    test('repo upNext: completed task stays ~24h then disappears', () async {
      final (repo: repo, orgId: orgId) = await freshOrg();
      final open = await repo.createTask(orgId: orgId, title: 'Open');
      final done = await repo.createTask(orgId: orgId, title: 'Done');
      await repo.setTaskDone(done.id, true);

      var next = await repo.upNext(orgId);
      expect(next.map((t) => t.id), [open.id, done.id]);
      expect(next.last.isDone, isTrue);

      // Backdate the completion past 24h: the task must drop out.
      await (repo.db.update(repo.db.tasks)
            ..where((t) => t.id.equals(done.id)))
          .write(
        TasksCompanion(
          completedAt: Value(DateTime.now().subtract(const Duration(hours: 25))),
        ),
      );
      next = await repo.upNext(orgId);
      expect(next.map((t) => t.id), [open.id]);
    });
  });

  group('1.3.0 — Day notes', () {
    test('save / get / watch / delete, scoped per organization', () async {
      final (repo: repo, orgId: orgId) = await freshOrg();
      final other = await repo.createOrganization(name: 'Other', kind: 'Club');

      expect(await repo.getDayNote(orgId, '2026-11-17'), isNull);
      await repo.saveDayNote(orgId, '2026-11-17', 'Diwali prep');
      expect((await repo.getDayNote(orgId, '2026-11-17'))?.note, 'Diwali prep');
      // Same date in another org is a different note.
      expect(await repo.getDayNote(other.id, '2026-11-17'), isNull);
      // Saving an empty note deletes the row.
      await repo.saveDayNote(orgId, '2026-11-17', '   ');
      expect(await repo.getDayNote(orgId, '2026-11-17'), isNull);
    });

    test('dayKey formats local dates as yyyy-MM-dd', () {
      expect(dayKey(DateTime(2026, 11, 17, 23, 59)), '2026-11-17');
      expect(dayKey(DateTime(2026, 1, 5)), '2026-01-05');
    });

    test('backup v2 round-trips day notes; v1 backup still imports', () async {
      final (repo: repo, orgId: orgId) = await freshOrg();
      await repo.createTask(orgId: orgId, title: 'Ship it');
      await repo.saveDayNote(orgId, '2026-11-17', 'Diwali prep');

      final payload = await repo.exportAll();
      expect(payload['version'], 2);
      expect((payload['dayNotes'] as List).length, 1);
      expect(KeelRepository.validateBackup(payload), isNull);

      final repo2 = await freshRepo();
      await repo2.importAll(payload);
      final orgs2 = await repo2.getOrganizations();
      expect(orgs2.length, 1);
      expect(
        (await repo2.getDayNote(orgs2.first.id, '2026-11-17'))?.note,
        'Diwali prep',
      );

      // A v1 payload (no dayNotes key) still validates and imports.
      final v1 = Map<String, dynamic>.from(payload)
        ..['version'] = 1
        ..remove('dayNotes');
      expect(KeelRepository.validateBackup(v1), isNull);
      final repo3 = await freshRepo();
      await repo3.importAll(v1);
      expect(await repo3.getOrganizations(), hasLength(1));
      expect(
        await repo3.getDayNote(
          (await repo3.getOrganizations()).first.id,
          '2026-11-17',
        ),
        isNull,
      );
    });

    test('migration 1 -> 2 keeps v1 data and adds day_notes', () async {
      final dir = await Directory.systemTemp.createTemp('keel-mig-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/keel.sqlite');

      // Build a v1 database: create with the v2 code, seed it, then
      // downgrade it — v1 had exactly the same tables minus day_notes,
      // and the same indexes minus idx_day_notes_org_date.
      final db = AppDatabase.forTesting(NativeDatabase(file));
      final repo = KeelRepository(db);
      final org = await repo.createOrganization(name: 'Northwind', kind: 'Studio');
      final person = await repo.createPerson(orgId: org.id, name: 'Ann A', roleTitle: 'Lead');
      final task1 = await repo.createTask(
        orgId: org.id,
        title: 'Ship it',
        dueDate: DateTime(2026, 11, 18),
      );
      await db.customStatement('DROP TABLE day_notes');
      await db.customStatement('DROP INDEX IF EXISTS idx_day_notes_org_date');
      await db.customStatement('PRAGMA user_version = 1');
      await db.close();

      // Reopen: the migration must run, non-destructively.
      final db2 = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(db2.close);
      final repo2 = KeelRepository(db2);
      expect((await repo2.getOrganizations()).map((o) => o.id), [org.id]);
      expect((await repo2.getPeople(org.id)).map((p) => p.id), [person.id]);
      final kept = await repo2.getTask(task1.id);
      expect(kept?.title, 'Ship it');
      expect(kept?.dueDate, DateTime(2026, 11, 18));
      final versionRows = await db2.customSelect('PRAGMA user_version').get();
      expect(versionRows.first.data['user_version'], 2);
      // The new table works.
      await repo2.saveDayNote(org.id, '2026-11-17', 'Migrated note');
      expect((await repo2.getDayNote(org.id, '2026-11-17'))?.note,
          'Migrated note');
    });
  });

  group('1.3.0 — Calendar helpers', () {
    test('calendarGridDays: 42 consecutive days starting on week start', () {
      // November 2026: the 1st is a Sunday.
      final sunday = calendarGridDays(DateTime(2026, 11, 1), 'sunday');
      expect(sunday.length, 42);
      expect(sunday.first, DateTime(2026, 11, 1));
      expect(sunday[6], DateTime(2026, 11, 7));
      final monday = calendarGridDays(DateTime(2026, 11, 1), 'monday');
      expect(monday.first, DateTime(2026, 10, 26));
      final saturday = calendarGridDays(DateTime(2026, 11, 1), 'saturday');
      expect(saturday.first, DateTime(2026, 10, 31));
      // Consecutive days, and the 1st of the month is inside the grid.
      for (var i = 1; i < 42; i++) {
        expect(sunday[i].difference(sunday[i - 1]), const Duration(days: 1));
      }
      expect(sunday, contains(DateTime(2026, 11, 1)));
    });

    test('tasksByDay: only open dated tasks, grouped by day', () {
      final tasks = [
        task('a', dueDate: DateTime(2026, 11, 17)),
        task('b', dueDate: DateTime(2026, 11, 17)),
        task('c', dueDate: DateTime(2026, 11, 18)),
        task('done', isDone: true, dueDate: DateTime(2026, 11, 17)),
        task('undated'),
      ];
      final byDay = tasksByDay(tasks);
      expect(byDay['2026-11-17']!.map((t) => t.id), ['a', 'b']);
      expect(byDay['2026-11-18']!.map((t) => t.id), ['c']);
      expect(byDay.length, 2);
    });

    test('dayTasks: open first, recently done at the bottom, old done gone',
        () {
      final now = DateTime(2026, 11, 17, 12);
      final day = DateTime(2026, 11, 17);
      final tasks = [
        task(
          'done-recent',
          isDone: true,
          dueDate: day,
          completedAt: now.subtract(const Duration(hours: 2)),
        ),
        task(
          'done-older',
          isDone: true,
          dueDate: day,
          completedAt: now.subtract(const Duration(hours: 20)),
        ),
        task(
          'done-old',
          isDone: true,
          dueDate: day,
          completedAt: now.subtract(const Duration(hours: 25)),
        ),
        task('open-a', dueDate: day),
        task('open-b', dueDate: day),
        task(
          'done-other-day',
          isDone: true,
          dueDate: DateTime(2026, 11, 18),
          completedAt: now.subtract(const Duration(hours: 1)),
        ),
        task('open-other-day', dueDate: DateTime(2026, 11, 18)),
      ];
      final result = dayTasks(tasks, day, now: now);
      expect(
        result.map((t) => t.id).toList(),
        ['open-a', 'open-b', 'done-recent', 'done-older'],
      );
      // Dots are unchanged: tasksByDay still sees open tasks only.
      expect(tasksByDay(tasks)['2026-11-17']!.map((t) => t.id), [
        'open-a',
        'open-b',
      ]);
    });

    test('dayTasks: only a recently done task lists it; only an old one lists nothing',
        () {
      final now = DateTime(2026, 11, 17, 12);
      final day = DateTime(2026, 11, 17);
      expect(
        dayTasks(
          [
            task(
              'done-recent',
              isDone: true,
              dueDate: day,
              completedAt: now.subtract(const Duration(hours: 1)),
            ),
          ],
          day,
          now: now,
        ).map((t) => t.id),
        ['done-recent'],
      );
      expect(
        dayTasks(
          [
            task(
              'done-old',
              isDone: true,
              dueDate: day,
              completedAt: now.subtract(const Duration(days: 2)),
            ),
          ],
          day,
          now: now,
        ),
        isEmpty,
      );
    });
  });

  group('1.3.0 — Edit sheets reuse the create sheets', () {
    Future<({KeelRepository repo, String orgId, Team team, Person person})>
        seed() async {
      final (repo: repo, orgId: orgId) = await freshOrg();
      final leader = await repo.createPerson(
        orgId: orgId,
        name: 'Ann A',
        roleTitle: 'Lead',
      );
      final member = await repo.createPerson(
        orgId: orgId,
        name: 'Ben B',
        roleTitle: 'Dev',
      );
      final team = await repo.createTeam(
        orgId: orgId,
        name: 'Design',
        colorHex: '#E5604D',
        leaderPersonId: leader.id,
      );
      await repo.addTeamMember(team.id, member.id);
      final task1 = await repo.createTask(orgId: orgId, title: 'Ship it');
      await repo.setMainTask(team.id, task1.id);
      return (repo: repo, orgId: orgId, team: team, person: leader);
    }

    Future<void> pumpHost(
      WidgetTester tester,
      AppDatabase db,
      void Function(BuildContext context) openSheet,
    ) async {
      tester.view.physicalSize = const Size(1170, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
          child: MaterialApp(
            theme: keelThemeData(
              brightness: Brightness.light,
              accent: KeelTokens.accentLight,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () => openSheet(context),
                    child: const Text('Open sheet'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> unmount(WidgetTester tester) async {
      await tester.pumpWidget(Container());
      await tester.pumpAndSettle();
    }

    testWidgets('edit team opens the create sheet pre-filled', (tester) async {
      final s = await seed();
      await pumpHost(
        tester,
        s.repo.db,
        (context) => showNewTeamSheet(
          context,
          orgId: s.orgId,
          existing: s.team,
        ),
      );
      await tester.tap(find.text('Open sheet'));
      await tester.pumpAndSettle();

      expect(find.text('Edit team'), findsOneWidget);
      expect(find.text('Design'), findsOneWidget);
      expect(find.text('Save changes'), findsOneWidget);
      // The main task is shown pre-filled.
      expect(find.text('Ship it'), findsOneWidget);
      // Saving closes the sheet.
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(find.text('Edit team'), findsNothing);
      await unmount(tester);
    });

    testWidgets('edit person opens the create sheet pre-filled',
        (tester) async {
      final s = await seed();
      await pumpHost(
        tester,
        s.repo.db,
        (context) => showNewPersonSheet(
          context,
          orgId: s.orgId,
          existing: s.person,
        ),
      );
      await tester.tap(find.text('Open sheet'));
      await tester.pumpAndSettle();

      expect(find.text('Edit person'), findsOneWidget);
      expect(find.text('Ann A'), findsOneWidget);
      expect(find.text('Lead'), findsOneWidget);
      expect(find.text('Save changes'), findsOneWidget);
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(find.text('Edit person'), findsNothing);
      await unmount(tester);
    });

    testWidgets('new organization sheet offers the five kinds',
        (tester) async {
      final s = await seed();
      await pumpHost(
        tester,
        s.repo.db,
        (context) => showNewOrganizationSheet(context),
      );
      await tester.tap(find.text('Open sheet'));
      await tester.pumpAndSettle();

      expect(find.text('New organization'), findsOneWidget);
      for (final kind in ['Studio', 'Company', 'Club', 'Family', 'Other']) {
        expect(find.text(kind), findsOneWidget);
      }
      await tester.tap(find.text('Club'));
      await tester.enterText(find.byType(TextField), 'Fest Club');
      await tester.tap(find.text('Create organization'));
      await tester.pumpAndSettle();

      final orgs = await s.repo.getOrganizations();
      expect(orgs.map((o) => o.kind), contains('Club'));
      expect(orgs.map((o) => o.name), contains('Fest Club'));
      await unmount(tester);
    });

    testWidgets('task card shows only the next sub-todo plus a count',
        (tester) async {
      final (repo: repo, orgId: orgId) = await freshOrg();
      final task1 = await repo.createTask(
        orgId: orgId,
        title: 'Ship it',
        subTodoTitles: ['Draft', 'Review', 'Publish'],
      );
      final subs = await repo.getSubTodos(task1.id);
      await repo.toggleSubTodo(subs.first.id, true);
      final fresh = (await repo.getTask(task1.id))!;

      await pumpHost(
        tester,
        repo.db,
        (context) => showDialog<void>(
          context: context,
          builder: (context) => Dialog(
            child: TaskCard(
              task: fresh,
              team: null,
              onTap: () {},
              onOpenPage: () {},
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open sheet'));
      await tester.pumpAndSettle();

      expect(find.text('Review'), findsOneWidget);
      expect(find.text('1 of 3 done'), findsOneWidget);
      // The done one and the later ones are not listed on the card.
      expect(find.text('Draft'), findsNothing);
      expect(find.text('Publish'), findsNothing);
      await unmount(tester);
    });
  });

  group('1.3.0 — Merged Teams tab + Calendar tab', () {
    testWidgets('Teams tab has Teams | People sub-tabs; Calendar opens',
        (tester) async {
      await pumpKeel(tester);

      // Complete onboarding to reach the shell.
      await tester.enterText(find.byType(TextField).first, 'Alex');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(1), 'Northwind Studio');
      await tester.tap(find.text('Create my workspace'));
      await tester.pumpAndSettle();

      // The tab bar sits last in the tree, after the offstage tabs.
      await tester.tap(find.text('Teams').last);
      await tester.pumpAndSettle();
      // The merged tab's People segment is the only hit-testable
      // 'People' text (Home's stat tile is offstage now).
      expect(find.text('People').hitTestable(), findsOneWidget);

      await tester.tap(find.text('People').hitTestable());
      await tester.pumpAndSettle();
      // The People sub-tab is showing: its empty state and live search.
      expect(find.text('No people yet'), findsOneWidget);
      expect(find.text('Search people'), findsOneWidget);

      await tester.tap(find.text('Calendar'));
      await tester.pumpAndSettle();
      expect(find.text('November 2026'), findsOneWidget);
      await unmountKeel(tester);
    });
  });
}
