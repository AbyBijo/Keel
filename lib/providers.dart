import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'db.dart';
import 'repo.dart';
import 'theme.dart';

// ---------------------------------------------------------------------------
// Core singletons
// ---------------------------------------------------------------------------

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final repositoryProvider = Provider<KeelRepository>((ref) {
  return KeelRepository(ref.watch(databaseProvider));
});

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences must be overridden in main()');
});

// ---------------------------------------------------------------------------
// Settings (SharedPreferences-backed, Riverpod StateNotifier)
// ---------------------------------------------------------------------------

class KeelSettings extends ChangeNotifier {
  final SharedPreferences _prefs;
  KeelSettings(this._prefs);

  static const _kOnboardingDone = 'onboarding_done';
  static const _kActiveOrg = 'active_org_id';
  static const _kThemeMode = 'theme_mode'; // system | light | dark
  static const _kTextScale = 'text_scale';
  static const _kReduceMotion = 'reduce_motion';
  static const _kAccent = 'accent_hex';
  static const _kReminders = 'reminders_on';
  static const _kHaptics = 'haptics_on';
  static const _kHapticStrength = 'haptic_strength'; // light | medium | heavy
  static const _kWeekStart = 'week_start'; // monday | saturday | sunday
  static const _kDigestHour = 'digest_hour';
  static const _kDigestMinute = 'digest_minute';
  static const _kLastBackup = 'last_backup_iso';
  static const _kHomeSeen = 'home_seen_once';

  bool get onboardingDone => _prefs.getBool(_kOnboardingDone) ?? false;
  String? get activeOrgId => _prefs.getString(_kActiveOrg);
  String get themeMode => _prefs.getString(_kThemeMode) ?? 'system';
  double get textScale => _prefs.getDouble(_kTextScale) ?? 1.0;
  bool get reduceMotion => _prefs.getBool(_kReduceMotion) ?? false;
  String? get accentHex => _prefs.getString(_kAccent);
  bool get remindersOn => _prefs.getBool(_kReminders) ?? false;
  bool get hapticsOn => _prefs.getBool(_kHaptics) ?? true;
  String get hapticStrength => _prefs.getString(_kHapticStrength) ?? 'medium';
  String get weekStart => _prefs.getString(_kWeekStart) ?? 'monday';
  int get digestHour => _prefs.getInt(_kDigestHour) ?? 8;
  int get digestMinute => _prefs.getInt(_kDigestMinute) ?? 0;
  DateTime? get lastBackup {
    final s = _prefs.getString(_kLastBackup);
    return s == null ? null : DateTime.tryParse(s);
  }

  bool get homeSeenOnce => _prefs.getBool(_kHomeSeen) ?? false;

  ThemeMode get themeModeValue => switch (themeMode) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  Color get accent =>
      accentHex == null ? KeelTokens.accentLight : KeelTokens.colorFromHex(accentHex!);

  Future<void> setOnboardingDone() async {
    await _prefs.setBool(_kOnboardingDone, true);
    notifyListeners();
  }

  Future<void> setActiveOrg(String? id) async {
    if (id == null) {
      await _prefs.remove(_kActiveOrg);
    } else {
      await _prefs.setString(_kActiveOrg, id);
    }
    notifyListeners();
  }

  Future<void> setThemeMode(String mode) async {
    await _prefs.setString(_kThemeMode, mode);
    notifyListeners();
  }

  Future<void> setTextScale(double v) async {
    await _prefs.setDouble(_kTextScale, v);
    notifyListeners();
  }

  Future<void> setReduceMotion(bool v) async {
    await _prefs.setBool(_kReduceMotion, v);
    notifyListeners();
  }

  Future<void> setAccent(String? hex) async {
    if (hex == null) {
      await _prefs.remove(_kAccent);
    } else {
      await _prefs.setString(_kAccent, hex);
    }
    notifyListeners();
  }

  Future<void> setReminders(bool v) async {
    await _prefs.setBool(_kReminders, v);
    notifyListeners();
  }

  Future<void> setHaptics(bool v) async {
    await _prefs.setBool(_kHaptics, v);
    notifyListeners();
  }

  Future<void> setHapticStrength(String v) async {
    await _prefs.setString(_kHapticStrength, v);
    notifyListeners();
  }

  Future<void> setWeekStart(String v) async {
    await _prefs.setString(_kWeekStart, v);
    notifyListeners();
  }

  Future<void> setDigestTime(int hour, int minute) async {
    await _prefs.setInt(_kDigestHour, hour);
    await _prefs.setInt(_kDigestMinute, minute);
    notifyListeners();
  }

