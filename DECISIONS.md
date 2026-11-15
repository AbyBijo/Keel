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
    NOT generated yet.** Awaiting the user's signing confirmation,
    per the brief. See README → Signing.
20. **CI workflow builds the DEBUG apk only** until release secrets
    exist. The release job is present in the workflow but gated on
    the four `ANDROID_*` secrets (see `.github/workflows/android.yml`).

## Not done / known gaps

- **No on-device test yet.** The debug APK builds locally, but no
  phone was available in this VM. On-device checks still open:
  model-free — install, onboarding, dial animation, FAB menu, photo
  pick, backup/restore round-trip, reminders digest, rotation,
  200% text scaling, dark mode on every screen.
- **App icon: generated locally** (teal gradient rounded square + white
  anchor, `assets/icon-1024.png`, mipmaps replaced). Adaptive icon
  (foreground/background split) not yet done — legacy mipmaps only.
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
