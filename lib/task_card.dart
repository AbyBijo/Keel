import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'db.dart';
import 'providers.dart';
import 'repo.dart';
import 'services.dart';
import 'theme.dart';
import 'widgets.dart';

/// First-team colour for a person (rule: avatar ring uses the FIRST team's
/// colour; no team = neutral grey).
Color firstTeamColor(List<Team> teams) =>
    teams.isEmpty ? KeelTokens.noTeam : KeelTokens.colorFromHex(teams.first.colorHex);

/// One task card, used on Home ("Up next"), Tasks, the team page and the
/// person card. Checkbox, due label, team chip, stacked avatars and the
/// sub-todo checklist underneath — all live from the DB streams.
///
/// Tap the card (except the arrow) opens the task overview sheet;
/// [onOpenPage] is the arrow at the right — it opens the full task page.
class TaskCard extends ConsumerStatefulWidget {
  final Task task;
  final Team? team;
  final VoidCallback onTap;
  final VoidCallback onOpenPage;
  final bool showSubTodos;

  const TaskCard({
    super.key,
    required this.task,
    required this.team,
    required this.onTap,
    required this.onOpenPage,
    this.showSubTodos = true,
  });

  @override
  ConsumerState<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends ConsumerState<TaskCard> {
  bool _promptDismissed = false;

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final assigneesAsync = ref.watch(taskAssigneesProvider(task.id));
    final subsAsync = ref.watch(subTodosProvider(task.id));
    final overdue = isOverdue(task);
    final dueSoon = isDueSoon(task);
    final dueText = dueLabel(task.dueDate, isDone: task.isDone);

    final teamColor = widget.team == null
        ? KeelTokens.noTeam
        : KeelTokens.colorFromHex(widget.team!.colorHex);

    return KeelCard(
      onTap: widget.onTap,
      semanticLabel: 'Task: ${task.title}',
      child: Opacity(
        opacity: task.isDone ? 0.62 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KeelCheckbox(
                  value: task.isDone,
                  semanticLabel: task.isDone
                      ? 'Mark "${task.title}" not done'
                      : 'Mark "${task.title}" done',
                  onChanged: (done) async {
                    await ref
                        .read(repositoryProvider)
                        .setTaskDone(task.id, done);
                  },
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedDefaultTextStyle(
                        duration: KeelTokens.fade,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: context.ink,
                          decoration: task.isDone
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                          decorationColor: context.muted,
                        ),
                        child: Text(task.title, maxLines: 2),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          if (dueText.isNotEmpty)
                            Text(
                              dueText,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: overdue
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                                color: overdue
                                    ? KeelTokens.overdue
                                    : dueSoon
                                        ? KeelTokens.colorFromHex('#B7791F')
                                        : context.muted,
                              ),
                            ),
                          if (dueText.isNotEmpty && widget.team != null)
                            const SizedBox(width: 8),
                          if (widget.team != null)
                            KeelChip(
                              label: widget.team!.name,
                              color: teamColor,
                            ),
                          if (task.priority != 'none') ...[
                            const SizedBox(width: 6),
                            _PriorityTag(priority: task.priority),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                assigneesAsync.when(
                  data: (people) => _AssigneeAvatars(people: people),
                  loading: () => const SizedBox(width: 28, height: 28),
                  error: (_, _) => const SizedBox.shrink(),
                ),
                const SizedBox(width: 8),
                // Arrow: opens the full task page. The card tap (handled
                // by KeelCard) opens the overview sheet instead.
                Semantics(
                  button: true,
                  label: 'Open task page for "${task.title}"',
                  child: GestureDetector(
                    onTap: widget.onOpenPage,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: KeelTokens.tint14(context.accent, context.card),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.chevron_right,
                        color: context.accent,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (widget.showSubTodos)
              subsAsync.when(
                data: (subs) {
                  if (subs.isEmpty) return const SizedBox.shrink();
                  final allDone =
                      subs.every((s) => s.isDone) && !task.isDone;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 10),
                      Container(height: 1, color: context.line),
                      const SizedBox(height: 4),
                      ...subs.map(
                        (s) => _SubTodoRow(
                          sub: s,
                          onToggle: (done) async {
                            final res = await ref
                                .read(repositoryProvider)
                                .toggleSubTodo(s.id, done);
                            if (res.allDone && mounted) {
                              setState(() => _promptDismissed = false);
                            }
                          },
                        ),
                      ),
                      // Rule 7: inline prompt (not a modal) when all
                      // sub-todos are done.
                      if (allDone && !_promptDismissed)
                        _CompletePrompt(
                          onComplete: () async {
                            await ref
                                .read(repositoryProvider)
                                .setTaskDone(task.id, true);
                          },
                          onDismiss: () =>
                              setState(() => _promptDismissed = true),
                        ),
                    ],
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
              ),
          ],
        ),
      ),
    );
  }
}

