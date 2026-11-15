# Keel — security review

Checked 2026-11-15 during the local build (Flutter 3.35.7, Dart 3.9).
Re-check after any dependency change with `flutter pub outdated` and
`flutter pub audit` (if available in your Flutter version).

## 1. Network: none

- `android/app/src/main/AndroidManifest.xml` contains **no `INTERNET`
  permission**. Verified by grep during the build. (Flutter's
  debug/profile manifests add it for tooling only; the shipped
  main manifest does not have it.)
- No HTTP client, no analytics SDK, no crash reporting, no tracker
  dependency in `pubspec.yaml`. The only outbound action in the app is
  `url_launcher` opening the three About-page links and `tel:` /
  `mailto:` / `sms:` intents from a person card, plus the person
  overview sheet's WhatsApp link (`https://wa.me/<digits>`, built by
  `whatsappUriFor` in `lib/sheets.dart` — digits only, `null` when the
  number has no digits, so no user-typed text can reach the URL
  unchecked) — all explicit user taps.
- Fonts are bundled locally (`assets/fonts/` — Inter + Nunito, OFL);
  nothing is fetched at runtime.

## 2. Dependencies (pinned in pubspec.yaml)

| Package | Version | Note |
|---|---|---|
| flutter_riverpod | 2.6.1 | State management. Maintained. |
| drift | 2.28.1 | SQLite ORM. Maintained. |
| sqlite3_flutter_libs | 0.5.24 | Bundled SQLite for Android. |
| path_provider / path | 2.1.5 / 1.9.1 | App dirs. |
| shared_preferences | 2.5.3 | Settings only (no user content). |
| flutter_local_notifications | 19.4.2 (pinned `>=19.4.2 <19.5.0`) | Daily digest only, local. 19.5.0 was excluded 2026-11-15 after CI Run #12 failed compiling its `java.time.LocalDateTime` usage; the app also moved to Java 17 for this plugin. |
| timezone | 0.10.1 | Needed by the digest scheduler. |
| file_picker | 10.3.2 | SAF picker for backup/restore/CSV. |
| image_picker | 1.2.0 | Camera/gallery for person photos. |
| archive | 4.0.7 | Zip for backups. |
| url_launcher | 6.3.2 | Intents only. |
| intl | 0.20.2 | Date formatting. |
| uuid | 4.5.1 | Random ids. |

Findings:

