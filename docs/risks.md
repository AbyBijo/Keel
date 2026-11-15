# Keel — pre-mortem (UI / settings / launch only)

Written before first release, in the OpenFlow style: only problems that
directly affect this app's UI, settings or launch. Backend/engine issues
are out of scope — Keel has no backend.

## 1. Splash / launch lingering

**Risk:** a splash or loading screen that never goes away, or the app
opening on the wrong first screen (onboarding again after setup, or a
blank Home while the DB opens).

**Mitigations in place:**
- No splash Activity and no splash screen widget: `main()` awaits
  `SharedPreferences` and then builds `KeelApp` directly; the home
  decision (`onboardingDone ? Shell : OnboardingScreen`) is a plain
  synchronous read of an already-loaded value.
- The DB opens lazily (`LazyDatabase`); screens show a
  `CircularProgressIndicator` while their first stream emits, never a
  full-screen blocker. `activeOrgProvider` yields `null` (not an error)
  when there are no organizations yet.
- Onboarding completion writes profile + org + `onboardingDone` before
  the rebuild, so the first Home render already has data.

**Still to verify on device:** cold start time on a low-end API 26
phone; the dial animating from zero on first Home paint.

## 2. Stuck navigation / dead back button

**Risk:** back does nothing, backs out of the app from a detail page,
or a sheet that cannot be dismissed.

**Mitigations in place:**
- Detail pages (team page, person card, task page) are pushed with
  `PageRouteBuilder` on the root navigator; the system back button
  pops them. Each has an explicit back affordance too.
- The shell's `PopScope(canPop: false)` only runs when the shell route
  itself is on top: FAB open → close it; non-Home tab → go Home;
  Home → exit. It cannot trap the user on a pushed page.
- All sheets are `showModalBottomSheet` with a drag handle and
  drag-to-dismiss; the FAB overlay closes on dim-area tap and on
  button tap. The task/person/team overview sheets are sheets, so
  back closes the sheet (they never push a route).
- Tab tap resets to that tab's root (IndexedStack) — no nested stacks
  to get lost in.

**Still to verify on device:** back from Team page → Teams; back from
Person card opened from a team page → Team page; back with the FAB
menu open; back with a create sheet open.

## 3. Dead settings

**Risk:** a settings row that does nothing, a toggle that doesn't
stick, or a setting that silently does nothing (Reminders).

**Mitigations in place:**
- Every settings row has a real handler (profile edit, org manager,
  accent picker, team colours, theme mode, text size, reduce motion,
  reminders + digest time, CSV export, clear completed, backup,
  restore, sample data, About). No placeholder rows.
- Settings are `SharedPreferences`-backed and read through a
  `ChangeNotifierProvider`, so a change rebuilds the app immediately
  (theme cross-fade, accent, text size).
- Reminders: enabling requests the notification permission first and
  says so in a snackbar if denied; the digest is scheduled with
  `matchDateTimeComponents: time` so it repeats daily.
- Destructive actions (clear completed, restore, delete org) all have
  confirm dialogs; restore validates the file before replacing data.

**Known gap:** if the user denies notifications and later enables
them in system settings, Keel does not re-schedule the digest until
the Reminders toggle is cycled. Acceptable for v1; the toggle row
shows the digest time so the state is visible.

## 4. Looping first-run / lost onboarding state

**Risk:** onboarding shows again after the user finished it, or the
app opens to an empty Home after the user created an organization.

**Mitigations in place:**
- `onboardingDone` is set only after profile + organization are
  written. If the app is killed mid-onboarding, it restarts onboarding
  (correct — no half-created workspace is shown as done).
- The active org is resolved defensively: stored id if it still
  exists, else the first organization, else `null` (empty state).
  Deleting the active organization switches to another one first;
  deleting the last organization is blocked with an explanation.

## 5. Frozen / blank loading states

**Risk:** a stream that never emits leaves a spinner forever (e.g.
after restore replaces all data, or after a failed DB open).

**Mitigations in place:**
- All streams are Drift `watch()` queries on a local file — they emit
  immediately, including an empty list. There is no network wait.
- Restore replaces data inside one transaction; streams re-emit the
  new state automatically. A failed restore (bad file) throws before
  any write, so the old data stays visible.
- Error branches exist on every `AsyncValue.when` (`error: ...`
  shows "Could not load …") instead of a bare spinner.

**Still to verify on device:** restore a real backup file and watch
every tab update; kill the app mid-backup and reopen.

## 6. First-paint jank / animation traps

**Risk:** the Home dial, the FAB stagger or the tab pill stutters on a
low-end phone; or an animation replays on every rebuild.

**Mitigations in place:**
- The dial animates from the previous value (`_from` kept in state),
  not from zero on every rebuild; reduce-motion replaces it with an
  instant value.
- Lists are lazy (`CustomScrollView` + `SliverList.builder` on Tasks,
  People and Teams; `ListView.builder` for the Home team strip), and
  task cards watch only their own assignees/sub-todos streams, so one
  checkbox change does not rebuild the whole list. Database queries
  run on a background isolate (`NativeDatabase.createInBackground`,
  2026-11-15), so a heavy query cannot block a frame. Photos decode
  at display size (`cacheWidth`/`cacheHeight` in `PersonAvatar`).
- The first-time staggered Home reveal runs once (`homeSeenOnce`
  persisted) and is skipped entirely when reduce-motion is on.
- Buttons wrap to two lines instead of overflowing at 200% text
  scaling (caught by widget tests, which render with a wider test
  font).

## 7. What this pre-mortem does NOT cover

Engine, sync or cloud issues — Keel has none by design. If a future
version adds any network feature, this document needs a new section.

## 8. Audit pass 2026-11-15 — residual risks

From the update-5 audit (details + fixes in `docs/security.md` §6).
These are accepted for v1 and must be verified on a real phone:

- **Zip decode before caps.** The entry/size caps are checked after
  `archive.decodeBytes` — bounded by the 100 MB compressed cap, so
  the worst case is an app OOM crash with data intact (the restore
  transaction never starts). A streaming decoder would close this
  fully; not available in the pinned `archive` version without a
  rewrite.
- **R8 + resource shrinking on release.** Newly enabled and made
  explicit for release; a wrong keep rule can only show up at
  runtime (e.g. a reflection-based plugin call). The release APK
  must be smoke-tested on the device before it is trusted.
- **Background-isolate DB.** `NativeDatabase.createInBackground`
  changes every query's threading; on a low-end phone the first
  queries may be slower than the old main-isolate path. Watch cold
  start and first Home paint on the device.
- **Per-ABI split.** Three APKs instead of one fat APK: the user
  must install the APK matching his phone's ABI (CI names them
  `app-arm64-v8a-release.apk` etc.).
