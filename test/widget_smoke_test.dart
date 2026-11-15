import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/db.dart';
import 'package:keel/main.dart';
import 'package:keel/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pumpKeel(WidgetTester tester) async {
  // Phone-sized surface, tall enough that long lists (Home, Settings)
  // build all their children — ListView only builds on-screen widgets.
  tester.view.physicalSize = const Size(1170, 3600);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
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
}

/// Unmount the app and flush Drift's deferred stream-close timers before
/// the test body returns. Drift schedules a `Timer(Duration.zero)` when a
/// watched stream is cancelled (StreamQueryStore.markAsClosed); the test
/// framework unmounts the tree itself after the body and then asserts that
/// no FakeAsync timer is pending, so the timers must be fired first with
/// [WidgetTester.pumpAndSettle]. Without this, any test that reaches Home
/// (where Riverpod StreamProviders watch Drift) fails with "A Timer is
/// still pending even after the widget tree was disposed" — even though
/// the app is correct (a zero timer fires immediately on a real event loop).
Future<void> unmountKeel(WidgetTester tester) async {
  await tester.pumpWidget(Container());
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('onboarding flow completes and lands on Home', (tester) async {
    await pumpKeel(tester);

    // Step 1: welcome + name.
    expect(find.text('Welcome to Keel'), findsOneWidget);
    expect(find.text('What should we call you?'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Alex Morgan');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // Step 2: role + organization.
    expect(find.text('Hi, Alex.'), findsOneWidget);
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), 'Operations Manager');
    await tester.enterText(fields.at(1), 'Northwind Studio');
    await tester.tap(find.text('Create my workspace'));
    await tester.pumpAndSettle();

    // Home: greeting, dial card, empty states.
    expect(find.textContaining('Good'), findsOneWidget);
    expect(find.text('0 of 0 tasks done'), findsOneWidget);
    expect(find.text('Nothing urgent'), findsOneWidget);
    expect(find.text('No teams yet'), findsOneWidget);
    // Tab bar with all five tabs.
    for (final label in ['Home', 'Tasks', 'Teams', 'People', 'Settings']) {
      expect(find.text(label), findsWidgets);
    }
    await unmountKeel(tester);
  });

  testWidgets('onboarding validates empty name and empty org inline', (
    tester,
  ) async {
    await pumpKeel(tester);

    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.text('Tell us your name so we can greet you.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Alex');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create my workspace'));
    await tester.pump();
    expect(find.text('Give your organization a name.'), findsOneWidget);
    // Still on onboarding — Home must not appear.
    expect(find.text('Nothing urgent'), findsNothing);
    await unmountKeel(tester);
  });

  testWidgets('Tasks tab shows empty state and Settings opens', (
    tester,
  ) async {
    await pumpKeel(tester);
    await tester.enterText(find.byType(TextField).first, 'Alex');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), 'Northwind Studio');
    await tester.tap(find.text('Create my workspace'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tasks'));
    await tester.pumpAndSettle();
    expect(find.text('Tasks'), findsWidgets);
    expect(find.text('No tasks yet'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Organizations'), findsOneWidget);
    // Backup and About sit near the bottom of the scrollable Settings
    // list; scroll each into view before expecting it (ListView only
    // builds on-screen children).
    await tester.scrollUntilVisible(find.text('Back up to phone'), 400);
    await tester.pumpAndSettle();
    expect(find.text('Back up to phone'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('About'), 400);
    await tester.pumpAndSettle();
    expect(find.text('About'), findsOneWidget);
    await unmountKeel(tester);
  });
}
