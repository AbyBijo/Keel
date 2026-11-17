import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'db.dart';
import 'providers.dart';
import 'repo.dart';
import 'services.dart';
import 'sheets.dart';
import 'task_card.dart';
import 'task_page.dart';
import 'teams.dart';
import 'theme.dart';
import 'widgets.dart';

/// The 42 grid days for the month containing [month], starting on
/// the week-start day. Pure — see test/calendar_test.dart.
List<DateTime> calendarGridDays(DateTime month, String weekStart) {
  final first = DateTime(month.year, month.month);
  final start = startOfWeek(first, weekStart);
  return List.generate(42, (i) => start.add(Duration(days: i)));
}

/// Open dated tasks grouped by day key. Done tasks are not shown on
/// the calendar — it is a view of what is still due. Pure.
Map<String, List<Task>> tasksByDay(List<Task> tasks) {
  final map = <String, List<Task>>{};
  for (final t in tasks) {
    if (t.isDone || t.dueDate == null) continue;
    (map[dayKey(t.dueDate!)] ??= []).add(t);
  }
  return map;
}

/// The tasks shown for one day in the day list (1.3.0, DECISIONS.md
/// 41): open tasks due that day first, then tasks due that day
/// completed within the last ~24 hours, most recently completed
/// first, shown as done. Same 24 h rule as Up next ([selectUpNext])
/// — a ticked-off task stays on its day under the open tasks instead
/// of vanishing, and is gone after about 24 hours. Dots are
/// untouched: [tasksByDay] still feeds them with open tasks only.
/// Pure.
List<Task> dayTasks(List<Task> tasks, DateTime day, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final key = dayKey(day);
  final open = tasks
      .where(
        (t) =>
            !t.isDone && t.dueDate != null && dayKey(t.dueDate!) == key,
      )
      .toList();
  final recent = tasks
      .where(
        (t) =>
            t.isDone &&
            t.dueDate != null &&
            dayKey(t.dueDate!) == key &&
            t.completedAt != null &&
            !t.completedAt!.isAfter(n) &&
            n.difference(t.completedAt!) < const Duration(hours: 24),
      )
      .toList()
    ..sort((a, b) => b.completedAt!.compareTo(a.completedAt!));
  return [...open, ...recent];
}

