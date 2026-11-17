# Keel — decisions

Every decision made where the master prompt was unspecified, plus
anything not done. Read this before changing behaviour.

## Decisions

1. **Flutter, not React Native.** Prompt's preferred choice; best
   match for a single-codebase offline app with custom animation.
2. **Drift `People` table → `Person` data class.** Drift would have
   generated `PeopleData`; `@DataClassName('Person')` keeps the code
   readable. Table/column names in SQLite are unchanged (`people`).
3. **Master prompt wins over the kit README where they differ.** The
   kit README says a person has "one email"; the master prompt says
   many emails (`PersonEmail` table, many per person). Implemented
   many emails.
4. **Undo = delete now + in-memory snapshot restore (6 s), not a
   `deletedAt` column.** User-visible behaviour is identical (Undo
   within 6 s restores everything, including children). A `deletedAt`
   column would have required filtering every query and treating
   soft-deleted teams as "no team" in task queries; the snapshot
   approach keeps all queries simple and honest. Trade-off: if the app
   is killed inside the 6 s window, the delete stands (no restore).
   Documented in `docs/security.md` §3.
5. **Circular FK gap handled in code.** `Teams.mainTaskId → Tasks`
   and `Tasks.teamId → Teams` are circular, so Drift drops the
   `Tasks.teamId` FK constraint at codegen (warning). The repository
   enforces the same semantics explicitly: `deleteTeam` nulls task
   team ids first; `_deleteTaskRows` clears main-task pointers first.
6. **FAB on Home only.** The prompt describes the floating Add button
   in the Home section. Tasks / Teams / People have an accent "+" in
   their header instead, opening the same create sheets.
7. **Icons: Material outlined set, 24px.** The kit asks for one
   consistent 24px outline set, 1.9 stroke, round caps. A hand-drawn
   icon font was out of scope for v1; Material outlined icons are
   visually consistent and meet the size/weight closely enough.
8. **Date picker is the themed Material picker.** A fully custom
   calendar would have been a second app; the picker is themed to the
   Keel palette (accent header, card background) and works.
9. **Photo "crop to circle": display crop.** The photo is stored
   as-picked (max 1024px) and shown inside a circular clip with the
   team-colour ring. There is no destructive crop step; the visible
   result is a circle in every surface. A real crop UI was cut for v1.
10. **Notifications: daily digest only, exact time via
    `inexactAllowWhileIdle`.** Android may shift the digest by minutes
    to save battery; acceptable for a digest. No per-task alarms in v1
    (the prompt asks for a daily digest; per-task reminders would need
    exact-alarm permission).
11. **Text size: system scaler × in-app setting.** The in-app text
    size (Small/Default/Large/Extra large = 0.85/1.0/1.15/1.3)
    multiplies the OS accessibility scaler, so 200% system scaling
    still works. Buttons wrap to two lines instead of overflowing.
12. **Accent colour default is kit teal; a custom accent applies
    app-wide** (tab pill, buttons, links). Team colours are separate
    and unaffected.
13. **Deleting the last organization is blocked.** Otherwise the app
    would have no active org and would need to re-run onboarding.
    The snackbar says "Keep at least one organization."
14. **Restoring a person does not restore their leadership.** If a
    deleted leader's teams got a replacement, Undo brings the person
    back as a member but does not silently take leadership back.
    (Their memberships and assignments are restored.)
15. **Sub-todo completion offers the parent prompt but never
    auto-completes the parent.** Per rule 7: completing all sub-todos
    shows an inline prompt; the user taps Complete. Reopening a
    sub-todo reopens the parent automatically.
16. **Sample data is additive and repeatable.** "Load sample data"
    can be tapped more than once; it adds another Northwind set.
    The app starts empty; nothing is seeded automatically.
17. **No blue overlay rule applied globally** via theme
    (`splashColor`/`highlightColor`/`hoverColor`/`focusColor`
    transparent) and text fields use a neutral grey focus border.
