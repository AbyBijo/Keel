# Keel — offline organization manager

**One manager. Many teams. Everything stays on your phone.**

Keel is a fully offline Android app (Flutter) for one person managing an
organization with many people, tasks, teams and sub-organizations. No login,
no server, no account, no internet permission. All data lives in a local
SQLite database (Drift) on the phone.

- Package: `com.keel.manager`
- Version: 1.0.0
- Android 8+ (API 26+), portrait, phones first
- Private repo: https://github.com/AbyBijo/Keel

## Run it

Prerequisites: Flutter SDK (stable, 3.35+), JDK 17, Android SDK
(platform 35, build-tools 35.0.0).

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs  # regenerate lib/db.g.dart
flutter analyze
flutter test
flutter run
flutter build apk --debug
```

Tooling used for this build lives outside the repo
(`~/workspace/keel-tools/` on the build machine): Flutter SDK, Temurin
JDK 17, Android cmdline tools. Set `JAVA_HOME` to the JDK and
`ANDROID_HOME`/`ANDROID_SDK_ROOT` to the Android SDK before building.

## Structure

```
lib/
  main.dart        App entry: SharedPreferences, notifications init, theme,
                   text scaling (system scaler x in-app text size).
  theme.dart       Design tokens (colours, radii, type, motion) — edit colours here.
  links.dart       ALL outbound URLs in one place (GitHub / LinkedIn /
                   Buy Me a Coffee). The Buy Me a Coffee URL is TO-CONFIRM.
  db.dart          Drift tables (exact data model from the master prompt),
                   foreign keys, indexes, migrations.
  repo.dart        All data access + the 10 logic rules. The UI never
                   touches the DB directly.
  providers.dart   Riverpod providers: DB, repo, settings, active org,
                   org-scoped streams, tab state.
  services.dart    Photos (app-private storage), backup/restore (zip via
                   the system file picker), daily-digest notifications,
                   Undo snackbar helper.
  seed.dart        Optional Northwind Studio demo dataset (Settings only).
  widgets.dart     Custom components: Card, Chip, Avatar, Checkbox,
                   ProgressRing/Bar, Segmented, Button, Input, EmptyState,
                   sheets, stat tiles.
  task_card.dart   The task card used on Home, Tasks, team page, person card.
  sheets.dart      Create sheets (Task/Person/Team), task detail, task +
                   person overview sheets, team overview, org switcher,
                   people/team/leader pickers.
  task_page.dart   Full task page (opened by the arrow on a task tile).
  onboarding.dart  First-launch 2-step onboarding (never shown again).
  shell.dart       Frosted tab bar (5 tabs, sliding pill) + floating Add
                   button with staggered Task/Person/Team pills.
  home.dart        Dashboard: greeting, dark progress dial, stat tiles,
                   Up next, team cards, global search.
  tasks.dart       Tasks list: segmented All/Open/Done, team/person/
                   overdue filters, swipe delete/complete.
  teams.dart       Teams list + full team page (hero, leader, people, tasks).
  people.dart      People list (live search) + person card (photo, intents,
                   phones/emails, teams, assigned tasks, notes).
  settings.dart    Settings groups + About page.
