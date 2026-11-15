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

// ---------------------------------------------------------------------------
// Tab navigation state (kept in the shell, not here)
// ---------------------------------------------------------------------------

/// Which tab is active: 0 Home, 1 Tasks, 2 Teams, 3 People, 4 Settings.
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