18. **Buy Me a Coffee URL is TO-CONFIRM** (`lib/links.dart`):
    `https://www.buymeacoffee.com/AbyBijo` — the user has not
    confirmed this username yet.
19. **Debug keystore: standard Android debug key. Release keystore:
    GENERATED 2026-11-15** (`keel-release`, RSA 2048, valid to
    2054-04-02; keystore + password only in the user's files folder;
    4 GitHub secrets set). See README → Signing.
20. **CI workflow builds the DEBUG apk + the signed RELEASE apk**
    (per-ABI split) as Actions artifacts on every push to main. The
    release job is gated on the four `ANDROID_*` secrets (see
    `.github/workflows/android.yml`); they are set, so both build.
    No GitHub Release is ever created.
21. **Tile tap = overview sheet, arrow = full page** (2026-11-15).
    Task, Team and Person tiles all follow the same rule: tapping the
    tile (except the arrow) slides up a read-only overview sheet with
    quick actions; the arrow opens the full page. Task page is new
    (`lib/task_page.dart`). The person sheet's Message button opens
    WhatsApp (`wa.me/<digits>`); Call is on the right with Message
    directly below it.
22. **Launcher icon = real `anchor_rounded` glyph** (2026-11-15).
    Rendered from the Flutter SDK's MaterialIcons font (U+F562), white
    on solid teal, as a proper adaptive icon with legacy mipmaps and a
    1024px master (`assets/icon-1024-v2.png`). The first hand-drawn
    icon had disconnected flukes and is deleted.
23. **Size levers** (2026-11-15): per-ABI release split; R8 +
    resource shrinking made explicit; the duplicated `assets/fonts/`
    entry removed (fonts were bundled twice, ~1.9 MB). Expected
    ~7–12 MB per ABI; exact number from CI.
24. **Audit + optimization pass** (2026-11-15, see `docs/security.md`
    §6 and `docs/risks.md` §5): DB runs on a background isolate
    (`NativeDatabase.createInBackground`); N+1 lookups replaced with
    JOINs; Tasks/People/Teams lists are lazy `SliverList.builder`s;
    Home search capped at 25 per section; photos decode at display
    size; backup validation hardened (missing lists, damaged rows)
    and restore capped (100 MB file, 5000 entries, 25 MB per file,
    100 MB expanded); restore catches non-FormatException errors;
    notifications init deferred past first frame; dialog-local
    controllers disposed. The `ProgressBar` now really animates
    (the old `AnimatedContainer` with `width: null` never did).

## Not done / known gaps

- **No on-device test yet.** The debug APK builds locally, but no
  phone was available in this VM. On-device checks still open:
  model-free — install, onboarding, dial animation, FAB menu, photo
  pick, backup/restore round-trip, reminders digest, rotation,
  200% text scaling, dark mode on every screen.
- **App icon: regenerated from the real `anchor_rounded` glyph**
  (2026-11-15, `assets/icon-1024-v2.png`): proper adaptive icon
  (foreground/background split) + legacy mipmaps at every density.
  The first hand-drawn icon (disconnected flukes) is deleted.
- **Drag-reorder of sub-todos uses `ReorderableListView` inside the
  task detail sheet** with a fixed height (max ~260px, 5 rows visible
  with internal scroll disabled). Long sub-todo lists scroll the
  sheet, not the list. Works, but the drag area is the whole row.
- **Team page "Set as main" chip overlaps the task card's bottom
  right.** It is positioned over the card intentionally; on very
  narrow screens with long sub-todo lists it can sit close to the
  last sub-todo row. Acceptable; flagged for a visual check.
- **`flutter pub outdated` shows newer versions** for several pinned
  packages (e.g. `uuid` 4.6.0). Pinned versions were kept because
  they are the versions the build was verified against.
- **The Home "Up next" list is a `FutureBuilder`** (re-queries on
  rebuild) rather than a stream; it refreshes whenever Home rebuilds,
  which happens on any task change. Fine for v1.
