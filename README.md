# Keel — native (Kotlin + Jetpack Compose)

Keel is an offline organization manager for Android: people, teams, tasks and
sub-tasks for one organization at a time, with no account, no server and no
internet permission. This is the **native rebuild** of the Flutter version
(`~/workspace/keel/` — reference only, untouched). Same screens, same logic
rules, same UI kit — rebuilt in Kotlin + Jetpack Compose for a smoother,
more premium feel.

- Package: `com.keel.manager`
- minSdk 26 · targetSdk / compileSdk 36 (Android 16) · Java 17 · Kotlin 2.1.0
- AGP 8.9.1 · Gradle 8.12 · Compose BOM 2025.01.00
- Storage: Room (SQLite) + DataStore. No INTERNET permission, no analytics.

## How to run

```bash
./gradlew :app:assembleDebug   # debug APK, v2+v3 signed with the fixed debug key
./gradlew :app:testDebugUnitTest  # 18 unit tests (10 logic rules + backup)
```

Install the APK from `app/build/outputs/apk/debug/` on any Android 8+ phone.
CI (`.github/workflows/android.yml`) runs the same two commands on every
push to `main` and uploads the debug APK as artifact `keel-debug-apk`.

## Structure

```
app/src/main/java/com/keel/manager/
  MainActivity.kt          Navigation state (KeelNav), text scaling, theme wiring
  KeelApp.kt               Application + manual DI container (no DI framework)
  Links.kt                 THE one place external links live (GitHub / LinkedIn /
                           Buy Me a Coffee — the last is TO-CONFIRM)
  data/
    Models.kt              Entities + date helpers (overdue / due-soon / greeting)
    KeelDatabase.kt        Room database + DAO (all queries)
    Repository.kt          All data access + the 10 logic rules + backup JSON
    SettingsStore.kt       DataStore settings (same keys/defaults as Flutter)
    SeedData.kt            Northwind Studio sample data (Settings only)
    Notifications.kt       Daily digest via AlarmManager + NotificationManager
    Backup.kt              .keel zip export/import + photo magic-byte validation
  ui/
    KeelViewModel.kt       Single ViewModel: flows, search, 6-second Undo
    theme/Theme.kt         Kit tokens, Nunito/Inter, springs, reduce-motion
    components/            KeelCard, Chip, Avatar, Checkbox, ProgressRing,
      Components.kt        SegmentedControl, TextField, EmptyState, press feedback
    screens/
      Shell.kt             Frosted tab bar (86dp), FAB + 3 pills, Undo snackbar
      Onboarding.kt        2 steps, shown once
      HomeScreen.kt        Org header, greeting, dial, stats, Up next, teams
      TasksScreen.kt       Task list + overview sheet + full task page
      TeamsScreen.kt       Team list + overview sheet + full team page
      PeopleScreen.kt      People list + overview sheet + full person page
      SettingsScreen.kt    Settings + About page
      Sheets.kt            Bottom sheets, confirm dialog, create forms,
                           org switcher, global search
      Shared.kt            TaskTile, PersonRow, TeamCard, date labels
app/src/test/java/com/keel/manager/
  LogicRulesTest.kt        18 JUnit + Robolectric tests (in-memory Room)
```

## Where to edit

- **Colours / type / radii / motion:** `ui/theme/Theme.kt` (`KeelColors`,
  `KeelType`, `KeelRadii`, `KeelMotion`). Kit tokens are copied exactly from
  `tokens/design-tokens.json` in the UI kit.
- **Links (About page):** `Links.kt` — the only file with URLs.
- **Launcher icon:** `app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`
  (adaptive) + `drawable/ic_launcher_foreground.xml` (anchor glyph) +
  `drawable/ic_launcher_background.xml` (teal gradient). The master is
  `icon-1024.png` at the project root. The glyph is Google's Material
  `anchor_rounded` (Apache 2.0) — the same anchor the in-app icon uses.
- **Signing:** `app/build.gradle.kts` (signingConfigs) + `keystore/debug.keystore.b64`
  (fixed debug key, public by design). Release reads `key.properties`
  (never committed); CI writes it from secrets.
- **Sample data:** `data/SeedData.kt`.

## The 10 logic rules (all tested)

1. Assignment is reflexive — one table (`task_assignees`), read from both sides.
2. Many-to-many people ↔ teams and tasks ↔ people.
3. A task can exist alone, team-only, people-only, or both.
4. Exactly one leader per team, who must be a member; removing/deleting a
   leader requires naming a replacement first.
5. At most one main task per team; team progress = done / all its tasks.
6. (Covered by 3) — the four task combinations.
7. Sub-todos: all done offers parent completion (never auto-completes);
   reopening a sub-todo reopens the parent; completing sets `completedAt`.
8. Overdue = not done + due before today; due soon = within 2 days.
9. Everything is scoped to the active organization.
10. Soft delete with 6-second Undo (in-memory snapshot; team delete keeps
    people and tasks; person delete removes only assignments/memberships).

## What's different from the Flutter version

- **Native:** Kotlin + Compose instead of Flutter/Dart/Drift. Smaller
  dependency surface, platform NotificationManager/AlarmManager instead of
  the notifications plugin that failed three CI builds.
- **Launcher icon:** redrawn as the `anchor_rounded` glyph — ring, stem,
  crossbar and a continuous curved bottom with connected flukes — as a
  proper adaptive icon, instead of the hand-drawn squircle PNG whose flukes
  floated free of the curve.
- **Overview sheets:** task and person tiles now open overview sheets with
  quick buttons (Complete / Edit / Delete; Call / Email / Message with Call
  bottom-right). Chevron still opens the full page. Teams already had this.
- **Premium feel:** critically-damped springs (stiffness ~300, damping 1.0),
  180–260 ms fades, transform/opacity-only animation, dial count-up,
  staggered FAB pills, haptics, instant press feedback, reduce-motion mode.
- **Signing:** v2+v3 only (v1 off), distinct fixed debug/release keys,
  `apksigner verify` in CI.
- **Size:** debug APK size is reported honestly; smoothness outranks the old
  10–20 MB target (user, 2026-11-15).

See `DECISIONS.md` for every decision and anything not done.
