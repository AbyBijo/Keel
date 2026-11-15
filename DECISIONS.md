# Keel (native) — Decisions

Every decision made for the native rebuild, and anything not done, honestly.

## Stack

- **Kotlin + Jetpack Compose (not pure Java).** The user asked "Kotlin or
  pure Java?" and confirmed Kotlin + Compose. Reason: the premium-feel
  requirement (critically-damped springs, staggered pills, count-up dial,
  sheet/page-push animations) is Compose's home ground; Kotlin's
  null-safety catches crashes at compile time. Pure Java would have meant
  hand-building the animation system.
- **Room 2.7.0 (KSP) instead of raw SQLiteOpenHelper.** The data model has
  10 tables and 10 logic rules with transactions; Room gives compile-time
  SQL checks, FK enforcement and in-memory test databases. The schema
  mirrors the Flutter Drift tables exactly, including indexes.
- **DataStore Preferences instead of SharedPreferences.** Same keys and
  defaults as the Flutter providers (`onboarding_done`, `active_org_id`,
  `theme_mode`, `text_scale`, `reduce_motion`, `accent_hex`,
  `reminders_on`, digest time, `last_backup_at`, `home_seen_once`).
- **Manual DI (one `AppContainer`) instead of Hilt.** One repository, one
  settings store, one ViewModel — a DI framework would be pure overhead.
- **No navigation-compose in the UI**, despite the dependency being present:
  the shell is a 5-tab IndexedStack-style layout with sheets and detail
  pages; a single `KeelNav` state object is simpler and matches the
  Flutter shell exactly. (The dependency stays in the catalog for later
  use; it is not linked into the app graph beyond the BOM.)
- **org.json (built into Android) for backup JSON** instead of a JSON
  library. Zero new dependencies for a format we fully control.
- **No R8 / minify / shrink in debug OR release.** User decision (same as
  the Flutter builds): reproducible builds without R8. Size is reported
  honestly instead.

## Data model

- `Teams.mainTaskId` is a **plain column with no foreign key**, exactly like
  the Flutter build. `Teams.mainTaskId` ↔ `Tasks.teamId` is circular, so a
  FK on both sides cannot exist. The repository clears main-task pointers
  explicitly in `deleteTaskRows()` (with a comment explaining why — never
  rely on the DB for this). `Tasks.teamId` DOES have an FK with SET_NULL.
- **Delete now + restore (Undo) instead of delayed delete.** The Flutter
  build deletes immediately and restores from an in-memory snapshot within
  6 seconds. The native build does the same: the snackbar shows for 6
  seconds, then the snapshot is dropped. Simpler than a timer-based delete
  and identical in behaviour.
- **Photos are file names only** (`photoPath` = a file name inside
  `filesDir/photos/`). `BackupService.photoFile()` strips any path with
  `File(name).name`, so a crafted backup cannot write outside that folder.
- **Due dates are stored at start-of-day** (normalized on write), so
  overdue/due-soon comparisons are exact.

## Icon

- The launcher icon is Google's Material `anchor_rounded` glyph
  (Apache 2.0, from the material-design-icons repo) — the same glyph the
  in-app icon uses (Flutter `Icons.anchor_rounded`). Single continuous
  path: ring, stem, crossbar, curved bottom with flukes CONNECTED to the
  curve. The old hand-drawn icon's flukes floated free of the curve.
- Built as a proper **adaptive icon**: foreground = anchor glyph only on
  transparency (glyph in the central 60 of the 108 viewport, inside the
  safe zone), background = the teal gradient `#12A0AB` → `#0B4F66`
  (angle 315, same as the in-app tile). Legacy mipmap PNGs at 48/72/96/
  144/192 are derived from the same glyph, plus the 1024px master.
- Verified visually: the foreground preview and the 1024 master both show
  the clean connected anchor with no floating pieces.
- Two generation bugs were found and fixed: (1) the first path-transform
  script double-applied the translation on relative commands; rewritten to
  emit all-absolute commands. (2) The master was first saved to
  `app/src/icon-1024.png`; moved to the project root.

## Sheets (user update #2)

- Task tile tap → overview sheet with quick buttons (Complete/Reopen,
  Edit, Delete) + assignee actions; chevron → full task page.
- Person tile tap → overview sheet (Message / Email / **Call** — Call is
  the right-most button, bottom-right, easiest right-thumb reach) +
  Open profile / Edit / Delete; chevron → full person page.
- Teams already had this pattern; unchanged in shape.

## Motion / premium feel (user updates #3–4)

- Springs: stiffness ~300, damping ratio 1.0 (critically damped, no
  bounce) per the apple-design skill; fades 180–260 ms; transform/opacity
  only — no layout animation.
- Dial count-up: 900 ms tween; FAB pills staggered by 40 ms each; FAB
  rotates 45° and morphs squircle → circle.
- Reduce-motion (Settings) switches every animation to a simple fade and
  makes the dial jump to its value.
