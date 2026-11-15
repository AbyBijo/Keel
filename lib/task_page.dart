import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'db.dart';
import 'providers.dart';
import 'repo.dart';
import 'services.dart';
import 'sheets.dart';
import 'teams.dart';
import 'theme.dart';
import 'widgets.dart';

/// Full task page: the arrow on a task tile opens this.
/// Team chip and assignees navigate onward; edit/delete live in the
/// top-right menu. The overview sheet is the quick view; this is the
/// full one.
void openTaskPage(
  BuildContext context, {
  required Task task,
  required String orgId,
}) {
  Navigator.of(context).push(
    PageRouteBuilder(
      pageBuilder: (_, _, _) => TaskPage(taskId: task.id, orgId: orgId),
      transitionsBuilder: (_, animation, _, child) {
        final slide = Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: animation, curve: KeelTokens.easeOut),
        );
        return SlideTransition(position: slide, child: child);
      },
      transitionDuration: KeelTokens.spring,
    ),
  );
}

class TaskPage extends ConsumerWidget {
  final String taskId;
  final String orgId;
  const TaskPage({super.key, required this.taskId, required this.orgId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taskAsync = ref.watch(taskProvider(taskId));
    final task = taskAsync.value;
    if (task == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Task')),
        body: const Center(child: Text('This task no longer exists.')),
      );
    }
    final repo = ref.read(repositoryProvider);
    final teams = ref.watch(teamsProvider(orgId)).value ?? const [];
    final team = teams.where((t) => t.id == task.teamId).firstOrNull;
    final assigneesAsync = ref.watch(taskAssigneesProvider(task.id));
    final subsAsync = ref.watch(subTodosProvider(task.id));
    final overdue = isOverdue(task);
    final dueSoon = isDueSoon(task);

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.chevron_left, color: context.accent, size: 28),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Back to Tasks',
        ),
        title: Text('Tasks', style: TextStyle(color: context.accent, fontSize: 17)),
        centerTitle: false,
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_horiz, color: context.ink),
            tooltip: 'Task options',
            onSelected: (value) async {
              if (value == 'edit') {
                await showTaskDetailSheet(context, task: task, orgId: orgId);
              } else if (value == 'delete') {
                await _deleteTask(context, ref, task);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit task')),
              PopupMenuItem(
                value: 'delete',
                child: Text(
                  'Delete task',
                  style: TextStyle(color: KeelTokens.overdue),
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KeelCheckbox(
                value: task.isDone,
                semanticLabel: task.isDone
                    ? 'Mark "${task.title}" not done'
                    : 'Mark "${task.title}" done',
                onChanged: (done) => repo.setTaskDone(task.id, done),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  task.title,
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontWeight: FontWeight.w800,
                    fontSize: 24,
                    height: 1.1,
                    letterSpacing: -0.6,
                    color: context.ink,
                    decoration:
                        task.isDone ? TextDecoration.lineThrough : null,
                    decorationColor: context.muted,
                  ),
                ),
              ),
            ],
          ),
          if (task.notes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              task.notes,
              style: TextStyle(color: context.muted, fontSize: 15, height: 1.4),
            ),
          ],
          const SizedBox(height: 16),
          // Due date + priority + team.
          KeelCard(
            child: Column(
              children: [
                _DetailRow(
                  icon: Icons.event_outlined,
                  label: 'Due date',
                  value: task.dueDate == null
                      ? 'No due date'
                      : '${dueLabel(task.dueDate, isDone: task.isDone)} · '
                          '${task.dueDate!.day}/${task.dueDate!.month}/${task.dueDate!.year}',
                  valueColor: overdue
                      ? KeelTokens.overdue
                      : dueSoon
                          ? KeelTokens.colorFromHex('#B7791F')
                          : null,
                ),
                _DetailRow(
                  icon: Icons.flag_outlined,
                  label: 'Priority',
                  value: task.priority == 'none'
                      ? 'None'
                      : task.priority[0].toUpperCase() +
                          task.priority.substring(1),
                ),
                if (team != null)
                  _DetailRow(
                    icon: Icons.group_outlined,
                    label: 'Team',
                    value: team.name,
                    valueColor: KeelTokens.colorFromHex(team.colorHex),
                    onTap: () => openTeamPage(
                      context,
                      team: team,
                      orgId: orgId,
                    ),
                  )
                else
                  const _DetailRow(
                    icon: Icons.group_outlined,
                    label: 'Team',
                    value: 'No team',
                  ),
                if (task.isDone && task.completedAt != null)
                  _DetailRow(
                    icon: Icons.check_circle_outline,
                    label: 'Completed',
                    value:
                        '${task.completedAt!.day}/${task.completedAt!.month}/${task.completedAt!.year}',
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Sub-tasks',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: context.muted,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => _addSubTodo(context, ref, task.id),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add sub-task'),
                style: TextButton.styleFrom(foregroundColor: context.accent),
              ),
            ],
          ),
          const SizedBox(height: 8),
          subsAsync.when(
            data: (subs) => subs.isEmpty
                ? KeelCard(
                    child: Text(
                      'No sub-tasks yet.',
                      style: TextStyle(color: context.muted, fontSize: 14),
                    ),
                  )
                : KeelCard(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    child: Column(
                      children: [
                        for (final s in subs)
                          Row(
                            children: [
                              KeelCheckbox(
                                value: s.isDone,
                                size: 20,
                                onChanged: (done) =>
                                    repo.toggleSubTodo(s.id, done),
                              ),
                              Expanded(
                                child: Text(
                                  s.title,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: s.isDone
                                        ? context.muted
                                        : context.ink,
                                    decoration: s.isDone
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                color: context.muted,
                                onPressed: () => repo.deleteSubTodo(s.id),
                                tooltip: 'Delete sub-task',
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 16),
          Text(
            'Assigned to',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: context.muted,
            ),
          ),
          const SizedBox(height: 8),
          assigneesAsync.when(
            data: (people) => people.isEmpty
                ? KeelCard(
                    child: Text(
                      'Nobody assigned yet — edit the task to assign people.',
                      style: TextStyle(color: context.muted, fontSize: 14),
                    ),
                  )
                : KeelCard(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    child: Column(
                      children: [
                        for (final p in people)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                PersonAvatar(
                                  person: p,
                                  ringColor: KeelTokens.noTeam,
                                  size: 38,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => showPersonOverviewSheet(
                                      context,
                                      person: p,
                                      orgId: orgId,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          p.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 16,
                                          ),
                                        ),
                                        if (p.roleTitle.isNotEmpty)
                                          Text(
                                            p.roleTitle,
                                            style: TextStyle(
                                              color: context.muted,
                                              fontSize: 13,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Future<void> _addSubTodo(
    BuildContext context,
    WidgetRef ref,
    String taskId,
  ) async {
    final controller = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add sub-task'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Sub-task'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (saved == true && controller.text.trim().isNotEmpty) {
      await ref.read(repositoryProvider).addSubTodo(taskId, controller.text);
    }
    controller.dispose();
  }

  Future<void> _deleteTask(
    BuildContext context,
    WidgetRef ref,
    Task task,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${task.title}"?'),
        content: const Text('You can undo this for 6 seconds.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: KeelTokens.overdue),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final repo = ref.read(repositoryProvider);
    final snap = await repo.deleteTask(task.id);
    if (context.mounted) {
      Navigator.of(context).pop();
      showUndoSnack(
        context,
        label: 'Task deleted',
        onUndo: () => repo.restoreSnapshot(snap),
      );
    }
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final VoidCallback? onTap;
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, size: 19, color: context.muted),
          const SizedBox(width: 12),
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: TextStyle(color: context.muted, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: valueColor ?? context.ink,
              ),
            ),
          ),
          if (onTap != null)
            Icon(Icons.chevron_right, color: context.muted, size: 20),
        ],
      ),
    );
    if (onTap == null) return row;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: row,
    );
  }
}