  Future<void> setLastBackup(DateTime when) async {
    await _prefs.setString(_kLastBackup, when.toIso8601String());
    notifyListeners();
  }

  Future<void> markHomeSeen() async {
    await _prefs.setBool(_kHomeSeen, true);
    notifyListeners();
  }
}

final settingsProvider = ChangeNotifierProvider<KeelSettings>((ref) {
  return KeelSettings(ref.watch(sharedPreferencesProvider));
});

// ---------------------------------------------------------------------------
// Active organization
// ---------------------------------------------------------------------------

/// The active org id, resolved: stored preference if it still exists,
/// otherwise the first organization, otherwise null.
final activeOrgProvider = StreamProvider<String?>((ref) async* {
  final repo = ref.watch(repositoryProvider);
  final settings = ref.watch(settingsProvider);
  await for (final orgs in repo.watchOrganizations()) {
    if (orgs.isEmpty) {
      yield null;
    } else {
      final stored = settings.activeOrgId;
      if (stored != null && orgs.any((o) => o.id == stored)) {
        yield stored;
      } else {
        yield orgs.first.id;
      }
    }
  }
});

// ---------------------------------------------------------------------------
// Data streams, all scoped to the active organization (rule 9)
// ---------------------------------------------------------------------------

final profileProvider = StreamProvider((ref) {
  return ref.watch(repositoryProvider).watchProfile();
});

final organizationsProvider = StreamProvider((ref) {
  return ref.watch(repositoryProvider).watchOrganizations();
});

final teamsProvider = StreamProvider.family<List<Team>, String>((ref, orgId) {
  return ref.watch(repositoryProvider).watchTeams(orgId);
});

final peopleProvider = StreamProvider.family<List<Person>, String>((
  ref,
  orgId,
) {
  return ref.watch(repositoryProvider).watchPeople(orgId);
});

final tasksProvider = StreamProvider.family<List<Task>, String>((ref, orgId) {
  return ref.watch(repositoryProvider).watchTasks(orgId);
});

final teamMembersProvider = StreamProvider.family<List<Person>, String>((
  ref,
  teamId,
) async* {
  final repo = ref.watch(repositoryProvider);
  // Re-emit whenever membership rows change.
  await for (final _ in repo.watchTeamMembers(teamId)) {
    yield await repo.getTeamMembers(teamId);
  }
});

final taskAssigneesProvider = StreamProvider.family<List<Person>, String>((
  ref,
  taskId,
) async* {
  final repo = ref.watch(repositoryProvider);
  await for (final _ in repo.watchTaskAssignees(taskId)) {
    yield await repo.getTaskAssignees(taskId);
  }
});

/// Live search for the People tab (name, role, phone, email, team).
/// A StreamProvider, NOT a FutureProvider: the list must re-emit
/// whenever any table it reads changes. As a one-shot FutureProvider
/// it cached its first result forever, so a person added from the
/// People tab or from the Create Team sheet never appeared until the
/// app was restarted (the Shell keeps all tabs alive in an
/// IndexedStack, so the screen is never rebuilt on tab switches).
/// A provider (not a FutureBuilder in the list) so the list below can
/// stay a lazy SliverList. Phones/emails/teams are fetched in bulk,
/// once per recompute — never one query per person.
final filteredPeopleProvider =
    StreamProvider.family<List<Person>, ({String orgId, String query})>((
  ref,
  args,
) async* {
  final repo = ref.watch(repositoryProvider);
  // Recompute whenever people, phones, emails, memberships or teams
  // change — the search matches across all of them.
  await for (final _ in _peopleSearchTrigger(repo, args.orgId)) {
    yield await _filterPeople(repo, args.orgId, args.query);
  }
});

/// Merges the Drift watch streams the people search reads into one
/// void trigger stream. Each Drift watch emits immediately with its
/// current rows, so the first recompute happens right away.
Stream<void> _peopleSearchTrigger(KeelRepository repo, String orgId) {
  final controller = StreamController<void>();
  void emit(_) {
    if (!controller.isClosed) controller.add(null);
  }

  final subs = <StreamSubscription>[
    repo.watchPeople(orgId).listen(emit),
    repo.db.select(repo.db.personPhones).watch().listen(emit),
    repo.db.select(repo.db.personEmails).watch().listen(emit),
    repo.db.select(repo.db.teamMembers).watch().listen(emit),
    repo.watchTeams(orgId).listen(emit),
  ];
  controller.onCancel = () async {
    for (final sub in subs) {
      await sub.cancel();
    }
  };
  return controller.stream;
}