```

## Where to edit

- **Colours / radii / type / motion:** `lib/theme.dart` (`KeelTokens`).
  Every screen reads from there; the kit tokens are copied verbatim.
- **Links (GitHub / LinkedIn / Buy Me a Coffee):** `lib/links.dart` only.
- **Team colour presets:** `KeelTokens.teamPresets` in `lib/theme.dart`.
- **Sample data:** `lib/seed.dart`.
- **Notification text / digest time:** `lib/services.dart`
  (`NotificationService`) + Settings → Utilities → Reminders.

## Tests

`flutter test` runs:

- `test/logic_rules_test.dart` — all 10 logic rules from the master
  prompt (reflexive assignment, many-to-many teams, exactly-one-leader
  with re-pick, at-most-one main task + progress, the four task shapes,
  sub-todo prompt/reopen, overdue/due-soon, org scoping, soft delete +
  Undo, backup validation + round-trip).
- `test/audit_fixes_test.dart` — backup validation hardening (missing
  phones/emails lists, damaged rows), WhatsApp `wa.me` link building
  (digits-only), and JOIN-rewrite regressions (team members, task
  assignees, per-person tasks return the same rows as the old code).
- `test/overview_sheets_test.dart` — the task overview sheet (summary,
  quick actions, Complete works live) and the person overview sheet
  (Call + Message on the right).

Note: the logic tests need a loadable `libsqlite3.so` on Linux. On this
build machine it was provided by a symlink to the installed
`libsqlite3.so.0` (`/usr/lib/x86_64-linux-gnu/libsqlite3.so`).

## Tiles: tap vs arrow

Every Task, Team and Person tile works the same way:

- **Tap the tile** (anywhere except the arrow) → a slide-up overview
  sheet: the task sheet has title/notes/due/priority, sub-todo
  progress + checklist, assignees, a button to its team, and quick
  actions (Complete/Reopen, Edit, Delete with Undo); the person sheet
  has avatar/name/role/teams with **Call** on the right and **Message**
  (WhatsApp, `wa.me/<digits>`) directly below it; the team sheet has
  stats, main task and members.
- **Tap the arrow** → the full page (Task page, Team page, Person page).

## App icon

The launcher icon is the real Material Icons `anchor_rounded` glyph
(U+F562, the same glyph the About page and onboarding show), white on
solid kit teal `#0E7C86`, rendered from the Flutter SDK's
`MaterialIcons-Regular.otf` (`/tmp/keel_icon_gen.py` — kept outside the
repo, re-runnable). It is a proper adaptive icon
(`mipmap-anydpi-v26/ic_launcher.xml`: foreground = white anchor on
transparency, background = teal) with legacy mipmaps at every density
and a 1024px master at `assets/icon-1024-v2.png`. The glyph is sized
to 62% of the 108dp canvas, inside the 66dp safe zone, so no launcher
mask can crop it. (The first icon was hand-drawn and its two flukes
floated disconnected from the curved bottom — replaced 2026-11-15.)

## Size

The debug APK was 77.2 MB. The release build is kept as small as
honestly possible without losing quality:

- **Per-ABI split** (`.github/workflows/android.yml`): `flutter build
  apk --release --split-per-abi` — one APK per ABI instead of one fat
  APK carrying three sets of native libraries. Expected ~7–12 MB per
  ABI (exact number from CI).
- **R8 + resource shrinking** are on for release, made explicit in
  `android/app/build.gradle.kts` (`isMinifyEnabled`,
  `isShrinkResources`, `proguard-rules.pro` with keeps for
  `flutter_local_notifications` and the plugin registrant).
- **No duplicated fonts**: the six font files are bundled once, via
  `flutter: fonts:` only. The old `assets: - assets/fonts/` entry
  bundled the same files a second time as raw assets (~1.9 MB) and
  was removed; nothing loads them as raw assets.
- **Tree-shaken icons** (Flutter default): only the Material icons the
  app actually uses are bundled.

## Signing (same plan as VoxFlow)

- **Debug and release keys are DISTINCT and each FIXED across builds of
  its type.** Never reuse one key for both.
- Debug: the standard debug keystore (generated by the Android build).
- Release: a dedicated `keel-release` keystore, generated 2026-11-15
  (alias `keel-release`, RSA 2048, valid to 2054-04-02, SHA-256
  `A1:AE:51:2D:AB:4E:03:DE:C4:44:0C:8D:19:82:AF:54:27:03:A6:C2:CF:50:4C:1F:62:60:BE:4D:0C:43:C8:56`).
  The keystore lives in the user's files folder only
  (`workspace/your_files/keel-release-keystore/`), the password only
  in its `PASSWORD.txt` — never in the repo, chat or this file. The
  four GitHub secrets are set (`ANDROID_KEYSTORE_BASE64`,
  `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`), so a push to
  `main` builds both the debug APK and the signed per-ABI release
  APKs as Actions artifacts.
- Release builds are GitHub Actions artifacts only — no GitHub Release.

## Privacy

No `INTERNET` permission (verified: it is absent from
`android/app/src/main/AndroidManifest.xml`), no analytics, no trackers,
no network calls anywhere in the code. Photos are copied into
app-private storage; the database stores only the path. Backup/restore
uses the Android system file picker only.

See `docs/security.md` and `docs/risks.md`.
