# Changelog

## 1.2.0 — 2026-11-15

On-device fix round, based on testing the 1.1.0 build on a real phone.

### Fixed

- New people now appear instantly on the Persons page, whether added
  from the People tab or from inside the Create Team sheet (the list
  was fed by a one-shot future and went stale after an insert; it now
  streams live from the database). Regression tests added.
- About page account links (GitHub, LinkedIn, Buy Me a Coffee) now
  open in the phone's browser (Android 11+ was blocking the check
  because the app did not declare browser intents; links now launch
  directly and only show a message if opening genuinely fails).
- Team colour picker in the create/edit team sheet no longer overflows
  on narrow screens — the swatch row scrolls sideways.

### Changed

- Text size is now a slider with four locked stops: Small, Medium,
  Large, Extra Large.
- Home progress dial: the arc animates with an ease-in-out curve, and
  the whole dial card now responds around the touch point (press scale
  + soft highlight, spring 300/26; reduce-motion = simple fade).
- About tagline is centre-aligned.
- Profile edit fields now have visible labels (Name, Role, Phone,
  Email, Notes).
- Team colour editing removed from Settings → Personalisation (it
  already lives in the team itself).

### Added — Personalisation

- Haptics on/off toggle. When off, every haptic in the app is silent.
- Vibration Intensity (Light / Medium / Heavy, default Medium) —
  always visible; when Haptics is off it shows greyed out and
  untouchable. Tapping an intensity saves it, shows it selected, and
  plays a preview buzz at that strength so you can feel what you
  picked.
- Week starts on (Monday / Saturday / Sunday, default Monday),
  persisted and wired into the week-boundary helper used by future
  week-based views.

## 1.1.0 — 2026-11-15

- Launcher icon rebuilt from the real Material `anchor_rounded`
  glyph (white on kit teal), proper adaptive icon + legacy mipmaps.
- Signed per-ABI release builds (arm64-v8a 22.4 MB, armeabi-v7a
  20.0 MB, x86_64 23.6 MB) and debug APK (77.3 MB) as GitHub Actions
  artifacts; no GitHub Release.
- Task overview sheet + full task page; person overview sheet with
  Call on the right and Message (WhatsApp) below it.
- Package renamed to `com.keel.manager`.
- Optimisation + security audit: background-isolate database, JOINs
  instead of N+1 lookups, lazy lists, photo decode at display size,
  hardened backup validation and restore caps.

## 1.0.0 — 2026-11-15

- First release: offline organization manager — organizations, teams,
  people, tasks, sub-todos, reminders, backup/restore, dark mode,
  sample data.