- **No tablet-specific layout.** Phones first per the prompt;
  tablets get the phone layout stretched (max content width is not
  capped). A 600dp cap is an easy follow-up.

## v1.2.0 — on-device fix round (2026-11-15)

Release version. `pubspec.yaml` bumped to `1.2.0+2`
(was `1.0.0+1`); `CHANGELOG.md` created. README rewritten as a
public product page (no developer Structure / Where-to-edit / Tests
/ Signing sections; developer material is one short "For developers"
section at the end). Real CI sizes stated everywhere: release
arm64-v8a 22.4 MB, armeabi-v7a 20.0 MB, x86_64 23.6 MB; debug
77.3 MB. The old 7–12 MB estimate is dropped.

25. **Persons list staleness (P0, user-reported on-device).**
    Root cause, confirmed by reading the code: `PeopleScreen`
    watched both `peopleProvider` (live StreamProvider) and
    `filteredPeopleProvider` (a one-shot `FutureProvider.family`),
    and displayed the future's result — so after any insert the
    list went stale, and the Shell's `IndexedStack` kept the stale
    screen alive across tab switches. Fix:
    `filteredPeopleProvider` is now a `StreamProvider.family`
    driven by a merged trigger stream (live `watchPeople` +
    Drift watches on personPhones/personEmails/teamMembers +
    `watchTeams`), so the list rebuilds live on every person add /
    edit / delete and on team-create-with-new-person. `people.dart`
    needed no change (same watch API). Regression tests:
    `test/people_live_test.dart` (direct add; team-sheet flow).
    Other `FutureBuilder`s are one-shot lookups re-created per
    build, not the same bug; teams/tasks lists already use live
    `StreamProvider`s — verified, left alone.

26. **About links not reaching the browser (user-reported).**
    Root cause: `AndroidManifest.xml` `<queries>` declared only
    the `PROCESS_TEXT` intent — no `VIEW`/`BROWSABLE` https/http
    declaration, so on Android 11+ `canLaunchUrl` false-negatived
    and `_open` showed "Could not open". Fix: manifest now declares
    `VIEW`+`BROWSABLE` for https/http plus tel/mailto/sms; `_open`
    (settings), `_launch` (sheets, WhatsApp `wa.me`) and `_launch`
    (people, tel/mailto/sms) launch directly and check the returned
    bool, try/catch, snackbar only on genuine failure. No WebView
    anywhere. Buy Me a Coffee URL confirmed from chat history
    (`https://www.buymeacoffee.com/AbyBijo`); TO-CONFIRM comments
    removed.

27. **Text size slider.** The picker dialog is replaced by a
    `Slider` (min 0, max 3, `divisions: 3`) with four locked stops
    0.85 / 1.0 / 1.15 / 1.3 labelled Small / Medium / Large /
    Extra Large, in Settings → Personalisation where the picker row
    was. Persists via the existing `setTextScale`; `main.dart`
    combined system × in-app scaling untouched. ("Default" renamed
    to "Medium".)

28. **Progress dial animation.** Arc now uses `Curves.easeInOut`
    (chosen over `easeInOutCubic`: the cubic variant's long slow
    tails would make the 700 ms count-up feel sluggish).
    `_DialCard` is a `StatefulWidget` with region-based touch
    response: `Listener` records the pointer-down position; press
    drives scale 1 → 0.97 and a soft white radial highlight centred
    at the touch point (opacity 0.14 × press), springing back with
    `SpringSimulation` (300/26, kit spec); transform/opacity only,
    no blue ripple; reduce-motion = simple `AnimatedOpacity` fade.
    Count-up behaviour kept.

29. **About tagline centred.** "One manager. Many teams.
    Everything stays on your phone." is wrapped in `Center` +
    `textAlign: TextAlign.center`.

