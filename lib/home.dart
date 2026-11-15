import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'db.dart';
import 'providers.dart';
import 'repo.dart';
import 'sheets.dart';
import 'task_card.dart';
import 'task_page.dart';
import 'teams.dart';
import 'theme.dart';
import 'widgets.dart';

/// Home dashboard: org+date header, greeting, dark progress dial,
/// 3 stat tiles, Up next, horizontal team cards, global search.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final orgIdAsync = ref.watch(activeOrgProvider);
    final scrollController = ref.watch(tabScrollControllersProvider)[0];

    return orgIdAsync.when(
      data: (orgId) {
        if (orgId == null) {
          return const Center(child: Text('No organization yet.'));
        }
        final orgsAsync = ref.watch(organizationsProvider);
        final profileAsync = ref.watch(profileProvider);
        final teamsAsync = ref.watch(teamsProvider(orgId));
        final peopleAsync = ref.watch(peopleProvider(orgId));
        final tasksAsync = ref.watch(tasksProvider(orgId));
        final org = (orgsAsync.value ?? const [])
            .where((o) => o.id == orgId)
            .firstOrNull;
        final name = profileAsync.value?.name ?? '';
        final firstName = name.split(' ').first;
        final teams = teamsAsync.value ?? const [];
        final tasks = tasksAsync.value ?? const [];
        final peopleCount = (peopleAsync.value ?? const []).length;
        final done = tasks.where((t) => t.isDone).length;
        final overdueCount = tasks.where((t) => isOverdue(t)).length;
        final dueSoonCount = tasks.where((t) => isDueSoon(t)).length;
        final pct = tasks.isEmpty ? 0.0 : done / tasks.length;

        return _HomeBody(
          scrollController: scrollController,
          org: org,
          greetingName: firstName,
          pct: pct,
          done: done,
          total: tasks.length,
          overdueCount: overdueCount,
          dueSoonCount: dueSoonCount,
          teamsCount: teams.length,
          peopleCount: peopleCount,
          teams: teams,
          orgId: orgId,
          reduceMotion: settings.reduceMotion,
          query: _query,
          onQueryChanged: (q) => setState(() => _query = q),
          searchController: _search,
          homeSeenOnce: settings.homeSeenOnce,
          onFirstPaint: () {
            if (mounted) settings.markHomeSeen();
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const Center(child: Text('Could not load your data.')),
    );
  }
}

class _HomeBody extends ConsumerWidget {
  final ScrollController scrollController;
  final Organization? org;
  final String greetingName;
  final double pct;
  final int done;
  final int total;
  final int overdueCount;
  final int dueSoonCount;
  final int teamsCount;
  final int peopleCount;
  final List<Team> teams;
  final String orgId;
  final bool reduceMotion;
  final String query;
  final ValueChanged<String> onQueryChanged;
  final TextEditingController searchController;
  final bool homeSeenOnce;
  final VoidCallback onFirstPaint;

  const _HomeBody({
    required this.scrollController,
    required this.org,
    required this.greetingName,
    required this.pct,
    required this.done,
    required this.total,
    required this.overdueCount,
    required this.dueSoonCount,
    required this.teamsCount,
    required this.peopleCount,
    required this.teams,
    required this.orgId,
    required this.reduceMotion,
    required this.query,
    required this.onQueryChanged,
    required this.searchController,
    required this.homeSeenOnce,
    required this.onFirstPaint,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateStr = DateFormat('EEE d MMM').format(DateTime.now());
    final upNextFuture = ref.read(repositoryProvider).upNext(orgId);

    final content = ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(18, 54, 18, 130),
      children: [
        // Header: org + date (tap → switcher), large greeting title.
        GestureDetector(
          onTap: () => showOrgSwitcherSheet(context),
          behavior: HitTestBehavior.opaque,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${org?.name ?? ''} · $dateStr',
                  style: TextStyle(color: context.muted, fontSize: 13),
                ),
              ),
              Icon(Icons.swap_horiz, size: 18, color: context.muted),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${greetingFor(DateTime.now())}, $greetingName',
          style: Theme.of(context).textTheme.displayLarge,
        ),
        const SizedBox(height: 16),
        // Search (global: tasks, people, teams).
        TextField(
          controller: searchController,
          onChanged: onQueryChanged,
          decoration: InputDecoration(
            hintText: 'Search tasks, people, teams',
            prefixIcon: Icon(Icons.search, color: context.muted, size: 19),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      searchController.clear();
                      onQueryChanged('');
                    },
                    tooltip: 'Clear search',
                  ),
          ),
        ),
        const SizedBox(height: 14),
        if (query.trim().isNotEmpty)
          _SearchResults(
            orgId: orgId,
            query: query,
            onClear: () {
              searchController.clear();
              onQueryChanged('');
            },
          )
        else ...[
          // Dark progress dial card.
          _DialCard(
            pct: pct,
            done: done,
            total: total,
            overdue: overdueCount,
            dueSoon: dueSoonCount,
            reduceMotion: reduceMotion,
            firstTime: !homeSeenOnce,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              StatTile(
                value: '$teamsCount',
                label: 'Teams',
                onTap: () =>
                    ref.read(tabIndexProvider.notifier).state = 2,
              ),
              const SizedBox(width: 8),
              StatTile(
                value: '$peopleCount',
                label: 'People',
                onTap: () =>
                    ref.read(tabIndexProvider.notifier).state = 3,
              ),
              const SizedBox(width: 8),
              StatTile(
                value: '$overdueCount',
                label: 'Overdue',
                valueColor: overdueCount > 0 ? KeelTokens.overdue : null,
                onTap: () {
                  ref.read(tasksOverdueFilterProvider.notifier).state = true;
                  ref.read(tabIndexProvider.notifier).state = 1;
                },
              ),
            ],
          ),
          SectionHeader(
            title: 'Up next',
            actionLabel: 'See all',
            onAction: () =>
                ref.read(tabIndexProvider.notifier).state = 1,
          ),
          FutureBuilder<List<Task>>(
            future: upNextFuture,
            builder: (context, snap) {
              final upNext = snap.data ?? const [];
              if (upNext.isEmpty) {
                return EmptyState(
                  icon: Icons.check_circle_outline,
                  title: 'Nothing urgent',
                  body: 'No open tasks right now. Add one and it will show up here.',
                  actionLabel: 'Add a task',
                  onAction: () => showNewTaskSheet(context, orgId: orgId),
                );
              }
              return Column(
                children: [
                  for (final t in upNext)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _HomeTaskCard(task: t),
                    ),
                ],
              );
            },
          ),
          SectionHeader(
            title: 'Teams',
            actionLabel: 'See all',
            onAction: () =>
                ref.read(tabIndexProvider.notifier).state = 2,
          ),
          if (teams.isEmpty)
            EmptyState(
              icon: Icons.group_outlined,
              title: 'No teams yet',
              body: 'Create your first team to group people and tasks together.',
              actionLabel: 'Create a team',
              onAction: () => showNewTeamSheet(context, orgId: orgId),
            )
          else
            SizedBox(
              height: 108,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: teams.length,
                itemBuilder: (context, i) {
                  final team = teams[i];
                  return _TeamStripCard(team: team, orgId: orgId);
                },
              ),
            ),
        ],
      ],
    );

    // First-time staggered reveal: dial, tiles and lists fade in once.
    if (!homeSeenOnce && !reduceMotion) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onFirstPaint());
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 500),
        curve: KeelTokens.easeOut,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 12),
            child: child,
          ),
        ),
        child: content,
      );
    }
    return content;
  }
}

