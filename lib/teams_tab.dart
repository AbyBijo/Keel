import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'people.dart';
import 'providers.dart';
import 'teams.dart';
import 'widgets.dart';

/// The merged Teams tab (1.3.0, DECISIONS.md 35): Teams and People in
/// one tab, with a segmented control (Teams | People) just above the
/// bottom bar, defaulting to Teams. Both lists keep their own screens;
/// People keeps its live search. The Home stat tiles route here by
/// setting [teamsTabSubProvider] before switching to tab 2.
///
/// Only one sub-screen is mounted at a time, and both scroll with
/// the merged tab's controller ([2]) — so tapping the active tab
/// scrolls whichever list is showing to the top. (Two lists cannot
/// share one ScrollController while both are mounted.) The trade-off
/// is that the People search resets when switching sub-tabs.
class TeamsPeopleTab extends ConsumerWidget {
  const TeamsPeopleTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sub = ref.watch(teamsTabSubProvider);
    final scrollController = ref.watch(tabScrollControllersProvider)[2];
    // The tab bar is ~73px + the bottom safe area tall; the control
    // sits 19px above it.
    final bottomClearance = MediaQuery.of(context).padding.bottom + 92;
    return Column(
      children: [
        Expanded(
          child: sub == 'people'
              ? PeopleScreen(
                  scrollController: scrollController,
                  bottomPadding: 16,
                )
              : TeamsScreen(
                  scrollController: scrollController,
                  bottomPadding: 16,
                ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: KeelSegmented<String>(
            options: const [('teams', 'Teams'), ('people', 'People')],
            selected: sub,
            onChanged: (v) => ref.read(teamsTabSubProvider.notifier).state = v,
          ),
        ),
        SizedBox(height: bottomClearance),
      ],
    );
  }
}
