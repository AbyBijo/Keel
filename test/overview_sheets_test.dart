import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/db.dart';
import 'package:keel/providers.dart';
import 'package:keel/repo.dart';
import 'package:keel/sheets.dart';
import 'package:keel/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One org + two people + one team + one task, in an in-memory DB.
/// The repo's `db` is handed to the ProviderScope override.
Future<({KeelRepository repo, String orgId, Task task, Person person})>
seed() async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  final repo = KeelRepository(db);
  final org = await repo.createOrganization(name: 'Northwind', kind: 'Studio');
  final leader = await repo.createPerson(
    orgId: org.id,
    name: 'Ann A',
    roleTitle: 'Design Lead',
    phones: const [(label: 'mobile', number: '+91 85903 86329')],
  );
  final member = await repo.createPerson(
    orgId: org.id,
    name: 'Ben B',
    roleTitle: 'Developer',
  );
  final team = await repo.createTeam(
    orgId: org.id,
    name: 'Design',
    colorHex: '#E5604D',
    leaderPersonId: leader.id,
    memberIds: [member.id],
  );
  final task = await repo.createTask(
    orgId: org.id,
    title: 'Ship the new dashboard',
    notes: 'Needs the final review before Friday.',
    dueDate: DateTime.now().add(const Duration(days: 1)),
    priority: 'high',
    teamId: team.id,
    assigneeIds: [leader.id, member.id],
    subTodoTitles: ['Draft', 'Review'],
  );
  return (repo: repo, orgId: org.id, task: task, person: leader);
}

/// Pumps a bare host: a button that opens the sheet under test.
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
  // 1.3.0: sheets now reconcile notification reminders on
  // Complete/Delete, which reads settings — so the harness must
  // provide mock SharedPreferences, like pumpKeel does.
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

void main() {
  testWidgets('task overview sheet shows summary + quick actions, Complete works',
      (tester) async {
    final s = await seed();
    await pumpHost(
      tester,
      s.repo.db,
      (context) => showTaskOverviewSheet(
        context,
        task: s.task,
        orgId: s.orgId,
        onOpenTeamPage: (_) {},
      ),
    );

    await tester.tap(find.text('Open sheet'));
    await tester.pumpAndSettle();

    expect(find.text('Ship the new dashboard'), findsOneWidget);
    expect(find.text('Needs the final review before Friday.'), findsOneWidget);
    // Due row is one Text: "Tomorrow · 16/11/2026" (label + date).
    expect(find.textContaining('Tomorrow'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);
    expect(find.text('Draft'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('0 of 2 sub-tasks done'), findsOneWidget);
    expect(find.text('Ann A'), findsOneWidget);
    expect(find.text('Ben B'), findsOneWidget);
    expect(find.text('Team: Design'), findsOneWidget);
    expect(find.text('Complete'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);

    // Quick action: Complete marks the task done (live, via the stream).
    await tester.tap(find.text('Complete'));
    await tester.pumpAndSettle();
    expect((await s.repo.getTask(s.task.id))?.isDone, isTrue);
    expect(find.text('Reopen'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('person overview sheet shows Call + Message on the right',
      (tester) async {
    final s = await seed();
    await pumpHost(
      tester,
      s.repo.db,
      (context) => showPersonOverviewSheet(
        context,
        person: s.person,
        orgId: s.orgId,
      ),
    );

    await tester.tap(find.text('Open sheet'));
    await tester.pumpAndSettle();

    expect(find.text('Ann A'), findsOneWidget);
    expect(find.text('Design Lead'), findsOneWidget);
    expect(find.text('+91 85903 86329'), findsOneWidget);
    expect(find.text('Design'), findsOneWidget);
    expect(find.text('Call'), findsOneWidget);
    expect(find.text('Message'), findsOneWidget);
    await unmount(tester);
  });
}