class _DialCard extends StatelessWidget {
  final double pct;
  final int done;
  final int total;
  final int overdue;
  final int dueSoon;
  final bool reduceMotion;
  final bool firstTime;
  const _DialCard({
    required this.pct,
    required this.done,
    required this.total,
    required this.overdue,
    required this.dueSoon,
    required this.reduceMotion,
    required this.firstTime,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.dialCard,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children: [
          ProgressRing(value: pct, reduceMotion: reduceMotion),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Overall progress',
                  style: TextStyle(
                    color: context.dialInk.withValues(alpha: 0.6),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$done of $total tasks done',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    height: 1.15,
                    color: context.dialInk,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$overdue overdue · $dueSoon due soon',
                  style: TextStyle(
                    color: context.dialInk.withValues(alpha: 0.6),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeTaskCard extends ConsumerWidget {
  final Task task;
  const _HomeTaskCard({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teams = ref.watch(teamsProvider(task.orgId)).value ?? const [];
    final team = teams.where((t) => t.id == task.teamId).firstOrNull;
    return TaskCard(
      task: task,
      team: team,
      onTap: () => showTaskOverviewSheet(
        context,
        task: task,
        orgId: task.orgId,
        onOpenTeamPage: (team) =>
            openTeamPage(context, team: team, orgId: task.orgId),
      ),
      onOpenPage: () => openTaskPage(context, task: task, orgId: task.orgId),
    );
  }
}

class _TeamStripCard extends ConsumerWidget {
  final Team team;
  final String orgId;
  const _TeamStripCard({required this.team, required this.orgId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = KeelTokens.colorFromHex(team.colorHex);
    final tasks = ref.watch(tasksProvider(orgId)).value ?? const [];
    final teamTasks = tasks.where((t) => t.teamId == team.id).toList();
    final done = teamTasks.where((t) => t.isDone).length;
    final pct = teamTasks.isEmpty ? 0.0 : done / teamTasks.length;
    final mainTask = team.mainTaskId == null
        ? null
        : teamTasks.where((t) => t.id == team.mainTaskId).firstOrNull;
    return GestureDetector(
      onTap: () => showTeamOverviewSheet(
        context,
        team: team,
        orgId: orgId,
        onOpenTeamPage: () => openTeamPage(context, team: team, orgId: orgId),
      ),
      child: Container(
        width: 150,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(KeelTokens.radiusCard),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              team.name,
              style: const TextStyle(
                fontFamily: 'Nunito',
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: Colors.white,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mainTask?.title ?? 'No main task',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                ProgressBar(
                  value: pct,
                  color: Colors.white,
                  trackColor: Colors.white.withValues(alpha: 0.25),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchResults extends ConsumerWidget {
  final String orgId;
  final String query;
  final VoidCallback onClear;
  const _SearchResults({required this.orgId, required this.query, required this.onClear});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder(
      future: ref.read(repositoryProvider).search(orgId, query),
      builder: (context, snap) {
        final res = snap.data;
        if (res == null) {
          return const Padding(
            padding: EdgeInsets.only(top: 32),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (res.tasks.isEmpty && res.people.isEmpty && res.teams.isEmpty) {
          return EmptyState(
            icon: Icons.search_off_outlined,
            title: 'Nothing found',
            body: 'No tasks, people or teams match "$query".',
            actionLabel: 'Clear search',
            onAction: onClear,
          );
        }
        final teams = ref.watch(teamsProvider(orgId)).value ?? const [];
        Team? teamOf(String? id) =>
            teams.where((t) => t.id == id).firstOrNull;
        // Search results are capped at 25 per section: the Home list is
        // a plain ListView, so an uncapped 200-person match would build
        // every card eagerly. The tab lists are lazy SliverLists; search
        // is for finding, not browsing.
        const cap = 25;
        final tasksShown = res.tasks.take(cap).toList();
        final teamsShown = res.teams.take(cap).toList();
        final peopleShown = res.people.take(cap).toList();
        Widget capNote(int total) => total > cap
            ? Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'Showing the first $cap of $total — narrow your search to see more.',
                  style: TextStyle(color: context.muted, fontSize: 12),
                ),
              )
            : const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (res.tasks.isNotEmpty) ...[
              const SectionHeader(title: 'Tasks'),
              for (final t in tasksShown)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TaskCard(
                    task: t,
                    team: teamOf(t.teamId),
                    onTap: () => showTaskOverviewSheet(
                      context,
                      task: t,
                      orgId: orgId,
                      onOpenTeamPage: (team) =>
                          openTeamPage(context, team: team, orgId: orgId),
                    ),
                    onOpenPage: () =>
                        openTaskPage(context, task: t, orgId: orgId),
                  ),
                ),
              capNote(res.tasks.length),
            ],
            if (res.teams.isNotEmpty) ...[
              const SectionHeader(title: 'Teams'),
              for (final t in teamsShown)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: KeelCard(
                    onTap: () => openTeamPage(context, team: t, orgId: orgId),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 40,
                          decoration: BoxDecoration(
                            color: KeelTokens.colorFromHex(t.colorHex),
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                        ),
                        Icon(Icons.chevron_right, color: context.muted),
                      ],
                    ),
                  ),
                ),
              capNote(res.teams.length),
            ],
            if (res.people.isNotEmpty) ...[
              const SectionHeader(title: 'People'),
              for (final p in peopleShown)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: KeelCard(
                    onTap: () => showPersonOverviewSheet(
                      context,
                      person: p,
                      orgId: orgId,
                    ),
                    child: Row(
                      children: [
                        PersonAvatar(person: p, ringColor: KeelTokens.noTeam, size: 40),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                              if (p.roleTitle.isNotEmpty)
                                Text(p.roleTitle, style: TextStyle(color: context.muted, fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              capNote(res.people.length),
            ],
          ],
        );
      },
    );
  }
}