/// Calendar tab (1.3.0, DECISIONS.md 35 + 39): a month view of task
/// due dates — the only dates in the app — scoped to the active
/// organization. Dots on days with open tasks, red when overdue;
/// tap a day to see that day's tasks, add a task due that day, and
/// keep a note for the day. Week rows start on the Week Starts On
/// setting, which finally gets a visible use.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _month;
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _selected = DateTime(now.year, now.month, now.day);
  }

  @override
  Widget build(BuildContext context) {
    final orgIdAsync = ref.watch(activeOrgProvider);
    final scrollController = ref.watch(tabScrollControllersProvider)[3];
    final settings = ref.watch(settingsProvider);

    return orgIdAsync.when(
      data: (orgId) {
        if (orgId == null) return const SizedBox.shrink();
        final tasksAsync = ref.watch(tasksProvider(orgId));
        final notesAsync = ref.watch(dayNotesProvider(orgId));
        final tasks = tasksAsync.value ?? const [];
        final notes = notesAsync.value ?? const [];
        final byDay = tasksByDay(tasks);
        final noteByDay = {for (final n in notes) n.date: n};
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final days = calendarGridDays(_month, settings.weekStart);
        final teams = ref.watch(teamsProvider(orgId)).value ?? const [];
        Team? teamOf(String? id) => teams.where((t) => t.id == id).firstOrNull;
        final selectedKey = dayKey(_selected);
        // The day list keeps recently completed tasks at the bottom
        // (DECISIONS.md 41); the grid dots above still use byDay,
        // open tasks only. The list is stream-fed (tasksProvider),
        // so ticking a task done reorders it at once, in place.
        final selectedTasks = dayTasks(tasks, _selected);
        final selectedNote = noteByDay[selectedKey];

        return CustomScrollView(
          controller: scrollController,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 54, 18, 130),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Month header: previous / title / next + Today.
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            DateFormat('MMMM yyyy').format(_month),
                            style: Theme.of(context).textTheme.displayLarge,
                          ),
                        ),
                        TextButton(
                          onPressed: () => setState(() {
                            _month = DateTime(today.year, today.month);
                            _selected = today;
                          }),
                          child: Text(
                            'Today',
                            style: TextStyle(color: context.accent),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.chevron_left, color: context.accent),
                          onPressed: () => setState(() {
                            _month = DateTime(_month.year, _month.month - 1);
                          }),
                          tooltip: 'Previous month',
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.chevron_right,
                            color: context.accent,
                          ),
                          onPressed: () => setState(() {
                            _month = DateTime(_month.year, _month.month + 1);
                          }),
                          tooltip: 'Next month',
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Weekday header, starting on the week-start day.
                    Row(
                      children: [
                        for (var i = 0; i < 7; i++)
                          Expanded(
                            child: Center(
                              child: Text(
                                DateFormat('EEE').format(days[i]),
                                style: TextStyle(
                                  color: context.muted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Month grid: 6 rows of 7 days.
                    for (var w = 0; w < 6; w++)
                      Row(
                        children: [
                          for (var d = 0; d < 7; d++)
                            _DayCell(
                              day: days[w * 7 + d],
                              inMonth: days[w * 7 + d].month == _month.month,
                              isToday: days[w * 7 + d] == today,
                              isSelected: days[w * 7 + d] == _selected,
                              tasks: byDay[dayKey(days[w * 7 + d])] ?? const [],
                              hasNote: noteByDay.containsKey(
                                dayKey(days[w * 7 + d]),
                              ),
                              onTap: () =>
                                  setState(() => _selected = days[w * 7 + d]),
                            ),
                        ],
                      ),
                    const SizedBox(height: 18),
                    // Selected day: date + add-task button.
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            DateFormat('EEEE, d MMMM').format(_selected),
                            style: const TextStyle(
                              fontFamily: 'Nunito',
                              fontWeight: FontWeight.w800,
                              fontSize: 20,
                            ),
                          ),
                        ),
                        KeelAddIconButton(
                          onPressed: () => showNewTaskSheet(
                            context,
                            orgId: orgId,
                            presetDueDate: _selected,
                          ),
                          tooltip: 'Add a task due this day',
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // The day note is the most prominent thing on the
                    // day (DECISIONS.md 39).
                    _DayNoteCard(
                      orgId: orgId,
                      date: _selected,
                      note: selectedNote,
                    ),
                    const SizedBox(height: 12),
                    if (selectedTasks.isEmpty)
                      EmptyState(
                        icon: Icons.event_available_outlined,
                        title: 'Nothing due this day',
                        body: 'No open tasks are due on this day.',
                        actionLabel: 'Add a task',
                        onAction: () => showNewTaskSheet(
                          context,
                          orgId: orgId,
                          presetDueDate: _selected,
                        ),
                      )
                    else
                      for (final t in selectedTasks) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: TaskCard(
                            task: t,
                            team: teamOf(t.teamId),
                            onTap: () => showTaskOverviewSheet(
                              context,
                              task: t,
                              orgId: orgId,
                              onOpenTeamPage: (team) => openTeamPage(
                                context,
                                team: team,
                                orgId: orgId,
                              ),
                            ),
                            onOpenPage: () =>
                                openTaskPage(context, task: t, orgId: orgId),
                          ),
                        ),
                        // A task's note is shown with the task on
                        // its day (DECISIONS.md 39).
                        if (t.notes.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: 10,
                              left: 4,
                              right: 4,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.notes_outlined,
                                  size: 16,
                                  color: context.muted,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    t.notes,
                                    style: TextStyle(
                                      color: context.muted,
                                      fontSize: 13,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const Center(child: Text('Could not load calendar.')),
    );
  }
}

class _DayCell extends StatelessWidget {
  final DateTime day;
  final bool inMonth;
  final bool isToday;
  final bool isSelected;
  final List<Task> tasks;
  final bool hasNote;
  final VoidCallback onTap;

  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.isSelected,
    required this.tasks,
    required this.hasNote,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final overdue = tasks.any(isOverdue);
    final dotColor = overdue ? KeelTokens.overdue : context.accent;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 52,
          padding: const EdgeInsets.only(top: 4),
          decoration: isSelected
              ? BoxDecoration(
                  color: context.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                )
              : null,
          child: Column(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: isSelected
                    ? BoxDecoration(
                        color: context.accent,
                        shape: BoxShape.circle,
                      )
                    : isToday
                    ? BoxDecoration(
                        border: Border.all(color: context.accent, width: 1.5),
                        shape: BoxShape.circle,
                      )
                    : null,
                child: Text(
                  '${day.day}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isToday || isSelected
                        ? FontWeight.w800
                        : FontWeight.w500,
                    color: isSelected
                        ? Colors.white
                        : inMonth
                        ? context.ink
                        : context.muted.withValues(alpha: 0.5),
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final _ in tasks.take(3))
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: dotColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  if (hasNote)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: context.muted.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The day note, shown most prominently on its day (DECISIONS.md 39).
/// Tapping opens the note editor sheet.
class _DayNoteCard extends StatelessWidget {
  final String orgId;
  final DateTime date;
  final DayNote? note;

  const _DayNoteCard({
    required this.orgId,
    required this.date,
    required this.note,
  });

  @override
  Widget build(BuildContext context) {
    if (note == null) {
      return KeelCard(
        onTap: () => _editDayNote(context, orgId, date, null),
        child: Row(
          children: [
            Icon(Icons.sticky_note_2_outlined, color: context.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Add a note for this day',
                style: TextStyle(color: context.muted, fontSize: 14),
              ),
            ),
            Icon(Icons.chevron_right, color: context.muted),
          ],
        ),
      );
    }
    return KeelCard(
      onTap: () => _editDayNote(context, orgId, date, note),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sticky_note_2_outlined, color: context.accent),
              const SizedBox(width: 8),
              Text(
                'Note',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: context.accent,
                ),
              ),
              const Spacer(),
              Text(
                'Edit',
                style: TextStyle(color: context.muted, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(note!.note, style: const TextStyle(fontSize: 15, height: 1.4)),
        ],
      ),
    );
  }
}

Future<void> _editDayNote(
  BuildContext context,
  String orgId,
  DateTime date,
  DayNote? existing,
) {
  return showKeelSheet<void>(
    context,
    builder: (context, c) => _DayNoteSheet(
      orgId: orgId,
      date: date,
      existing: existing,
      scrollController: c,
    ),
  );
}

class _DayNoteSheet extends ConsumerStatefulWidget {
  final String orgId;
  final DateTime date;
  final DayNote? existing;
  final ScrollController scrollController;

  const _DayNoteSheet({
    required this.orgId,
    required this.date,
    required this.existing,
    required this.scrollController,
  });

  @override
  ConsumerState<_DayNoteSheet> createState() => _DayNoteSheetState();
}

class _DayNoteSheetState extends ConsumerState<_DayNoteSheet> {
  late final TextEditingController _note;

  @override
  void initState() {
    super.initState();
    _note = TextEditingController(text: widget.existing?.note ?? '');
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ref
        .read(repositoryProvider)
        .saveDayNote(widget.orgId, dayKey(widget.date), _note.text);
    if (mounted) {
      Navigator.of(context).pop();
      showKeelSnack(context, 'Note saved');
    }
  }

  Future<void> _delete() async {
    await ref
        .read(repositoryProvider)
        .deleteDayNote(widget.orgId, dayKey(widget.date));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      title: 'Note · ${DateFormat('d MMM yyyy').format(widget.date)}',
      buttonLabel: 'Save note',
      onButton: _save,
      scrollController: widget.scrollController,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KeelTextField(
            controller: _note,
            hint: 'Write a note for this day…',
            maxLines: 5,
            autofocus: true,
          ),
          if (widget.existing != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline, size: 20),
                label: const Text('Delete note'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: KeelTokens.overdue,
                  side: const BorderSide(color: KeelTokens.overdue),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      KeelTokens.radiusButton,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