Future<List<Person>> _filterPeople(
  KeelRepository repo,
  String orgId,
  String query,
) async {
  final people = await repo.getPeople(orgId);
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return people;
  final phones = await repo.db.select(repo.db.personPhones).get();
  final emails = await repo.db.select(repo.db.personEmails).get();
  final memberships = await repo.db.select(repo.db.teamMembers).get();
  final teams = await repo.getTeams(orgId);
  final teamNameById = {for (final t in teams) t.id: t.name};
  final phonesByPerson = <String, List<String>>{};
  for (final ph in phones) {
    (phonesByPerson[ph.personId] ??= []).add(ph.number);
  }
  final emailsByPerson = <String, List<String>>{};
  for (final em in emails) {
    (emailsByPerson[em.personId] ??= []).add(em.address);
  }
  final teamNamesByPerson = <String, List<String>>{};
  for (final m in memberships) {
    final name = teamNameById[m.teamId];
    if (name != null) (teamNamesByPerson[m.personId] ??= []).add(name);
  }
  return people.where((p) {
    if (p.name.toLowerCase().contains(q) ||
        p.roleTitle.toLowerCase().contains(q)) {
      return true;
    }
    final hay = [
      ...(phonesByPerson[p.id] ?? const []),
      ...(emailsByPerson[p.id] ?? const []),
      ...(teamNamesByPerson[p.id] ?? const []),
    ].join(' ').toLowerCase();
    return hay.contains(q);
  }).toList();
}

/// One task, live — used by the task overview sheet and the task page.
final taskProvider = StreamProvider.family<Task?, String>((ref, taskId) {
  return ref.watch(repositoryProvider).watchTask(taskId);
});

final subTodosProvider = StreamProvider.family<List<SubTodo>, String>((
  ref,
  taskId,
) {
  return ref.watch(repositoryProvider).watchSubTodos(taskId);
});

final personTeamsProvider = StreamProvider.family<List<Team>, String>((
  ref,
  personId,
) async* {
  final repo = ref.watch(repositoryProvider);
  await for (final _ in repo.watchTeamsForPerson(personId)) {
    yield await repo.getTeamsForPerson(personId);
  }
});

final personTasksProvider = StreamProvider.family<List<Task>, String>((
  ref,
  personId,
) async* {
  final repo = ref.watch(repositoryProvider);
  // Refresh when any task row changes.
  await for (final _ in repo.db.select(repo.db.tasks).watch()) {
    yield await repo.getTasksForPerson(personId);
  }
});

/// Day notes for the calendar, live (1.3.0).
final dayNotesProvider = StreamProvider.family<List<DayNote>, String>((
  ref,
  orgId,
) {
  return ref.watch(repositoryProvider).watchDayNotes(orgId);
});

/// Which sub-tab of the merged Teams tab is showing (1.3.0):
/// 'teams' | 'people'. Default Teams. Set by the Home stat tiles
/// and by the segmented control just above the bottom bar.
final teamsTabSubProvider = StateProvider<String>((ref) => 'teams');

/// Up next, live (1.3.0): the Home section used to re-create a
/// one-shot future on every build, so the list reloaded and jumped
/// while scrolling. This streams the tasks and selects with the same
/// pure rule as the repo ([selectUpNext]) — open tasks first,
/// recently completed ones at the bottom for ~24h.
final upNextProvider = StreamProvider.family<List<Task>, String>((
  ref,
  orgId,
) async* {
  final repo = ref.watch(repositoryProvider);
  await for (final tasks in repo.watchTasks(orgId)) {
    yield selectUpNext(tasks);
  }
});

// ---------------------------------------------------------------------------
// Tab navigation state (kept in the shell, not here)
// ---------------------------------------------------------------------------

/// Which tab is active: 0 Home, 1 Tasks, 2 Teams (merged Teams +
/// People), 3 Calendar, 4 Settings.
final tabIndexProvider = StateProvider<int>((ref) => 0);

/// Tasks tab filter requested from elsewhere (e.g. Home "Overdue" tile).
final tasksOverdueFilterProvider = StateProvider<bool>((ref) => false);

/// Scroll-to-top requests: each tab's list listens for its tab id here.
final scrollToTopProvider = StateProvider<int>((ref) => 0);

/// One ScrollController per tab, so tapping the active tab scrolls it
/// to the top (section 5). Owned by the shell; screens read theirs.
final tabScrollControllersProvider = Provider<List<ScrollController>>((ref) {
  final list = List.generate(5, (_) => ScrollController());
  ref.onDispose(() {
    for (final c in list) {
      c.dispose();
    }
  });
  return list;
});
