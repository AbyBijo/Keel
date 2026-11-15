import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'db.dart';
import 'people.dart';
import 'providers.dart';
import 'repo.dart';
import 'services.dart';
import 'sheets.dart';
import 'task_card.dart';
import 'theme.dart';
import 'widgets.dart';

void openTeamPage(
  BuildContext context, {
  required Team team,
  required String orgId,
}) {
  Navigator.of(context).push(
    PageRouteBuilder(
      pageBuilder: (_, _, _) => TeamPage(teamId: team.id, orgId: orgId),
      transitionsBuilder: (_, animation, _, child) {
        // Apple-style push: slide in, previous page parallaxes slightly.
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

/// Teams tab: cards with coloured bar, Lead, progress, stacked avatars,
/// arrow button. Tap card = overview sheet; tap arrow = full team page.
class TeamsScreen extends ConsumerWidget {
  const TeamsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orgIdAsync = ref.watch(activeOrgProvider);
    final scrollController = ref.watch(tabScrollControllersProvider)[2];

    return orgIdAsync.when(
      data: (orgId) {
        if (orgId == null) return const SizedBox.shrink();
        final teamsAsync = ref.watch(teamsProvider(orgId));
        final teams = teamsAsync.value ?? const [];
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
                        '${teams.length} teams · tap for overview',
                        style: TextStyle(color: context.muted, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text('Teams', style: Theme.of(context).textTheme.displayLarge),
                    ],
                  ),
                ),
                KeelAddIconButton(
                  onPressed: () => showNewTeamSheet(context, orgId: orgId),
                  tooltip: 'Add a team',
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (teams.isEmpty)
              EmptyState(
                icon: Icons.group_outlined,
                title: 'No teams yet',
                body: 'Create your first team to group people and tasks together.',
                actionLabel: 'Create a team',
                onAction: () => showNewTeamSheet(context, orgId: orgId),
              )
            else
              for (final team in teams)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _TeamCard(team: team, orgId: orgId),
                ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const Center(child: Text('Could not load teams.')),
    );
  }
}

class _TeamCard extends ConsumerWidget {
  final Team team;
  final String orgId;
  const _TeamCard({required this.team, required this.orgId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = KeelTokens.colorFromHex(team.colorHex);
    final membersAsync = ref.watch(teamMembersProvider(team.id));
    final tasks = ref.watch(tasksProvider(orgId)).value ?? const [];
    final teamTasks = tasks.where((t) => t.teamId == team.id).toList();
    final done = teamTasks.where((t) => t.isDone).length;
    final pct = teamTasks.isEmpty ? 0.0 : done / teamTasks.length;
    final members = membersAsync.value ?? const [];

    return KeelCard(
      onTap: () => showTeamOverviewSheet(
        context,
        team: team,
        orgId: orgId,
        onOpenTeamPage: () => openTeamPage(context, team: team, orgId: orgId),
      ),
      semanticLabel: 'Team ${team.name}',
      child: Row(
        children: [
          Container(
            width: 6,
            height: 64,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(9),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  team.name,
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontWeight: FontWeight.w800,
                    fontSize: 19,
                  ),
                ),
                const SizedBox(height: 2),
                FutureBuilder<Person?>(
                  future: ref.read(repositoryProvider).getPerson(team.leaderPersonId),
                  builder: (context, snap) => Text(
                    'Lead: ${snap.data?.name ?? '…'}',
                    style: TextStyle(color: context.muted, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 8),
                ProgressBar(value: pct, color: color),
              ],
            ),
          ),
          const SizedBox(width: 10),
          AvatarStack(
            members: members
                .map((p) => (person: p, color: color))
                .toList(),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => openTeamPage(context, team: team, orgId: orgId),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: KeelTokens.tint14(color, context.card),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.chevron_right, color: color, size: 24),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full team page: coloured hero, stats, Leader, People, Tasks,
/// edit/delete in the top-right menu.
class TeamPage extends ConsumerWidget {
  final String teamId;
  final String orgId;
  const TeamPage({super.key, required this.teamId, required this.orgId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teamAsync = ref.watch(teamsProvider(orgId));
    final team = (teamAsync.value ?? const [])
        .where((t) => t.id == teamId)
        .firstOrNull;
    if (team == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Team')),
        body: const Center(child: Text('This team no longer exists.')),
      );
    }
    final color = KeelTokens.colorFromHex(team.colorHex);
    final membersAsync = ref.watch(teamMembersProvider(teamId));
    final members = membersAsync.value ?? const [];
    final tasks = ref.watch(tasksProvider(orgId)).value ?? const [];
    final teamTasks = tasks.where((t) => t.teamId == teamId).toList();
    final done = teamTasks.where((t) => t.isDone).length;
    final pct = teamTasks.isEmpty ? 0.0 : done / teamTasks.length;
    final mainTask = team.mainTaskId == null
        ? null
        : teamTasks.where((t) => t.id == team.mainTaskId).firstOrNull;

    return Scaffold(
      backgroundColor: context.bg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 190,
            pinned: false,
            backgroundColor: color,
            leading: IconButton(
              icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
              onPressed: () => Navigator.of(context).pop(),
              tooltip: 'Back to Teams',
            ),
            actions: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz, color: Colors.white),
                tooltip: 'Team options',
                onSelected: (value) async {
                  if (value == 'edit') {
                    await _editTeam(context, ref, team, orgId);
                  } else if (value == 'delete') {
                    await _deleteTeam(context, ref, team);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit team')),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      'Delete team',
                      style: TextStyle(color: KeelTokens.overdue),
                    ),
                  ),
                ],
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                color: color,
                padding: const EdgeInsets.fromLTRB(18, 64, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      team.name,
                      style: const TextStyle(
                        fontFamily: 'Nunito',
                        fontWeight: FontWeight.w800,
                        fontSize: 32,
                        height: 1.05,
                        letterSpacing: -0.8,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Main task · ${mainTask?.title ?? 'None set'}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ProgressBar(
                      value: pct,
                      color: Colors.white,
                      trackColor: Colors.white.withValues(alpha: 0.25),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 40),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Row(
                  children: [
                    StatTile(value: '${members.length}', label: 'People'),
                    const SizedBox(width: 8),
                    StatTile(value: '${teamTasks.length}', label: 'Tasks'),
                    const SizedBox(width: 8),
                    StatTile(value: '${(pct * 100).round()}%', label: 'Done'),
                  ],
                ),
                const SectionHeader(title: 'Leader'),
                FutureBuilder<Person?>(
                  future: ref.read(repositoryProvider).getPerson(team.leaderPersonId),
                  builder: (context, snap) {
                    final leader = snap.data;
                    if (leader == null) {
                      return const KeelCard(child: Text('Loading leader…'));
                    }
                    return KeelCard(
                      onTap: () => openPersonPage(context, person: leader, orgId: orgId),
                      child: Row(
                        children: [
                          PersonAvatar(person: leader, ringColor: color, size: 48),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(leader.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                                if (leader.roleTitle.isNotEmpty)
                                  Text(leader.roleTitle, style: TextStyle(color: context.muted, fontSize: 13)),
                              ],
                            ),
                          ),
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: KeelTokens.tint14(color, context.card),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.flag_outlined, color: color, size: 20),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                Row(
                  children: [
                    const Expanded(child: SectionHeader(title: 'People')),
                    TextButton.icon(
                      onPressed: () async {
                        final all = await ref.read(repositoryProvider).getPeople(orgId);
                        if (!context.mounted) return;
                        final ids = await pickPeople(
                          context,
                          orgId: orgId,
                          selected: members.map((p) => p.id).toList(),
                          title: 'Team members',
                        );
                        if (!context.mounted) return;
                        if (ids == null) return;
                        final repo = ref.read(repositoryProvider);
                        final old = members.map((p) => p.id).toSet();
                        for (final id in ids) {
                          if (!old.contains(id)) {
                            await repo.addTeamMember(team.id, id);
                          }
                        }
                        for (final id in old) {
                          if (!ids.contains(id)) {
                            if (!context.mounted) return;
                            await _removeMemberWithLeaderCheck(
                              context,
                              ref,
                              team,
                              id,
                              all,
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add / remove'),
                      style: TextButton.styleFrom(foregroundColor: context.accent),
                    ),
                  ],
                ),
                if (members.isEmpty)
                  EmptyState(
                    icon: Icons.person_add_outlined,
                    title: 'No members yet',
                    body: 'Add people to this team.',
                    actionLabel: 'Add members',
                    onAction: () async {
                      final ids = await pickPeople(
                        context,
                        orgId: orgId,
                        selected: const [],
                        title: 'Team members',
                      );
                      if (ids == null) return;
                      final repo = ref.read(repositoryProvider);
                      for (final id in ids) {
                        await repo.addTeamMember(team.id, id);
                      }
                    },
                  )
                else
                  KeelCard(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Column(
                      children: [
                        for (final m in members)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                PersonAvatar(person: m, ringColor: color, size: 38),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => openPersonPage(context, person: m, orgId: orgId),
                                    child: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                                  ),
                                ),
                                Text(
                                  m.roleTitle,
                                  style: TextStyle(color: context.muted, fontSize: 13),
                                ),
                                const SizedBox(width: 8),
                                if (m.id != team.leaderPersonId)
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                                    color: context.muted,
                                    tooltip: 'Remove ${m.name} from team',
                                    onPressed: () async {
                                      final all = await ref.read(repositoryProvider).getPeople(orgId);
                                      if (!context.mounted) return;
                                      await _removeMemberWithLeaderCheck(context, ref, team, m.id, all);
                                    },
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    const Expanded(child: SectionHeader(title: 'Tasks')),
                    TextButton.icon(
                      onPressed: () =>
                          showNewTaskSheet(context, orgId: orgId, presetTeamId: team.id),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add task'),
                      style: TextButton.styleFrom(foregroundColor: context.accent),
                    ),
                  ],
                ),
                if (teamTasks.isEmpty)
                  EmptyState(
                    icon: Icons.check_box_outlined,
                    title: 'No tasks for this team',
                    body: 'Add a task here and it will belong to ${team.name}.',
                    actionLabel: 'Add a task',
                    onAction: () =>
                        showNewTaskSheet(context, orgId: orgId, presetTeamId: team.id),
                  )
                else
                  for (final t in teamTasks)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Stack(
                        children: [
                          TaskCard(
                            task: t,
                            team: team,
                            onTap: () => showTaskDetailSheet(context, task: t, orgId: orgId),
                          ),
                          Positioned(
                            right: 12,
                            bottom: 12,
                            child: GestureDetector(
                              onTap: () async {
                                final repo = ref.read(repositoryProvider);
                                if (team.mainTaskId == t.id) {
                                  await repo.setMainTask(team.id, null);
                                  if (context.mounted) {
                                    showKeelSnack(context, 'Main task cleared');
                                  }
                                } else {
                                  await repo.setMainTask(team.id, t.id);
                                  if (context.mounted) {
                                    showKeelSnack(context, 'Main task set: ${t.title}');
                                  }
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                                decoration: BoxDecoration(
                                  color: team.mainTaskId == t.id
                                      ? color
                                      : KeelTokens.tint14(color, context.card),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.flag_outlined,
                                      size: 13,
                                      color: team.mainTaskId == t.id ? Colors.white : color,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      team.mainTaskId == t.id ? 'Main task' : 'Set as main',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: team.mainTaskId == t.id ? Colors.white : color,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _removeMemberWithLeaderCheck(
    BuildContext context,
    WidgetRef ref,
    Team team,
    String personId,
    List<Person> all,
  ) async {
    final repo = ref.read(repositoryProvider);
    try {
      await repo.removeTeamMember(team.id, personId);
    } on LeaderRemovalNeedsReplacement {
      // Rule 4: the leader is leaving — pick a new leader first.
      final candidates =
          all.where((p) => p.id != personId).toList();
      if (!context.mounted) return;
      final replacement = await pickLeader(
        context,
        orgId: orgId,
        candidates: candidates,
        title: 'Pick a new leader',
      );
      if (replacement != null) {
        await repo.removeTeamMember(
          team.id,
          personId,
          newLeaderId: replacement,
        );
      }
    }
  }

  Future<void> _editTeam(
    BuildContext context,
    WidgetRef ref,
    Team team,
    String orgId,
  ) async {
    final name = TextEditingController(text: team.name);
    var colorHex = team.colorHex;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Edit team'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(hintText: 'Team name'),
                ),
                const SizedBox(height: 16),
                ColorPickerField(
                  valueHex: colorHex,
                  onChanged: (v) => setState(() => colorHex = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved == true && name.text.trim().isNotEmpty) {
      await ref.read(repositoryProvider).updateTeam(
            team.id,
            name: name.text,
            colorHex: colorHex,
          );
    }
  }

  Future<void> _deleteTeam(
    BuildContext context,
    WidgetRef ref,
    Team team,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${team.name}?'),
        content: const Text(
          'The team will be deleted, but its people and tasks stay — tasks will simply have no team.',
        ),
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
    final snap = await repo.deleteTeam(team.id);
    if (context.mounted) {
      Navigator.of(context).pop();
      showUndoSnack(
        context,
        label: 'Team deleted',
        onUndo: () => repo.restoreSnapshot(snap),
      );
    }
  }
}
