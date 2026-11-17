import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'calendar.dart';
import 'haptics.dart';
import 'home.dart';
import 'providers.dart';
import 'services.dart';
import 'settings.dart';
import 'sheets.dart';
import 'tasks.dart';
import 'teams_tab.dart';
import 'theme.dart';

/// Root after onboarding: 5 tabs (Home, Tasks, Teams, Calendar,
/// Settings) + frosted tab bar + floating Add button.
class Shell extends ConsumerStatefulWidget {
  const Shell({super.key});

  @override
  ConsumerState<Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<Shell> {
  bool _fabOpen = false;
  AppLifecycleListener? _lifecycleListener;
  Timer? _delayedSync;

  @override
  void initState() {
    super.initState();
    // Notifications are reconciled whenever the app is opened: the
    // digest gets fresh counts, and per-task reminders are
    // re-derived from the current tasks (1.3.0). The plugin
    // initialises after runApp in main(), so the first sync is
    // delayed a little to let it land; later foregroundings sync
    // on resume. The timer is cancelled on dispose so a disposed
    // shell never fires a sync (and never leaves a pending timer).
    _delayedSync = Timer(const Duration(seconds: 2), () {
      if (mounted) unawaited(NotificationService.syncForRef(ref));
    });
    _lifecycleListener = AppLifecycleListener(
      onResume: () => unawaited(NotificationService.syncForRef(ref)),
    );
  }

  @override
  void dispose() {
    _delayedSync?.cancel();
    _lifecycleListener?.dispose();
    super.dispose();
  }

  void _onTabTap(int index) {
    final current = ref.read(tabIndexProvider);
    if (current == index) {
      final controllers = ref.read(tabScrollControllersProvider);
      final c = controllers[index];
      if (c.hasClients) {
        c.animateTo(0, duration: KeelTokens.spring, curve: KeelTokens.easeOut);
      }
      return;
    }
    KeelHaptics.selection(ref);
    setState(() => _fabOpen = false);
    ref.read(tabIndexProvider.notifier).state = index;
  }

  @override
  Widget build(BuildContext context) {
    final tabIndex = ref.watch(tabIndexProvider);
    final activeOrgAsync = ref.watch(activeOrgProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_fabOpen) {
          setState(() => _fabOpen = false);
          return;
        }
        if (tabIndex != 0) {
          ref.read(tabIndexProvider.notifier).state = 0;
          return;
        }
        // Home tab, nothing open: exit the app.
        SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: context.bg,
        body: Stack(
          children: [
            IndexedStack(
              index: tabIndex,
              children: const [
                HomeScreen(),
                TasksScreen(),
                TeamsPeopleTab(),
                CalendarScreen(),
                SettingsScreen(),
              ],
            ),
            if (_fabOpen)
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => setState(() => _fabOpen = false),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                    child: Container(color: context.ink.withValues(alpha: 0.4)),
                  ),
                ),
              ),
            if (tabIndex == 0 && activeOrgAsync.value != null)
              _AddButton(
                open: _fabOpen,
                onToggle: () => setState(() => _fabOpen = !_fabOpen),
                onPick: (kind) async {
                  final orgId = activeOrgAsync.value!;
                  setState(() => _fabOpen = false);
                  if (kind == 'task') {
                    await showNewTaskSheet(context, orgId: orgId);
                  } else if (kind == 'person') {
                    await showNewPersonSheet(context, orgId: orgId);
                  } else {
                    await showNewTeamSheet(context, orgId: orgId);
                  }
                },
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _TabBar(current: tabIndex, onTap: _onTabTap),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  final int current;
  final ValueChanged<int> onTap;
  const _TabBar({required this.current, required this.onTap});

  static const _items = [
    ('Home', Icons.home_outlined, Icons.home),
    ('Tasks', Icons.check_box_outlined, Icons.check_box),
    ('Teams', Icons.group_outlined, Icons.group),
    ('Calendar', Icons.calendar_month_outlined, Icons.calendar_month),
    ('Settings', Icons.tune_outlined, Icons.tune),
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return ClipRRect(
      child: BackdropFilter(
        // 1.3.0: the blur was sigma 22 — heavy enough to drop frames
        // and make a scroll feel dead on weaker phones. Sigma 8 keeps
        // the frosted look at a fraction of the cost.
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: EdgeInsets.only(top: 8, bottom: bottom + 10),
          decoration: BoxDecoration(
            color: context.card.withValues(alpha: 0.82),
            border: Border(top: BorderSide(color: context.line)),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final itemW = constraints.maxWidth / _items.length;
              return Stack(
                children: [
                  AnimatedPositioned(
                    duration: KeelTokens.spring,
                    curve: KeelTokens.easeOut,
                    left: current * itemW + (itemW - 52) / 2,
                    top: 0,
                    width: 52,
                    height: 30,
                    child: Container(
                      decoration: BoxDecoration(
                        color: context.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < _items.length; i++)
                        Expanded(
                          child: GestureDetector(
                            onTap: () => onTap(i),
                            behavior: HitTestBehavior.opaque,
                            child: Semantics(
                              button: true,
                              selected: current == i,
                              label: _items[i].$1,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    height: 30,
                                    child: Center(
                                      child: AnimatedScale(
                                        scale: current == i ? 1.12 : 1.0,
                                        duration: KeelTokens.fade,
                                        child: Icon(
                                          current == i
                                              ? _items[i].$3
                                              : _items[i].$2,
                                          size: 24,
                                          color: current == i
                                              ? context.accent
                                              : context.muted,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _items[i].$1,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                      color: current == i
                                          ? context.accent
                                          : context.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Floating Add button: rotates 45°, squircle morphs to a circle, three
/// labelled pills rise above it with 40ms stagger.
class _AddButton extends ConsumerStatefulWidget {
  final bool open;
  final VoidCallback onToggle;
  final ValueChanged<String> onPick;
  const _AddButton({
    required this.open,
    required this.onToggle,
    required this.onPick,
  });

  @override
  ConsumerState<_AddButton> createState() => _AddButtonState();
}

class _AddButtonState extends ConsumerState<_AddButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
  }

  @override
  void didUpdateWidget(_AddButton old) {
    super.didUpdateWidget(old);
    if (widget.open) {
      _c.forward();
    } else {
      _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const pills = [
      ('task', 'Task', Icons.check_box_outlined),
      ('person', 'Person', Icons.person_outline),
      ('team', 'Team', Icons.group_outlined),
    ];
    return Positioned(
      right: 20,
      bottom: 104,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < pills.length; i++)
            AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final t = Interval(
                  i * 0.13,
                  0.4 + i * 0.13,
                  curve: Curves.easeOut,
                ).transform(_c.value);
                return Opacity(
                  opacity: t,
                  child: Transform.translate(
                    offset: Offset(0, (1 - t) * 14),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GestureDetector(
                        onTap: _c.value > 0.9
                            ? () => widget.onPick(pills[i].$1)
                            : null,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(10, 9, 16, 9),
                          decoration: BoxDecoration(
                            color: context.card,
                            borderRadius: BorderRadius.circular(99),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.18),
                                blurRadius: 24,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: context.accent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: Icon(
                                  pills[i].$3,
                                  size: 19,
                                  color: context.accent,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                pills[i].$2,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          GestureDetector(
            onTap: () {
              KeelHaptics.impact(ref);
              widget.onToggle();
            },
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                return Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: context.accent,
                    borderRadius: BorderRadius.circular(
                      21 + (30 - 21) * _c.value,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: context.accent.withValues(alpha: 0.4),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Transform.rotate(
                    angle: _c.value * 0.785398, // 45°
                    child: const Icon(Icons.add, color: Colors.white, size: 30),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
