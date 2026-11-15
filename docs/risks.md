# Keel (native) — Pre-mortem (UI / settings / navigation only)

Per the brief, this pre-mortem covers only the problems that directly
affect the app's UI, settings and navigation — the same scope as the
OpenFlow pre-mortem. Backend/engine risks are out of scope.

## What could go wrong

### 1. The tab bar hides content
**Risk:** the frosted 86dp tab bar and the FAB overlap the bottom of a
list, hiding the last item or its action.
**Mitigation:** every scrollable screen uses `contentPadding(bottom = 120dp)`.
**Check on device:** scroll each tab to the bottom and confirm the last
row is fully visible above the tab bar.

### 2. Sheet vs page confusion
**Risk:** users tap a tile expecting the full page (or the chevron
expecting the sheet) and feel lost.
**Mitigation:** consistent pattern everywhere — tile = overview sheet with
quick buttons, chevron = full page. Same as Teams, which the user already
knows. The sheet's first button is "Open …" for the full page.
**Check on device:** tap tile, tap chevron, on Tasks, Teams and People.

### 3. The FAB pills cover the list
**Risk:** opening the FAB covers the Home content and the user cannot tell
how to close it.
**Mitigation:** the FAB rotates 45° into a close button; tapping it again,
tapping a pill, or pressing Back closes it. The pills are above the FAB,
not over the dial.
**Check on device:** open/close the FAB, pick each pill, press Back.

### 4. Undo snackbar is missed
**Risk:** a delete happens, the 6-second snackbar is missed, and the user
thinks the data is gone forever.
**Mitigation:** the snackbar sits above the tab bar (96dp bottom padding)
with a clear "Undo" action; deletes of teams and people state what was
kept ("Team deleted — people and tasks kept").
**Check on device:** delete a task, wait, confirm the Undo window.

### 5. Dark mode contrast
**Risk:** muted text or the dial card reads poorly in dark mode.
**Mitigation:** dark tokens are the kit's own (`#0A1118` / `#142029` /
`#EAF1F5` / `#8696A3` / `#3CC3CF`); the dial card is dark in both modes
so its white text is always safe.
**Check on device:** toggle System / Light / Dark in Settings and read
every screen.

### 6. Text scaling breaks layouts
**Risk:** at 150% text size, titles wrap badly or chips overflow.
**Mitigation:** text scale is capped at 1.5x; rows use `maxLines` +
ellipsis; chips wrap in `FlowRow` where they can overflow.
**Check on device:** set text size to max and open Home, Tasks, People.

### 7. Reduce-motion is not actually reducing motion
**Risk:** the setting exists but a spring still fires somewhere.
**Mitigation:** `LocalReduceMotion` is read in `ProgressRing` (snap
instead of count-up), the FAB pills (fade instead of slide) and the
theme; springs are the only other motion source.
**Check on device:** enable Reduce motion, watch the dial and the FAB.

### 8. The launcher icon still looks wrong in a real drawer
**Risk:** the adaptive icon is verified from rendered previews, not from
a real launcher, which may crop or mask it differently.
**Mitigation:** glyph sits in the central 60 of the 108 viewport (inside
the safe zone); legacy PNGs are supplied for older launchers.
**Check on device:** install and look at the drawer icon next to the
About-page icon — they must match.

### 9. Back behaviour surprises
**Risk:** Back from a detail page exits the app instead of returning.
**Mitigation:** a `BackHandler` closes the FAB, then the detail page,
then returns to Home, and only then lets the system exit. Sheets handle
their own Back (drag down / scrim / Back).
**Check on device:** open a team page, press Back; open a sheet, press Back.

### 10. Settings changes do not stick
**Risk:** a theme/accent/text-size change reverts after restart.
**Mitigation:** every setting is written to DataStore immediately and the
UI reads it as a Flow; the theme and density are applied at the root.
**Check on device:** change theme and text size, kill the app, reopen.

### 11. The digest never fires (or fires at the wrong time)
**Risk:** the alarm is lost after reboot or the exact-alarm permission
is denied.
**Mitigation:** the receiver re-schedules itself on every fire; without
exact-alarm permission it falls back to an inexact daily alarm; a
`BootReceiver` re-schedules the digest after a reboot.
**Check on device:** enable the digest, confirm the notification arrives.

### 12. Restore replaces data the user wanted to keep
**Risk:** importing a backup wipes current data without a clear warning.
**Mitigation:** the backup card states plainly that restoring replaces
everything and the file is checked first; the user picks the file.
**Check on device:** export, add a task, restore, confirm the task is gone
and the backup content is back.