30. **Profile field labels.** `_editProfile` (Settings → Profile)
    now has `labelText: 'Name'` / `'Role'`; `_NewPersonSheet`
    passes `label:` to `KeelTextField` for Name / Role / Phone /
    Email / Notes (kit pattern). Validation, controllers, saving
    unchanged. Out of scope, not changed: `_editPerson`
    (people.dart) and onboarding name/role fields — same hint-only
    pattern, follow-up candidates.

31. **Team colour removed from Settings → Personalisation.** The
    'Team colors' row and the whole `_manageTeamColors` method are
    deleted; no setting/preference/provider entry existed only to
    serve it (colours live per-team as `colorHex`). Team-colour
    editing inside team screens unchanged. Accent colour verified
    present in Personalisation already — left exactly as is, not
    duplicated.

32. **Team colour picker overflow.** `ColorPickerField`'s preset
    swatch `Row` (6 × 38 px + gaps ≈ 326 px) overflowed narrow
    sheets. It now wraps in a horizontal `SingleChildScrollView`;
    same 6 presets, same selection ring and tap behaviour.

33. **Haptics + Vibration Intensity (Personalisation).** New
    settings: `haptics_on` (default `true`), `haptic_strength`
    (default `'medium'`). All three `HapticFeedback` call sites
    (checkbox, tab tap, Add button) now go through one helper,
    `lib/haptics.dart` (`KeelHaptics.impact` / `.selection` /
    `.preview`): off means silent everywhere; strength maps
    Light → `lightImpact`, Medium → `mediumImpact`, Heavy →
    `heavyImpact`. Selection taps use the same strength mapping as
    impacts (not a separate `selectionClick`), so the feel is
    uniform. The Vibration Intensity control is ALWAYS visible:
    when Haptics is off it shows greyed out (opacity 0.45) and
    untouchable (`IgnorePointer`, taps do nothing, no preview);
    when on, tapping Light/Medium/Heavy saves it, shows it
    selected (filled accent pill + check) and immediately plays a
    preview buzz at exactly that strength.

34. **Week Starts On (Personalisation).** New setting `week_start`
    (default `'monday'`), picker dialog with exactly Monday /
    Saturday / Sunday. Surveyed the code: the app computes NO
    week boundary today — due-soon is a fixed 2-day window
    (master-prompt rule 8, must not change), Up next orders by due
    date, due labels only name the weekday. Nothing hard-coded a
    week start, so nothing was rewired; the setting is persisted
    and the new pure helper `startOfWeek` (`lib/theme.dart`) reads
    it, tested in `test/week_start_test.dart`, ready for the first
    week-based view.

37. **Edit reuses the create sheet — teams and people (user
    decision, 2026-11-16, not yet built).** Tasks already work
    this way: editing opens the same slide-up sheet as creating,
    pre-filled, with everything changeable. Teams and people do
    not: `_editTeam` (`teams.dart`) and `_editPerson`
    (`people.dart`) are small `AlertDialog` popups — name +
    colour for a team, name + role + notes for a person. In
    1.3.0 both are replaced: 'Edit team' (three-dot menu and
    inside the team page) opens the create-team sheet pre-filled
    — name, colour, leader, members, main task, all changeable
    from that one window; editing a person opens the
    create-person sheet pre-filled — phones, emails, photo, notes
    and teams all changeable. One sheet for create and edit, no
    separate edit popups.

38. **Task card sub-todo preview + Up next keeps done tasks 24 h
    (user decisions, 2026-11-17, not yet built).** The task card
    currently lists every sub-todo, so a task with many sub-todos
    makes the card huge. In 1.3.0 the preview shows only what
    matters right now: the next sub-todo to do, and the done ones
    as a count ('2 of 8 done') — the full list lives on the task
    page. Up next currently filters out done tasks at once
    (`upNext` keeps only `!isDone`), so a ticked-off task vanishes
    from Home instantly. In 1.3.0 a completed task drops to the
    bottom of the Up next list, under all open tasks, shown as
    done, and is removed after about 24 hours. (Correction
    2026-11-17: bottom of the list, not under the next task as
    first articulated.)