class _PriorityTag extends StatelessWidget {
  final String priority;
  const _PriorityTag({required this.priority});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (priority) {
      'high' => ('High', KeelTokens.overdue),
      'medium' => ('Medium', KeelTokens.colorFromHex('#B7791F')),
      'low' => ('Low', KeelTokens.success),
      _ => ('', context.muted),
    };
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _AssigneeAvatars extends ConsumerWidget {
  final List<Person> people;
  const _AssigneeAvatars({required this.people});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (people.isEmpty) return const SizedBox.shrink();
    final entries = people.map((p) {
      final teams = ref.watch(personTeamsProvider(p.id)).value ?? const [];
      return (person: p, color: firstTeamColor(teams));
    }).toList();
    return AvatarStack(members: entries);
  }
}

class _SubTodoRow extends StatelessWidget {
  final SubTodo sub;
  final ValueChanged<bool> onToggle;
  const _SubTodoRow({required this.sub, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          KeelCheckbox(
            value: sub.isDone,
            size: 20,
            semanticLabel: sub.isDone
                ? 'Reopen sub-task "${sub.title}"'
                : 'Complete sub-task "${sub.title}"',
            onChanged: onToggle,
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Text(
              sub.title,
              style: TextStyle(
                fontSize: 14,
                color: sub.isDone ? context.muted : context.ink,
                decoration: sub.isDone
                    ? TextDecoration.lineThrough
                    : TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompletePrompt extends StatelessWidget {
  final VoidCallback onComplete;
  final VoidCallback onDismiss;
  const _CompletePrompt({required this.onComplete, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: KeelTokens.tint14(KeelTokens.success, context.card),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, size: 20, color: KeelTokens.success),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'All sub-tasks done — mark the task complete?',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: onComplete,
            style: TextButton.styleFrom(
              foregroundColor: KeelTokens.success,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(48, 36),
            ),
            child: const Text('Complete'),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(Icons.close, size: 18),
            color: context.muted,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

/// Dismissible wrapper: swipe left = delete (with Undo), right = complete.
class DismissibleTaskCard extends ConsumerWidget {
  final Task task;
  final Team? team;
  final VoidCallback onTap;
  final VoidCallback onOpenPage;

  const DismissibleTaskCard({
    super.key,
    required this.task,
    required this.team,
    required this.onTap,
    required this.onOpenPage,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: ValueKey('task-${task.id}'),
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        decoration: BoxDecoration(
          color: KeelTokens.success,
          borderRadius: BorderRadius.circular(KeelTokens.radiusCard),
        ),
        child: const Icon(Icons.check, color: Colors.white),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: KeelTokens.overdue,
          borderRadius: BorderRadius.circular(KeelTokens.radiusCard),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        final repo = ref.read(repositoryProvider);
        if (direction == DismissDirection.startToEnd) {
          await repo.setTaskDone(task.id, !task.isDone);
          return false;
        }
        return true;
      },
      onDismissed: (_) async {
        final repo = ref.read(repositoryProvider);
        final snap = await repo.deleteTask(task.id);
        if (context.mounted) {
          showUndoSnack(
            context,
            label: 'Task deleted',
            onUndo: () => repo.restoreSnapshot(snap),
          );
        }
      },
      child: TaskCard(
        task: task,
        team: team,
        onTap: onTap,
        onOpenPage: onOpenPage,
      ),
    );
  }
}