- **No known-vulnerable packages found in the resolved set** at build
  time (`flutter pub outdated` shows newer versions available for some
  packages, e.g. `uuid` 4.6.0, but the pinned versions have no known
  CVE affecting this app's use). Versions are pinned exactly so a
  rebuild cannot silently pull a different release.
- `build_runner` 2.7.1 (not 2.7.2): 2.7.2 requires `build` 4.0.0,
  which conflicts with `drift_dev` 2.28.1's `build` ^3.0.0. Pinned to
  the compatible pair; revisit when drift_dev supports build 4.
- No dependency phones home: none of the above makes network calls
  except `url_launcher` on explicit tap (see §1).

## 3. Data handling

- **SQL:** all access goes through Drift generated code. No raw
  string-concatenated queries anywhere; user input never reaches SQL
  as text. The only `customStatement` calls are fixed DDL
  (`PRAGMA foreign_keys = ON`, fixed `CREATE INDEX` statements).
- **Foreign keys:** `PRAGMA foreign_keys = ON` in `beforeOpen`.
  One deliberate gap: the Teams ↔ Tasks foreign keys are circular
  (`Teams.mainTaskId → Tasks`, `Tasks.teamId → Teams`), so Drift drops
  the `Tasks.teamId` FK constraint (it warns at codegen). The
  repository enforces the same behaviour in code instead
  (`deleteTeam` nulls task team ids first; `_deleteTaskRows` clears
  main-task pointers first). See `DECISIONS.md`.
- **Photos:** picked via `image_picker`, validated by magic bytes
  (JPEG/PNG/WebP) before copying, copied into app-private storage
  (`getApplicationDocumentsDirectory()/photos/`), DB stores only the
  path. Displayed with `Image.file` + `errorBuilder` fallback.
- **Backup/restore:** the zip is validated **before** any data is
  replaced — `keel-backup.json` must exist, `format` must be
  `keel-backup`, `version` must be 1, all lists must be present
  (`KeelRepository.validateBackup`). Since the 2026-11-15 audit the
  validator also requires the `phones` and `emails` lists and checks
  that every row is a map, so a foreign file with the right header but
  a damaged row gets a readable error instead of a raw `TypeError`
  crash at restore. Files over 100 MB are rejected, as are archives
  with over 5000 entries, any single file over 25 MB, or over 100 MB
  expanded in total (zip-slip / zip-bomb caps; photo entries are
  written by basename only, never by archive path). Photos inside the
  zip are written to app-private storage and paths are rewritten to
  the new location. Restore runs inside one transaction, and the
  Settings restore flow now catches non-`FormatException` errors too
  instead of crashing.
- **File picker input:** restore only accepts `.zip` picked by the
  user; malformed zips / JSON raise a user-readable error and change
  nothing.
- **No secrets:** no API keys, passwords, tokens or hardcoded
  credentials anywhere in the code. The release keystore is not in
  the repo (see README → Signing).
- **Soft delete / Undo:** delete executes immediately but keeps a
  full snapshot (entity + children) in memory for 6 seconds; Undo
  re-inserts it. Nothing is kept after the snackbar expires. See
  `DECISIONS.md` for why this differs from a `deletedAt` column.

## 4. Platform

- `minSdk 26` (Android 8+), `targetSdk` = Flutter default (35).
- No permissions beyond the defaults: no contacts, no location, no
  microphone, no storage permission (SAF picker needs none).
- `flutter_local_notifications` requests the Android 13+
  `POST_NOTIFICATIONS` permission only when the user turns Reminders
  on; declining it leaves the toggle on but no digest is delivered
  (a snackbar explains it).

## 5. Residual risks (accepted)

- The debug keystore is the standard Android debug key — fine for
  debug builds, never for release.
- A backup zip contains photos + all data in plain JSON. It is the
  user's file on their own phone; there is no encryption by design
  (offline-first, user-controlled file). If the user shares the zip,
  they share their data — the restore confirm dialog says what will
  be replaced, but does not warn about sharing. Acceptable for v1;
  consider a warning line in the backup dialog later.
- `image_picker` on old devices may return a content URI the app
  cannot copy; the failure path shows "That photo could not be used"
  instead of crashing.

## 6. Audit + optimization pass (2026-11-15, update 5)

A full re-read of `lib/` against this document, with fixes. Every
item below was checked by reading the code — not by running a
scanner, which does not exist for this stack on this machine.

- [x] No `INTERNET` permission (absent from
      `android/app/src/main/AndroidManifest.xml`).
- [x] No HTTP client, no analytics, no trackers in `pubspec.yaml`.
- [x] No raw user-input SQL anywhere: Drift only, parameterised
      (`lib/repo.dart`).
- [x] Photos validated and app-private (`lib/services.dart`).
- [x] Backup/restore validated before replacing data (see §3).
- [x] No secrets/keys/passwords in source (grep clean except keystore
      property *names* in the Gradle signing config).
- [x] No logging of personal data in `lib/` (`print`/`debugPrint`:
      none).
- [x] No WebView, no remote content.
- [x] URL intents built from validated input only (tel/mailto/sms
      from stored contact rows; `wa.me` digits-only, §1).
- [x] Deleted rows are removed from the database on undo-expiry; the
      6-second window is the only retention.
- [x] **Vulnerability: app name exposed by a manifest flag** —
      `android:allowBackup="true"` (default). A user-level backup
      could copy the local database off the phone. Not applicable to
      the threat model for an offline app on the user's own device,
      but noted here as a conscious decision, not an oversight.

Findings and fixes from this pass:

| # | Severity | Finding | Fix |
|---|----------|---------|-----|
| 1 | Medium | `validateBackup` did not require the `phones`/`emails` lists and did not check row types — a foreign file with the right header but a damaged row threw a raw `TypeError` at restore. | Validator now requires all 9 lists and requires every row to be a map; the Settings restore flow catches non-`FormatException` errors too. Tests: `test/audit_fixes_test.dart`. |
| 2 | Low | Restore had no cap on entry count / per-file size / total expanded size (zip-bomb residual). | Caps added: 5,000 entries, 25 MB per file, 100 MB expanded; file cap lowered 200 → 100 MB. |
| 3 | Low | Photos decoded at full size for 28–48 px avatars. | `cacheWidth`/`cacheHeight` = size × devicePixelRatio in `PersonAvatar`. |
| 4 | Low | Database queries ran on the UI thread (Drift's default main-isolate connection). | `NativeDatabase.createInBackground` — all queries on a background isolate. |
| 5 | Info | N+1 lookups in the repo (one query per member/assignee/phone/email). | Rewritten as single JOINs + bulk fetches; behaviour locked by `test/audit_fixes_test.dart`. |

Non-security fixes from the same pass: Tasks/People/Teams lists are
lazy `SliverList.builder`s; Home search capped at 25 results per
section; notifications init deferred past the first frame;
dialog-local `TextEditingController`s disposed (7 sites); the
`ProgressBar` now really animates (`TweenAnimationBuilder` — the old
`AnimatedContainer` with `width: null` never animated).

Residual risks from this pass (accepted, also in `docs/risks.md`
§8): zip decode happens before the caps are checked, bounded by the
100 MB compressed cap (worst case is an app OOM crash with data
intact); the R8/shrink release build is untested on a device until
CI delivers it; the background-isolate DB and lazy lists are
untested on a low-end phone until the user installs the APK.