- Press feedback: neutral grey indication only — **no blue ripple and no
  blue focus ring anywhere** (universal rule, 2026-11-05). Implemented by
  using `indication = null` on clickables and letting components show
  their own pressed state; text fields use a neutral grey border on focus.
- Haptics on key actions (FAB, pills, checkbox, buttons).

## Signing & Android version (user, 2026-11-15 ~10:23)

- Package **`com.keel.manager`** everywhere (not `com.abybijo.keel`).
- targetSdk / compileSdk **36**, minSdk 26.
- Signing v2+v3 only (`enableV1Signing = false`, v2+v3 true) for BOTH
  debug and release, following the Agent-zero pattern for Android 16.
- Debug key: **fixed**, generated 2026-11-15 ~10:54 IST — alias
  `keel-debug`, RSA 2048, valid to 2054-04-02, SHA256
  `BC:5B:1C:63:F2:AD:BE:19:00:8D:61:28:CA:6D:66:00:66:0C:A4:D2:C7:CA:F6:7F:4D:34:B4:FD:5B:C9:A2:72`.
  Committed as base64 text in `keystore/debug.keystore.b64` (debug-only
  credentials `keel-debug`, public by design, VoxFlow pattern). The binary
  keystore lives only in `/tmp/keel-debug.keystore`, never in the repo.
- Release key: **NOT generated** — waits on the user's confirmation. The
  release signing config reads `key.properties` (never committed) and
  falls back to the debug key when it is absent, so local release runs
  still work. CI writes `key.properties` from the 4 release secrets and
  only builds release when all 4 exist.
- CI verifies the debug (and release, when built) signature with
  `apksigner verify --verbose --print-certs`.

## Notifications (pre-mortem fix)

- The Flutter build failed three CI runs on `flutter_local_notifications`:
  desugaring, then `java.time.LocalDateTime` on Java 11, then a floating
  19.5.0 despite the lock pinning 19.4.2. The native app uses **platform
  APIs only**: `NotificationManager` + `AlarmManager` + `BroadcastReceiver`,
  `java.time` (native from API 26 = minSdk), Java 17, and every dependency
  pinned in `gradle/libs.versions.toml`. No desugaring, no plugin.

## Size (user, 2026-11-15 ~10:23)

- The 10–20 MB target is **relaxed**: smoothness and premium feel outrank
  size. Dependencies are still minimal (Compose BOM, Room, DataStore,
  coroutines, Material icons core + extended) and the actual debug APK size
  is reported honestly in the final report. No R8 was enabled to chase size.
- **Material icons extended (1.7.8) added during verification** (see below):
  four icons the screens use (`ChevronRight`, `Group`, `Message`,
  `PersonAdd`) exist only in `material-icons-extended`, not in core. The
  extended library's classes jar is ~37 MB, so it will add several MB to
  the debug APK (no R8 in debug). The alternative — hand-drawing four
  outlined icons — was rejected: the official glyphs match the kit's
  24px-outline/1.9-stroke style exactly, and the size limit is relaxed.

## Local verification (2026-11-15, this VM)

- **Gradle cannot run locally: BLOCKED by the sandbox TCP guard.** The
  Gradle daemon protocol runs over loopback TCP; the JVM receives the
  guard message (`Other TCP connections is turned off… switch other_tcp
  from Deny to Ask` in Muse settings → Permissions → Direct network
  protocols). The daemon starts, listens, and never receives a connection
  (`DaemonConnectionException`, tag 109 = `m` of "muse:…"). This is a
  sandbox permission, not a code or Gradle problem, and was NOT bypassed.
  **CI (GitHub Actions) is the proof path for the Gradle build + APK.**
- **Direct kotlinc compile (no Gradle): PASS.** All 22 main sources +
  generated `R`/`BuildConfig` stubs compiled with kotlinc 2.1.0 + the
  Compose compiler plugin against the exact pinned dependencies:
  **exit 0, 0 errors, 0 warnings, 391 classes** (log
  `/tmp/keel-kotlinc9.log`). Classpath assembled from the version catalog
  with a hand-written Maven resolver; AndroidX KMP artifacts needed their
  `-android` (or `-jvm`) variants — the plain coordinates are empty stubs.
- **Room codegen: PASS, clean.** kapt itself is unusable via the CLI
  (its K1 frontend, language 1.9 fallback, cannot resolve
  `RoomDatabase.Builder.build()` — reproduced with a 10-line minimal
  case; the same code compiles under kotlinc K2). So Room's processor was
  run directly with javac on the kapt-generated stubs:
  `KeelDatabase_Impl.java` + `KeelDao_Impl.java` generated, **exit 0, no
  errors, no warnings** (after the index fix below). This is the same
  processor CI runs — but note CI uses **KSP** (the build applies the KSP
  plugin), not kapt, so the kapt CLI limitation does not affect CI.
