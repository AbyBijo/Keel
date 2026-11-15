import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/db.dart';
import 'package:keel/main.dart';
import 'package:keel/providers.dart';
import 'package:keel/repo.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regression tests for the "new people don't appear instantly" bug
/// (v1.2.0 fix): the Persons list used to come from a one-shot
/// FutureProvider, so it went stale after any insert and only refreshed
/// on a full restart. It now comes from a live StreamProvider, so the
/// list must rebuild from the database on every add — without the
/// screen being rebuilt or the app restarted.
void main() {
  Future<KeelRepository> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 3600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    SharedPreferences.setMockInitialValues({'onboarding_done': true});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = KeelRepository(db);
    await repo.createOrganization(name: 'Northwind', kind: 'Studio');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          databaseProvider.overrideWithValue(db),
        ],
        child: const KeelApp(),
      ),
    );
    await tester.pumpAndSettle();
    return repo;
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(Container());
    await tester.pumpAndSettle();
  }

  testWidgets('new person appears on the People tab without rebuilding',
      (tester) async {
    final repo = await pumpApp(tester);

    // Open the People tab via the tab bar label (the last 'People'
    // text in the tree — the stat tile's label comes first).
    await tester.tap(find.text('People').last);
    await tester.pumpAndSettle();
    expect(find.text('No people yet'), findsOneWidget);

    // Add a person from outside the screen — no rebuild, no restart.
    final org = (await repo.getOrganizations()).first;
    await repo.createPerson(
      orgId: org.id,
      name: 'Cara C',
      roleTitle: 'Designer',
    );
    await tester.pumpAndSettle();
    expect(find.text('Cara C'), findsOneWidget);
    expect(find.text('No people yet'), findsNothing);
    await unmount(tester);
  });

  testWidgets(
      'person created from the Create Team sheet appears on the People tab',
      (tester) async {
    await pumpApp(tester);

    // Teams tab via the tab bar label (last 'Teams' text in the tree).
    await tester.tap(find.text('Teams').last);
    await tester.pumpAndSettle();

    // Open the Create Team sheet via the header add button (its
    // tooltip string lives in a Semantics label, not a Tooltip).
    await tester.tap(find.bySemanticsLabel('Add a team'));
    await tester.pumpAndSettle();
    expect(find.text('New team'), findsOneWidget);

    // Team name.
    await tester.enterText(find.byType(TextField).first, 'Design');
    // Create a person inline, from inside the team sheet.
    await tester.tap(find.text('Or create a person first'));
    await tester.pumpAndSettle();
    expect(find.text('New person'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Dana D');
    await tester.tap(find.text('Add person'));
    await tester.pumpAndSettle();

    // Back in the team sheet: pick the new person as leader.
    await tester.tap(find.text('Choose a leader'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dana D'));
    await tester.pumpAndSettle();
    // Create the team.
    await tester.tap(find.text('Create team'));
    await tester.pumpAndSettle();

    // People tab: the person must be there, without any restart.
    await tester.tap(find.text('People').last);
    await tester.pumpAndSettle();
    expect(find.text('Dana D'), findsOneWidget);
    await unmount(tester);
  });
}
