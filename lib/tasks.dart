import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'db.dart';
import 'providers.dart';
import 'repo.dart';
import 'sheets.dart';
import 'task_card.dart';
import 'theme.dart';
import 'widgets.dart';

/// Tasks tab: large title + open count, segmented All/Open/Done,
/// filter chips (team, person, overdue), swipe delete/complete.
class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  String _segment = 'All';
  String? _teamFilter;
  String? _personFilter;

  @override
  Widget build(BuildContext context) {
    final orgIdAsync = ref.watch(activeOrgProvider);
    final scrollController = ref.watch(tabScrollControllersProvider)[1];
    final overdueOnly = ref.watch(tasksOverdueFilterProvider);

    return orgIdAsync.when(
      data: (orgId) {
        if (orgId == null) return const SizedBox.shrink();
        final tasksAsync = ref.watch(tasksProvider(orgId));
        final teamsAsync = ref.watch(teamsProvider(orgId));
        final peopleAsync = ref.watch(peopleProvider(orgId));
        final tasks = tasksAsync.value ?? const [];
        final teams = teamsAsync.value ?? const [];
        final people = peopleAsync.value ?? const [];
        final openCount = tasks.where((t) => !t.isDone).length;

        var shown = tasks;
        if (_segment == 'Open') shown = shown.where((t) => !t.isDone).toList();
        if (_segment == 'Done') shown = shown.where((t) => t.isDone).toList();
        if (overdueOnly) shown = shown.where((t) => isOverdue(t)).toList();
        if (_teamFilter != null) {
          shown = shown.where((t) => t.teamId == _teamFilter).toList();
        }

        final listWidget = _personFilter == null
            ? _TaskList(tasks: shown, teams: teams, orgId: orgId)
            : FutureBuilder<List<Task>>(
                future: ref
                    .read(repositoryProvider)
                    .getTasksForPerson(_personFilter!),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Padding(
                      padding: EdgeInsets.only(top: 32),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final ids = snap.data!.map((t) => t.id).toSet();
                  final filtered =
                      shown.where((t) => ids.contains(t.id)).toList();
                  if (filtered.isEmpty) {
                    return EmptyState(
                      icon: Icons.person_search_outlined,
                      title: 'No tasks for this person',
                      body: 'Assign a task to them and it will show up here.',
                      actionLabel: 'Add a task',
                      onAction: () => showNewTaskSheet(context, orgId: orgId),
                    );
                  }
                  return _TaskList(tasks: filtered, teams: teams, orgId: orgId);
                },
              );

        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(18, 54, 18, 130),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$openCount open',
                        style: TextStyle(color: context.muted, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text('Tasks', style: Theme.of(context).textTheme.displayLarge),
                    ],
                  ),
                ),
                KeelAddIconButton(
                  onPressed: () => showNewTaskSheet(context, orgId: orgId),
                  tooltip: 'Add a task',
                ),
              ],
            ),
            const SizedBox(height: 16),
            KeelSegmented<String>(
              options: const [
                ('All', 'All'),
                ('Open', 'Open'),
                ('Done', 'Done'),
              ],
              selected: _segment,
              onChanged: (v) => setState(() => _segment = v),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FilterChip(
                    label: 'Overdue',
                    selected: overdueOnly,
                    color: KeelTokens.overdue,
                    onTap: () => ref
                        .read(tasksOverdueFilterProvider.notifier)
                        .state = !overdueOnly,
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'All teams',
                    selected: _teamFilter == null,
                    color: context.accent,
                    onTap: () => setState(() => _teamFilter = null),
                  ),
                  for (final t in teams) ...[
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: t.name,
                      selected: _teamFilter == t.id,
                      color: KeelTokens.colorFromHex(t.colorHex),
                      onTap: () => setState(
                        () => _teamFilter = _teamFilter == t.id ? null : t.id,
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'All people',
                    selected: _personFilter == null,
                    color: context.accent,
                    onTap: () => setState(() => _personFilter = null),
                  ),
                  for (final p in people) ...[
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: p.name.split(' ').first,
                      selected: _personFilter == p.id,
                      color: context.accent,
                      onTap: () => setState(
                        () => _personFilter =
                            _personFilter == p.id ? null : p.id,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (shown.isEmpty && _personFilter == null)
              EmptyState(
                icon: overdueOnly
                    ? Icons.event_busy_outlined
                    : Icons.check_box_outlined,
                title: overdueOnly
                    ? 'Nothing overdue'
                    : _segment == 'Done'
                        ? 'No completed tasks'
                        : 'No tasks yet',
                body: overdueOnly
                    ? 'All caught up — nothing is past its due date.'
                    : 'Add your first task and it will show up here.',
                actionLabel: 'Add a task',
                onAction: () => showNewTaskSheet(context, orgId: orgId),
              )
            else
              listWidget,
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const Center(child: Text('Could not load tasks.')),
    );
  }
}

/// Person filter needs assignee data; resolved asynchronously in the
/// screen above (FutureBuilder over getTasksForPerson), so the list
/// itself stays a plain lazy column.
class _TaskList extends ConsumerWidget {
  final List<Task> tasks;
  final List<Team> teams;
  final String orgId;
  const _TaskList({required this.tasks, required this.teams, required this.orgId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        for (final t in tasks)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: DismissibleTaskCard(
              task: t,
              team: teams.where((x) => x.id == t.teamId).firstOrNull,
              onTap: () =>
                  showTaskDetailSheet(context, task: t, orgId: orgId),
            ),
          ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color : context.card,
          borderRadius: BorderRadius.circular(99),
          border: selected ? null : Border.all(color: context.line),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : context.ink,
          ),
        ),
      ),
    );
  }
}

