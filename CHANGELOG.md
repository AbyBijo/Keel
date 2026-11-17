# Changelog

## 1.3.0 — 2026-11-17

Built 2026-11-17; release target: weekend 21–22 Nov 2026 (after on-device testing).

Haptics, notifications, Home scroll and the Teams + People merge
with Calendar, from on-device testing of 1.2.0.

### Haptics — what went wrong (diagnosed 2026-11-16)

- The settings wiring is correct: the toggle and the intensity save
  properly, the preview fires after saving, and the call sites exist.
  The bug is the API underneath. `HapticFeedback` on Android is not
  a vibration — it is a polite request to the system, and on many
  phones the system's touch-vibration setting is off, so the request
  is silently ignored: no error, no buzz, and the app never knows.
  Even when it does fire, Light / Medium / Heavy are a few
  milliseconds apart, so the three strengths feel almost identical.
- Fix: drive the motor directly with the `vibration`
  package — explicit durations and amplitudes per strength
  (Light ~15 ms soft, Medium ~30 ms, Heavy ~60 ms strong) — which
  does not depend on the system's touch-vibration toggle. Add a
  "Test vibration" button in Settings so the buzz can be checked
  on the spot, and wire haptics to more places (checkboxes, saves,
  deletes), not just tab taps and the add button.

### Notifications

- Today there is only one notification: a daily digest at a set
  time (default 8:00 AM). Two flaws: the digest text is computed
  once when it is switched on, then the same text repeats every
  day, so the counts go stale; and there are no per-task reminders
  — a task due at a set time never pings you.
- Fix: compute the digest counts fresh each morning;
  add per-task reminders — one on the due date and one when a task
  goes overdue (user decision, 2026-11-16: both); raise the
  channel to high importance so it shows and buzzes instead of
  arriving silently.

### Home scroll — what went wrong (diagnosed 2026-11-16)

- Sometimes the Home page refuses to scroll. The animations are
  NOT the cause: the dial's press spring and the ring's count-up
  are transform / opacity / paint only and never intercept touch,
  the dial listens with a `Listener` (which cannot steal a scroll
  gesture), the first-time fade-in runs once ever, and the
  scroll-to-top animation is 300 ms and is cancelled by a touch.
- The cause is the horizontal team strip nested inside the
  vertical Home list. A swipe starting on the strip pits the
  strip's horizontal drag against the page's vertical drag, and
  if the finger moves even slightly sideways first, the strip
  wins and the page never scrolls — it feels exactly like the app
  ignoring the swipe. It is intermittent because it depends on
  where the finger lands and the first millimetres of movement,
  and it is Home-only because no other tab nests a horizontal
  list. The tab bar's heavy background blur can also drop frames
  and make a scroll feel dead on weaker phones.
- Fix: rebuild the team strip so it cannot claim
  vertical drags (horizontal-only drag handling with a higher
  movement threshold), and verify on-device that a vertical swipe
  starting on the strip always scrolls the page. Also lighten or
  drop the tab bar's background blur, and stop recreating the
  Up-next future on every build (it reloads the section on each
  rebuild, which makes the list jump while scrolling).

### Edit sheets

- Editing a team or a person currently opens a small popup with
  only a few fields. In 1.3.0 both reuse their create sheet: the
  same slide-up window, pre-filled, with everything changeable —
  the way task editing already works.

### Task cards + Up next

- A task card currently lists every sub-todo, so a task with many
  sub-todos makes the card huge. In 1.3.0 the preview shows only
  the next sub-todo to do, and the done ones as a count ('2 of 8
  done'); the full list stays on the task page.
- A completed task currently vanishes from Home's Up next the
  moment it is ticked off. In 1.3.0 it drops to the bottom of the
  Up next list, under all open tasks, shown as done, and is
  removed after about 24 hours.

### Calendar + merged Teams tab

- Teams and People merge into one tab (sub-tabs Teams | People
  above the bottom bar, default Teams); Calendar takes People's
  spot — month view of task due dates, dots for open tasks,
  overdue red, tap a day to see and add its tasks, week rows
  follow Week Starts On. The merge and the calendar are wired
  through the whole app (Home tiles, tab bar, Add sheet, search,
  notifications), not a bolted-on tab.
- Calendar notes: the user can keep a note for a day and for a
  task. On a day, the day note is the most prominent thing shown;
  a task's note is shown with the task on its day.
- Calendar day view: a task ticked done stays on its day, under
  the open tasks, shown as done, and is gone after about 24
  hours — the same rule as Up next. Dots still mark open tasks
  only.

### Organizations

- Creating an organization from Settings asks for a name only
  and silently saves every new org as 'Other' — the type can
  never be chosen. In 1.3.0 creation is a proper flow: name plus
  a type picker (Studio, Company, Club, Family, Other), wherever
  organizations are created — as an uncluttered slide-up sheet
  like task/team creation. The initial org in onboarding keeps
  its own flow. The org list becomes one Apple-style grouped card
  with the organizations as rows inside it, instead of a separate
  card per org.

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