39. **Calendar notes — day notes and task notes (user decision,
    2026-11-17, not yet built).** The calendar lets the user keep
    a note for a day and also for a task (task notes already
    exist). On a day, if the day has a note it is the most
    prominent thing shown; if a task on that day has a note, that
    note is shown with the task — on the day the task is assigned
    or its deadline day. Day notes are new (a day-note store
    scoped to the active organization); task notes ride on the
    existing task notes field.

40. **Organization creation must let the user pick the type; org
    rows combined Apple-style (user decision, 2026-11-17, not yet
    built).** Creating an organization from Settings opens a bare
    popup asking for a name only, then silently saves every new
    org as kind 'Other' — the type can never be chosen, which is
    why existing orgs all show 'Other' even though the app
    supports Studio, Company, Club, Family, Other. In 1.3.0
    creation becomes a proper flow: name plus a type picker with
    the five kinds, in a proper sheet, applied wherever
    organizations are created (Settings and the org switcher).
    The org list tiles are combined Apple-style: one grouped card
    with the organizations as rows inside it (iOS Settings
    style) instead of a separate card per org, keeping the active
    check and the three-dot menu, without breaking the existing
    look. Refinement (user, 2026-11-17): the creation form must
    stay uncluttered and easy — the same slide-up sheet pattern
    as creating a task or a team (name + type picker, done right
    there), not a long form. The only organization creation that
    goes through a longer flow is the initial one inside
    onboarding, which already has its own kind picker (default
    Studio); that stays exactly as it is.

35. **Merge Teams + People; add a Calendar tab (user decision,
    2026-11-16, not yet built).** The bottom bar stays five tabs:
    Home, Tasks, Teams (merged), Calendar, Settings. Calendar
    takes People's old spot (index 3). The merged Teams tab gets
    two sub-tabs (segmented control) just above the bottom bar,
    Teams | People, defaulting to Teams; both lists keep their own
    screens, People keeps its live search, and the Home stat tiles
    route to the right sub-tab. Rejected: merging Tasks + Teams
    (buries the daily task list and breaks the Home shortcuts into
    it) and merging Tasks + People (unrelated lists — contacts and
    calls have nothing to do with the task list). Teams + People
    won because they are the same domain: a team is people, every
    person is a potential member or leader, and the database
    already joins them (`TeamMember`). Calendar: month view of task
    due dates (the only dates in the app), scoped to the active
    organization; dots on days with open tasks, overdue in red;
    tap a day to see that day's tasks, with a way to add a task due
    that day; week rows start on the Week Starts On setting, which
    finally gets a visible use. Part of the v1.3.0 scope with the
    haptics fix, the notification rework and the Home scroll fix
    (see CHANGELOG.md Unreleased). Build rule (user, 2026-11-17):
    the merge and the calendar are wired through the whole app —
    Home tiles, tab bar, Add sheet, search, notifications, week
    start — not a bolted-on tab.

36. **Per-task reminders fire twice (user decision, 2026-11-16).**
    A task with a due date gets one reminder on its due date and
    a second one when it goes overdue — both, not one or the
    other. Tasks carry due dates, not times, so the due-date
    reminder lands on the due day; the exact time of day for each
    is a build-time detail.

41. **Calendar day view keeps done tasks 24 h (user decision,
    2026-11-17).** In the Calendar, when a person ticks a task
    done for a day, it must stay on that day's list, but under
    all the other to-do tasks for that day — exactly like Up
    next: a completed task drops to the bottom under all open
    tasks, shown as done, removed after about 24 hours. Same
    ~24 h rule as Up next (item 38), reusing `Task.completedAt`;
    no new rule invented. Dots are unchanged: they still mark
    days with open tasks only, red when overdue. The day list is
    stream-fed (`tasksProvider`), so the tick reorders the list
    at once without leaving the page.
