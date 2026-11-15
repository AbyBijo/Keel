import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'haptics.dart';
import 'links.dart';
import 'providers.dart';
import 'repo.dart';
import 'seed.dart';
import 'services.dart';
import 'sheets.dart';
import 'theme.dart';
import 'widgets.dart';

/// Settings tab — grouped lists in the order of the master prompt:
/// Profile + Organizations, Personalization, Appearance, Utilities,
/// Backup, About (last, separated).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final profileAsync = ref.watch(profileProvider);
    final orgsAsync = ref.watch(organizationsProvider);
    final activeOrgAsync = ref.watch(activeOrgProvider);
    final scrollController = ref.watch(tabScrollControllersProvider)[4];
    final profile = profileAsync.value;
    final orgs = orgsAsync.value ?? const [];
    final activeOrgId = activeOrgAsync.value;
    final repo = ref.read(repositoryProvider);

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(18, 54, 18, 130),
      children: [
        Text('Settings', style: Theme.of(context).textTheme.displayLarge),
        const SizedBox(height: 16),
        _Group(
          children: [
            _SettingsRow(
              icon: Icons.person_outline,
              iconColor: context.accent,
              label: profile?.name ?? 'Your profile',
              detail: profile?.role.isEmpty ?? true
                  ? 'Tap to set your name and role'
                  : profile!.role,
              onTap: () => _editProfile(context, ref),
            ),
            _SettingsRow(
              icon: Icons.business_outlined,
              iconColor: const Color(0xFF4F6BED),
              label: 'Organizations',
              detail: orgs.isEmpty
                  ? 'None yet'
                  : '${orgs.length} · ${orgs.where((o) => o.id == activeOrgId).firstOrNull?.name ?? ''}',
              onTap: () => _manageOrganizations(context, ref),
            ),
          ],
        ),
        const _Caption('Personalization'),
        _Group(
          children: [
            _SettingsRow(
              icon: Icons.palette_outlined,
              iconColor: const Color(0xFFE3A21A),
              label: 'Accent color',
              detail: settings.accentHex ?? 'Teal (default)',
              trailing: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: settings.accent,
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
              onTap: () => _pickAccent(context, ref),
            ),
            _SettingsRow(
              icon: Icons.vibration_outlined,
              iconColor: context.accent,
              label: 'Haptics',
              detail: settings.hapticsOn ? 'On' : 'Off',
              trailing: Switch.adaptive(
                value: settings.hapticsOn,
                activeThumbColor: KeelTokens.success,
                onChanged: (v) => settings.setHaptics(v),
              ),
            ),
            const _HapticStrengthControl(),
            _SettingsRow(
              icon: Icons.calendar_month_outlined,
              iconColor: const Color(0xFF4F6BED),
              label: 'Week starts on',
              detail: _weekStartLabel(settings.weekStart),
              onTap: () => _pickWeekStart(context, ref),
            ),
          ],
        ),
        const _Caption('Appearance'),
        _Group(
          children: [
            _SettingsRow(
              icon: Icons.dark_mode_outlined,
              iconColor: context.ink,
              label: 'Dark mode',
              detail: switch (settings.themeMode) {
                'light' => 'Light',
                'dark' => 'Dark',
                _ => 'System',
              },
              onTap: () => _pickThemeMode(context, ref),
            ),
            _TextSizeSlider(settings: settings),
            _SettingsRow(
              icon: Icons.motion_photos_off_outlined,
              iconColor: KeelTokens.success,
              label: 'Reduce motion',
              detail: 'Replace animations with simple fades',
              trailing: Switch.adaptive(
                value: settings.reduceMotion,
                activeThumbColor: KeelTokens.success,
                onChanged: (v) => settings.setReduceMotion(v),
              ),
            ),
          ],
        ),
        const _Caption('Utilities'),
        _Group(
          children: [
            _SettingsRow(
              icon: Icons.notifications_outlined,
              iconColor: KeelTokens.overdue,
              label: 'Reminders',
              detail: settings.remindersOn
                  ? 'Daily digest at ${_two(settings.digestHour)}:${_two(settings.digestMinute)}'
                  : 'Daily digest of due and overdue tasks',
              trailing: Switch.adaptive(
                value: settings.remindersOn,
                activeThumbColor: KeelTokens.success,
                onChanged: (v) => _setReminders(context, ref, v),
              ),
              onTap: settings.remindersOn
                  ? () => _pickDigestTime(context, ref)
                  : null,
            ),
            _SettingsRow(
              icon: Icons.file_download_outlined,
              iconColor: KeelTokens.success,
              label: 'Export tasks to CSV',
              onTap: () async {
                final orgId = activeOrgId;
                if (orgId == null) return;
                final ok = await BackupService().exportTasksCsv(repo, orgId);
                if (context.mounted) {
                  showKeelSnack(
                    context,
                    ok ? 'Tasks exported.' : 'Export cancelled.',
                  );
                }
              },
            ),
            _SettingsRow(
              icon: Icons.clear_all_outlined,
              iconColor: KeelTokens.overdue,
              label: 'Clear completed tasks',
              detail: 'Deletes tasks marked done',
              onTap: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Clear completed tasks?'),
                    content: const Text(
                      'All tasks marked done will be permanently deleted. This cannot be undone.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text(
                          'Clear',
                          style: TextStyle(color: KeelTokens.overdue),
                        ),
                      ),
                    ],
                  ),
                );
                if (confirmed == true && activeOrgId != null) {
                  final n = await repo.clearCompletedTasks(activeOrgId);
                  if (context.mounted) {
                    showKeelSnack(context, '$n completed task${n == 1 ? '' : 's'} cleared.');
                  }
                }
              },
            ),
          ],
        ),
        const _Caption('Backup'),
        _Group(
          children: [
            _SettingsRow(
              icon: Icons.cloud_upload_outlined,
              iconColor: const Color(0xFF4F6BED),
              label: 'Back up to phone',
              detail: settings.lastBackup == null
                  ? 'Never backed up'
                  : 'Last: ${_backupDate(settings.lastBackup!)}',
              onTap: () async {
                final summary = await BackupService().backup(repo);
                if (summary == null) return; // user cancelled the picker
                await settings.setLastBackup(DateTime.now());
                if (context.mounted) {
                  showKeelSnack(context, 'Backup saved ($summary).');
                }
              },
            ),
            _SettingsRow(
              icon: Icons.cloud_download_outlined,
              iconColor: context.muted,
              label: 'Restore from file',
              detail: 'Replaces all current data',
              onTap: () => _restore(context, ref),
            ),
            _SettingsRow(
              icon: Icons.science_outlined,
              iconColor: KeelTokens.success,
              label: 'Load sample data',
              detail: 'Northwind Studio demo dataset',
              onTap: () async {
                final orgId = activeOrgId;
                if (orgId == null) return;
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Load sample data?'),
                    content: const Text(
                      'Adds the Northwind Studio demo — 3 teams, 6 people, 6 tasks — to the current organization.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Load'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await loadSampleData(repo, orgId);
                  if (context.mounted) {
                    showKeelSnack(context, 'Sample data loaded.');
                  }
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 24),
        _Group(
          children: [
            _SettingsRow(
              icon: Icons.info_outline,
              iconColor: context.accent,
              label: 'About',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AboutPage()),
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  String _backupDate(DateTime d) =>
      '${d.day}/${d.month}/${d.year} ${_two(d.hour)}:${_two(d.minute)}';

  Future<void> _setReminders(
    BuildContext context,
    WidgetRef ref,
    bool on,
  ) async {
    final settings = ref.read(settingsProvider);
    if (on) {
      final granted = await NotificationService.requestPermission();
      if (!granted && context.mounted) {
        showKeelSnack(
          context,
          'Notifications are off for Keel — enable them in system settings to get the digest.',
        );
      }
    }
    await settings.setReminders(on);
    await NotificationService.setDailyDigest(
      on: on,
      hour: settings.digestHour,
      minute: settings.digestMinute,
      counts: () async {
        final orgId = ref.read(activeOrgProvider).value;
        if (orgId == null) return (overdue: 0, dueSoon: 0, open: 0);
        final stats = await ref.read(repositoryProvider).homeStats(orgId);
        return (
          overdue: stats.overdue,
          dueSoon: stats.dueSoon,
          open: stats.total - stats.done,
        );
      },
    );
  }

  String _weekStartLabel(String v) => switch (v) {
        'saturday' => 'Saturday',
        'sunday' => 'Sunday',
        _ => 'Monday',
      };

  Future<void> _pickWeekStart(BuildContext context, WidgetRef ref) async {
    final settings = ref.read(settingsProvider);
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Week starts on'),
        children: [
          for (final (value, label) in [
            ('monday', 'Monday'),
            ('saturday', 'Saturday'),
            ('sunday', 'Sunday'),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(value),
              child: Row(
                children: [
                  Text(label),
                  const Spacer(),
                  if (settings.weekStart == value)
                    Icon(Icons.check, color: context.accent),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked != null) await settings.setWeekStart(picked);
  }

  Future<void> _pickDigestTime(BuildContext context, WidgetRef ref) async {
    final settings = ref.read(settingsProvider);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: settings.digestHour,
        minute: settings.digestMinute,
      ),
    );
    if (picked == null) return;
    await settings.setDigestTime(picked.hour, picked.minute);
    if (!context.mounted) return;
    if (settings.remindersOn) {
      await _setReminders(context, ref, true);
    }
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore from file?'),
        content: const Text(
          'This replaces ALL current data — organizations, people, teams and tasks — with the backup file. Make a backup first if you are unsure.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Choose file'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final summary =
          await BackupService().restore(ref.read(repositoryProvider));
      if (context.mounted) {
        showKeelSnack(
          context,
          'Restored ${summary.orgs} orgs, ${summary.people} people, ${summary.teams} teams, ${summary.tasks} tasks.',
        );
      }
    } on FormatException catch (e) {
      if (e.message == 'cancelled') return;
      if (context.mounted) showKeelSnack(context, e.message);
    } catch (_) {
      // A foreign file can throw outside FormatException (e.g. a row
      // with the wrong value type inside fromJson). Never crash the
      // restore flow on it — the data is untouched, the transaction
      // never started.
      if (context.mounted) {
        showKeelSnack(
          context,
          'That backup file is damaged and cannot be restored.',
        );
      }
    }
  }

  Future<void> _editProfile(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(repositoryProvider);
    final profile = await repo.getProfile();
    if (!context.mounted) return;
    final name = TextEditingController(text: profile?.name ?? '');
    final role = TextEditingController(text: profile?.role ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Your profile'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'Your name',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: role,
              decoration: const InputDecoration(
                labelText: 'Role',
                hintText: 'Your role',
              ),
            ),
          ],
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
    );
    if (saved == true && name.text.trim().isNotEmpty) {
      await repo.saveProfile(name: name.text, role: role.text);
    }
    // Dialog-local controllers are short-lived but still ChangeNotifiers:
    // dispose them instead of leaking one per edit.
    name.dispose();
    role.dispose();
  }

  Future<void> _manageOrganizations(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(repositoryProvider);
    final settings = ref.read(settingsProvider);
    await showKeelDialogSheet<void>(
      context,
      child: _OrgManagerSheet(repo: repo, settings: settings),
    );
  }

  Future<void> _pickAccent(BuildContext context, WidgetRef ref) async {
    final settings = ref.read(settingsProvider);
    var hex = settings.accentHex ?? KeelTokens.hexOf(KeelTokens.accentLight);
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Accent color'),
          content: SingleChildScrollView(
            child: ColorPickerField(
              valueHex: hex,
              onChanged: (v) => setState(() => hex = v),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Default'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(hex),
              child: const Text('Use this color'),
            ),
          ],
        ),
      ),
    );
    if (picked == null) {
      await settings.setAccent(null);
    } else {
      await settings.setAccent(picked);
    }
  }

  Future<void> _pickThemeMode(BuildContext context, WidgetRef ref) async {
    final settings = ref.read(settingsProvider);
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Dark mode'),
        children: [
          for (final (value, label) in [
            ('system', 'System'),
            ('light', 'Light'),
            ('dark', 'Dark'),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(value),
              child: Row(
                children: [
                  Text(label),
                  const Spacer(),
                  if (settings.themeMode == value)
                    Icon(Icons.check, color: context.accent),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked != null) await settings.setThemeMode(picked);
  }
}

/// Text size as a slider with 4 locked stops — Small, Medium, Large,
/// Extra Large — replacing the old picker dialog. The value persists
/// through the existing setTextScale; main.dart still combines it with
/// the system text scaler.
class _TextSizeSlider extends StatelessWidget {
  final KeelSettings settings;
  const _TextSizeSlider({required this.settings});

  static const _scales = [0.85, 1.0, 1.15, 1.3];
  static const _labels = ['Small', 'Medium', 'Large', 'Extra large'];

  static int _nearestIndex(double v) {
    var best = 0;
    for (var i = 1; i < _scales.length; i++) {
      if ((v - _scales[i]).abs() < (v - _scales[best]).abs()) best = i;
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final index = _nearestIndex(settings.textScale);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF9B5DE5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.text_fields_outlined, size: 19, color: Colors.white),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Text size', style: TextStyle(fontSize: 15)),
              ),
              Text(
                _labels[index],
                style: TextStyle(color: context.muted, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 2),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: context.accent,
              inactiveTrackColor: context.line,
              thumbColor: context.accent,
              overlayColor: context.accent.withValues(alpha: 0.15),
              trackHeight: 4,
            ),
            child: Slider(
              value: index.toDouble(),
              min: 0,
              max: 3,
              divisions: 3,
              label: _labels[index],
              onChanged: (v) =>
                  settings.setTextScale(_scales[v.round()]),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final label in _labels)
                Text(
                  label,
                  style: TextStyle(color: context.muted, fontSize: 11),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OrgManagerSheet extends ConsumerStatefulWidget {
  final KeelRepository repo;
  final KeelSettings settings;
  const _OrgManagerSheet({required this.repo, required this.settings});

  @override
  ConsumerState<_OrgManagerSheet> createState() => _OrgManagerSheetState();
}

/// Vibration Intensity control (Personalisation, under the Haptics
/// toggle). Always visible — never hidden. When Haptics is OFF the
/// control stays on screen but greyed out and untouchable: taps do
/// nothing and no preview buzz plays; the saved value just shows
/// dimmed. When Haptics is ON, tapping an option saves it, shows it
/// selected (filled pill + check) and immediately plays a preview
/// buzz at exactly that strength, so the user feels what they picked.
class _HapticStrengthControl extends ConsumerWidget {
  const _HapticStrengthControl();

  static const _options = [
    ('light', 'Light'),
    ('medium', 'Medium'),
    ('heavy', 'Heavy'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final enabled = settings.hapticsOn;
    final selected = settings.hapticStrength;
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Vibration Intensity', style: TextStyle(fontSize: 15)),
              ),
              if (!enabled)
                Text('Off', style: TextStyle(color: context.muted, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < _options.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: enabled
                        ? () async {
                            await settings.setHapticStrength(_options[i].$1);
                            KeelHaptics.preview(ref, _options[i].$1);
                          }
                        : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: selected == _options[i].$1
                            ? context.accent
                            : context.card,
                        borderRadius: BorderRadius.circular(12),
                        border: selected == _options[i].$1
                            ? null
                            : Border.all(color: context.line),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (selected == _options[i].$1)
                            const Icon(Icons.check, size: 16, color: Colors.white),
                          if (selected == _options[i].$1)
                            const SizedBox(width: 4),
                          Text(
                            _options[i].$2,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: selected == _options[i].$1
                                  ? Colors.white
                                  : context.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
    if (!enabled) {
      // Visible but untouchable: greyed out, taps blocked, no preview.
      return Opacity(
        opacity: 0.45,
        child: IgnorePointer(child: content),
      );
    }
    return content;
  }
}

class _OrgManagerSheetState extends ConsumerState<_OrgManagerSheet> {
  @override
  Widget build(BuildContext context) {
    final orgsAsync = ref.watch(organizationsProvider);
    final activeOrgAsync = ref.watch(activeOrgProvider);
    final orgs = orgsAsync.value ?? const [];
    final activeId = activeOrgAsync.value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Organizations', style: Theme.of(context).textTheme.displayMedium?.copyWith(fontSize: 24)),
          const SizedBox(height: 12),
          for (final org in orgs)
            KeelCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        await widget.settings.setActiveOrg(org.id);
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(org.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                          Text(org.kind, style: TextStyle(color: context.muted, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                  if (activeId == org.id)
                    Icon(Icons.check_circle, color: context.accent),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_horiz, color: context.muted),
                    onSelected: (value) async {
                      if (value == 'rename') {
                        final name = TextEditingController(text: org.name);
                        final saved = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Rename organization'),
                            content: TextField(controller: name, autofocus: true),
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
                        );
                        if (saved == true && name.text.trim().isNotEmpty) {
                          await widget.repo.renameOrganization(org.id, name.text);
                        }
                        name.dispose();
                      } else if (value == 'delete') {
                        if (orgs.length <= 1) {
                          if (context.mounted) {
                            showKeelSnack(
                              context,
                              'Keep at least one organization.',
                            );
                          }
                          return;
                        }
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text('Delete ${org.name}?'),
                            content: const Text(
                              'Everything inside this organization — its teams, people and tasks — will be deleted.',
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
                        if (confirmed == true) {
                          if (activeId == org.id) {
                            final remaining =
                                orgs.where((o) => o.id != org.id).toList();
                            await widget.settings
                                .setActiveOrg(remaining.first.id);
                          }
                          await widget.repo.deleteOrganization(org.id);
                        }
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'rename', child: Text('Rename')),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          'Delete',
                          style: TextStyle(color: KeelTokens.overdue),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final name = TextEditingController();
                final created = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('New organization'),
                    content: TextField(
                      controller: name,
                      autofocus: true,
                      decoration: const InputDecoration(hintText: 'Organization name'),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Create'),
                      ),
                    ],
                  ),
                );
                if (created == true && name.text.trim().isNotEmpty) {
                  final org = await widget.repo.createOrganization(
                    name: name.text,
                    kind: 'Other',
                  );
                  await widget.settings.setActiveOrg(org.id);
                }
                name.dispose();
              },
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Add organization'),
              style: OutlinedButton.styleFrom(
                foregroundColor: context.accent,
                side: BorderSide(color: context.line),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(KeelTokens.radiusButton),
                ),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  final List<Widget> children;
  const _Group({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: context.isDark
            ? null
            : [
                const BoxShadow(
                  color: Color(0x140D1B26),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                  spreadRadius: -12,
                ),
              ],
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Divider(height: 1, indent: 58, color: context.line),
          ],
        ],
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  final String text;
  const _Caption(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 18, 6, 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: context.muted,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String? detail;
  final Widget? trailing;
  final VoidCallback? onTap;
  const _SettingsRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    this.detail,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 19, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(fontSize: 15)),
                    if (detail != null)
                      Text(
                        detail!,
                        style: TextStyle(color: context.muted, fontSize: 13),
                      ),
                  ],
                ),
              ),
              trailing ??
                  (onTap != null
                      ? Icon(Icons.chevron_right, color: context.muted, size: 20)
                      : const SizedBox.shrink()),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// About page
// ---------------------------------------------------------------------------

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  Future<void> _open(BuildContext context, String url, String label) async {
    // Launch directly and check the result: gating on canLaunchUrl
    // false-negatives on Android 11+ when the intent is not declared
    // in <queries> (that was the About-links bug — the check said
    // "cannot open" even though a browser exists). The manifest now
    // also declares the VIEW/BROWSABLE queries, so both layers agree.
    final uri = Uri.parse(url);
    bool opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) {
      showKeelSnack(context, 'Could not open $label.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.chevron_left, color: context.accent, size: 28),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Back to Settings',
        ),
        title: Text('Settings', style: TextStyle(color: context.accent, fontSize: 17)),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
        children: [
          Center(
            child: Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF12A0AB), Color(0xFF0B4F66)],
                ),
              ),
              child: const Icon(Icons.anchor_rounded, size: 50, color: Colors.white),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text('Keel', style: Theme.of(context).textTheme.displayLarge),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              'Version 1.0.0 · Works fully offline',
              style: TextStyle(color: context.muted, fontSize: 13),
            ),
          ),
          const SizedBox(height: 18),
          const KeelCard(
            child: Center(
              child: Text(
                'One manager. Many teams. Everything stays on your phone.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, height: 1.45),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _Caption('What Keel does'),
          const SizedBox(height: 6),
          const KeelCard(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Column(
              children: [
                _FeatureRow(icon: Icons.group_outlined, text: 'Teams with one leader and one main task'),
                _FeatureRow(icon: Icons.check_box_outlined, text: 'Tasks with sub-tasks, due dates and priorities'),
                _FeatureRow(icon: Icons.person_outline, text: 'People with phones, emails, photos and notes'),
                _FeatureRow(icon: Icons.business_outlined, text: 'Multiple organizations, all on-device'),
                _FeatureRow(icon: Icons.cloud_off_outlined, text: 'No account, no server, no internet'),
                _FeatureRow(icon: Icons.backup_outlined, text: 'Backup and restore from a file you control'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _Caption('Developer'),
          const SizedBox(height: 6),
          KeelCard(
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: KeelTokens.tint14(context.accent, context.card),
                    border: Border.all(color: context.accent, width: 2.5),
                  ),
                  child: Center(
                    child: Text(
                      'AB',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                        color: context.accent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Aby Bijo', style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w800, fontSize: 18)),
                      Text('Designer and developer', style: TextStyle(color: Color(0xFF7B8894), fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          KeelButton(
            label: 'GitHub',
            background: const Color(0xFF0D1B26),
            foreground: Colors.white,
            icon: Icons.code_outlined,
            onPressed: () => _open(context, KeelLinks.github, 'GitHub'),
          ),
          const SizedBox(height: 10),
          KeelButton(
            label: 'LinkedIn',
            background: const Color(0xFF2A6FB0),
            foreground: Colors.white,
            icon: Icons.work_outline,
            onPressed: () => _open(context, KeelLinks.linkedIn, 'LinkedIn'),
          ),
          const SizedBox(height: 10),
          KeelButton(
            label: 'Buy Me a Coffee',
            background: const Color(0xFFF5C33B),
            foreground: const Color(0xFF1B1400),
            icon: Icons.coffee_outlined,
            onPressed: () => _open(context, KeelLinks.buyMeACoffee, 'Buy Me a Coffee'),
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _FeatureRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, size: 20, color: context.accent),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14, height: 1.35))),
        ],
      ),
    );
  }
}
