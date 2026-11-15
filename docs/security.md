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
  `mailto:` / `sms:` intents from a person card — all explicit user taps.
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
| flutter_local_notifications | 19.4.2 | Daily digest only, local. |
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
  (`KeelRepository.validateBackup`). Files over 200 MB are rejected.
  Photos inside the zip are written to app-private storage and paths
  are rewritten to the new location. Restore runs inside one
  transaction.
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
