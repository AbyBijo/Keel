# Keel (native) — Security review

## Permissions

- **No INTERNET permission** in the manifest — by design. The app cannot
  reach the network at all, so there is no exfiltration path.
- `POST_NOTIFICATIONS` — runtime permission, only asked when the user
  turns on the daily digest (off by default).
- `CAMERA` — runtime permission, only for person photos taken in-app
  (picker not yet wired; see DECISIONS.md).
- `SCHEDULE_EXACT_ALARM` — for the daily digest alarm; falls back to an
  inexact repeating alarm when the user has not granted exact alarms.

## Data

- All data lives in the app's private SQLite database (`keel.sqlite`) and
  DataStore. No account, no server, no analytics, no trackers, no crash
  reporting.
- All SQL goes through Room (compile-time checked, parameterised). No raw
  string-concatenated queries anywhere.
- Backups are written only through the Storage Access Framework (the user
  picks the destination). **The backup file is validated before any data
  is replaced** (`Repository.validateBackup`: format string, version, all
  required lists present). Import runs inside one Room transaction, so a
  bad file cannot leave half-imported data.
- Backup size is capped at 200 MB (same as the Flutter build).
- Photos: `photoPath` is a file name only. `BackupService.photoFile()`
  strips any directory with `File(name).name`, so a crafted backup cannot
  write outside `filesDir/photos/`. Photo files are validated by
  **magic bytes** (JPEG / PNG / WebP), never by extension.
- The debug keystore is committed as base64 text (`keystore/debug.keystore.b64`)
  with debug-only credentials (`keel-debug`). That is the VoxFlow pattern:
  debug keys are public by design and cannot sign a release. The release
  keystore is never generated or committed; CI reads it from secrets.
- No secrets, API keys or tokens anywhere in the code.

## Dependencies (all pinned — no floating versions)

| Dependency | Version | Notes |
|---|---|---|
| AGP | 8.9.1 | |
| Kotlin | 2.1.0 | |
| KSP | 2.1.0-1.0.29 | |
| Compose BOM | 2025.01.00 | ui, material3, foundation, animation |
| core-ktx | 1.15.0 | |
| lifecycle | 2.8.7 | runtime-compose, viewmodel-compose |
| activity-compose | 1.9.3 | |
| navigation-compose | 2.8.5 | declared, not yet used by the UI |
| Room | 2.7.0 | runtime, ktx, testing |
| datastore-preferences | 1.1.1 | |
| coroutines | 1.9.0 | android |
| coroutines-test | 1.8.1 | test only |
| junit | 4.13.2 | test only |
| robolectric | 4.13 | test only |
| androidx.test:core | 1.6.1 | test only |
| material-icons-core | 1.7.8 | outline icons |

No dependency with a known critical CVE was introduced at build time;
the set is the current stable set for the pinned BOM. Re-check with
`./gradlew dependencyCheck` (or the GitHub dependency graph) when the
versions are next bumped.

## Known limitations

- The debug keystore is in the repo by design (see above) — it must never
  be used for release, and the release config falls back to it only when
  `key.properties` is absent (local dev). CI always supplies the real
  release key when the secrets exist.
- Exact alarms need the user's grant on Android 12+; without it the digest
  uses an inexact alarm and may arrive late. That is a deliberate
  graceful degradation, not a silent failure.
- The app has not had an on-device security review (no device test yet).