- **SQL validation: PASS.** All 68 `@Query` strings were validated
  against the real schema in SQLite (`EXPLAIN` + end-to-end runs with
  seed rows). The generated `CREATE TABLE` statements match the validated
  schema exactly.
- **Bugs found and fixed by the verification** (all in the source, none
  in the build config except the icons dependency):
  1. `KeelMotion.spring()` called itself recursively — qualified to
     `androidx.compose.animation.core.spring`.
  2. `RoomDatabase.Callback` has no `onConfigure` in Room 2.7 — removed
     (Room enables foreign keys by default).
  3. Missing `import kotlinx.coroutines.launch` in `Notifications.kt` and
     `KeelViewModel.kt`.
  4. Missing `import androidx.compose.ui.draw.clip` (Shared, Tasks,
     Teams, People screens), `size`/`width` (Teams), `background`
     (all four screens), `Search` icon import (People, Sheets).
  5. `FlowRow` needs `@OptIn(ExperimentalLayoutApi::class)` (Onboarding,
     three create forms in Sheets).
  6. `material-icons-extended` missing from the build (see Size).
  7. Deprecated `Icons.Outlined.ArrowBack`/`Message` → AutoMirrored
     versions; `ExperimentalCoroutinesApi` opt-in on the ViewModel.
  8. Room warning: `Team.leaderPersonId` FK had no index — added
     `Index("leaderPersonId")`; codegen is now warning-free.
- **Unit tests: compile PASS, run BLOCKED by the local Robolectric harness (NOT a code problem).** Test sources compile clean — **exit 0, 0 errors, 0 warnings** (log `/tmp/keel-test-compile2.log`). Running them locally needs Robolectric 4.13's native SQLite runtime: the sandbox loads and Room opens the in-memory DB, but every one of the 18 tests fails identically with `UnsatisfiedLinkError: SQLiteConnectionNatives.nativeOpen` — the `librobolectric-nativeruntime.so` (from `nativeruntime-dist-compat 1.0.12`, verified valid with its JNI symbols and all shared-lib deps resolving) is never loaded by the hand-rolled offline JUnitCore harness, even with the instrumented android-all (`14-robolectric-10818077-i6`) and the dist artifact pre-placed in `~/.m2` with crafted metadata. Seven run attempts, same failure each time (logs `/tmp/keel-test-run1.log` … `/tmp/keel-test-run7.log`). This is a limitation of the local offline harness, not of the test code or the app code: **CI runs the same tests through Gradle, which resolves Robolectric the normal way — CI is the proof path for the test count.** Do not "fix" this by weakening the tests.

## Environment notes

- Android 36 platform + build-tools 36.0.0 were installed locally by
  fetching the zips with `curl` from the repository XML and unzipping them
  manually: `sdkmanager` failed with a proxy-tunneling
  `NoSuchElementException` (`HttpURLConnection.doTunneling`). The Gradle
  proxy token rotates; if Gradle cannot download, refresh it from the
  current env `https_proxy` into `~/.gradle/gradle.properties` (never print
  token values).
- Local verification scratch lives in `/tmp/keel-deps/` (kotlinc 2.1.0,
  the Maven resolver + downloaded jars, classpath, stubs, Room codegen
  output, validation scripts, logs). `/tmp` is a 512 MB tmpfs — the
  build-tools/platform zips that filled it were deleted after installing
  into the SDK; keep an eye on free space when adding large artifacts
  (material-icons-extended classes alone are ~37 MB).

## Not done / open

- **On-device test: NOT done.** No APK has been built anywhere yet
  (local Gradle is blocked — see above; CI has not run yet). Onboarding,
  all screens, dark mode, smoothness and the launcher icon in a real
  drawer are all unconfirmed until the user tries it.
- **CI run: NOT done yet.** The workflow exists (`.github/workflows/
  android.yml`) but the code has not been pushed, so no CI run has
  happened. CI is the proof path for the Gradle build, the APK and its
  v2+v3 signature verification.
- **Release keystore: NOT generated** (waits on user confirmation) and the
  4 release secrets are NOT set. Release fingerprint is therefore not
  reportable yet.
- **Buy Me a Coffee URL is TO-CONFIRM** (`Links.kt`): the handle follows
  the user's known handle but the URL has not been independently verified.
- **Person photos:** the data model stores `photoPath` and the backup
  service handles photo files, but the person page does not yet have a
  camera/gallery picker wired up — the photo/camera badge from the kit is
  not implemented. (FileProvider + `file_paths.xml` are ready for it.)
- **Digest time picker:** the daily digest time is fixed at the stored
  hour/minute (default 08:00); there is no time-picker UI in Settings yet
  — only the on/off toggle.
- **Due-date picker:** task creation offers Today / Tomorrow / In 3 days /
  In a week / No date chips, not a full calendar picker. The task page
  does not yet edit the due date (it shows it).
- **Drag-to-reorder sub-todos:** `reorderSubTodos()` exists in the
  repository; no drag handle in the UI yet.
- **Widget / shortcut / share targets:** not in the brief, not built.
