import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'db.dart';
import 'providers.dart';
import 'repo.dart';
import 'services.dart';
import 'task_card.dart';
import 'theme.dart';
import 'widgets.dart';

// ---------------------------------------------------------------------------
// Shared sheet scaffold: title, close button, scrollable body, bottom button.
// Keyboard-aware via viewInsets padding.
// ---------------------------------------------------------------------------

class SheetScaffold extends StatelessWidget {
  final String title;
  final Widget child;
  final String buttonLabel;
  final VoidCallback? onButton;
  final ScrollController scrollController;

  const SheetScaffold({
    super.key,
    required this.title,
    required this.child,
    required this.buttonLabel,
    required this.onButton,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.displayMedium,
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
                color: context.muted,
                tooltip: 'Close',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(controller: scrollController, children: [child]),
          ),
          const SizedBox(height: 12),
          KeelButton(label: buttonLabel, onPressed: onButton),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Colour picker: 6 presets + hue / lightness sliders + hex field.
// ---------------------------------------------------------------------------

class ColorPickerField extends StatefulWidget {
  final String valueHex;
  final ValueChanged<String> onChanged;
  const ColorPickerField({
    super.key,
    required this.valueHex,
    required this.onChanged,
  });

  @override
  State<ColorPickerField> createState() => _ColorPickerFieldState();
}

class _ColorPickerFieldState extends State<ColorPickerField> {
  late final TextEditingController _hex;

  @override
  void initState() {
    super.initState();
    _hex = TextEditingController(text: widget.valueHex);
  }

  @override
  void didUpdateWidget(ColorPickerField old) {
    super.didUpdateWidget(old);
    if (old.valueHex != widget.valueHex && _hex.text != widget.valueHex) {
      _hex.text = widget.valueHex;
    }
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = KeelTokens.colorFromHex(widget.valueHex);
    final hsl = HSLColor.fromColor(color);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The swatch row scrolls horizontally: 6 presets + the custom
        // swatch are wider than a narrow sheet, and a plain Row would
        // overflow outside the sheet window (RenderFlex overflow).
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final preset in KeelTokens.teamPresets)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: GestureDetector(
                    onTap: () => widget.onChanged(KeelTokens.hexOf(preset)),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: preset,
                        borderRadius: BorderRadius.circular(13),
                        border:
                            widget.valueHex.toUpperCase() ==
                                KeelTokens.hexOf(preset).toUpperCase()
                            ? Border.all(color: context.ink, width: 2.5)
                            : null,
                      ),
                      child:
                          widget.valueHex.toUpperCase() ==
                              KeelTokens.hexOf(preset).toUpperCase()
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 20,
                            )
                          : null,
                    ),
                  ),
                ),
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: context.line, width: 1.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SliderRow(
          label: 'Hue',
          value: hsl.hue,
          max: 360,
          onChanged: (v) =>
              widget.onChanged(KeelTokens.hexOf(hsl.withHue(v).toColor())),
        ),
        _SliderRow(
          label: 'Lightness',
          value: hsl.lightness,
          max: 1,
          onChanged: (v) => widget.onChanged(
            KeelTokens.hexOf(hsl.withLightness(v).toColor()),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 140,
          child: TextField(
            controller: _hex,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(hintText: '#E5604D'),
            onSubmitted: (v) {
              final hex = v.trim();
              if (RegExp(r'^#?[0-9A-Fa-f]{6}$').hasMatch(hex)) {
                widget.onChanged(
                  hex.startsWith('#')
                      ? hex.toUpperCase()
                      : '#${hex.toUpperCase()}',
                );
              } else {
                _hex.text = widget.valueHex;
                showKeelSnack(context, 'Enter a hex colour like #E5604D');
              }
            },
          ),
        ),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double max;
  final ValueChanged<double> onChanged;
  const _SliderRow({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 74,
          child: Text(
            label,
            style: TextStyle(color: context.muted, fontSize: 13),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(0, max),
            max: max,
            activeColor: context.accent,
            inactiveColor: context.line,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Pickers
// ---------------------------------------------------------------------------

/// Multi-select people picker sheet. Returns the chosen ids, or null.
Future<List<String>?> pickPeople(
  BuildContext context, {
  required String orgId,
  required List<String> selected,
  String title = 'Choose people',
}) {
  return showKeelSheet<List<String>>(
    context,
    builder: (context, scrollController) =>
        _PeoplePickerSheet(orgId: orgId, selected: selected, title: title),
  );
}

class _PeoplePickerSheet extends ConsumerStatefulWidget {
  final String orgId;
  final List<String> selected;
  final String title;
  const _PeoplePickerSheet({
    required this.orgId,
    required this.selected,
    required this.title,
  });

  @override
  ConsumerState<_PeoplePickerSheet> createState() => _PeoplePickerSheetState();
}

class _PeoplePickerSheetState extends ConsumerState<_PeoplePickerSheet> {
  late final Set<String> _sel = {...widget.selected};
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final peopleAsync = ref.watch(peopleProvider(widget.orgId));
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.title,
                style: Theme.of(context).textTheme.displayMedium,
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(_sel.toList()),
              child: Text(
                'Done',
                style: TextStyle(
                  color: context.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: 'Search people',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: peopleAsync.when(
            data: (people) {
              final q = _search.text.trim().toLowerCase();
              final shown = q.isEmpty
                  ? people
                  : people
                        .where((p) => p.name.toLowerCase().contains(q))
                        .toList();
              if (shown.isEmpty) {
                return const EmptyState(
                  icon: Icons.person_search_outlined,
                  title: 'No people found',
                  body: 'Try a different search, or add a new person first.',
                  actionLabel: 'Close',
                  onAction: _noop,
                );
              }
              return ListView.builder(
                itemCount: shown.length,
                itemBuilder: (context, i) {
                  final p = shown[i];
                  final teams =
                      ref.watch(personTeamsProvider(p.id)).value ?? const [];
                  return _PersonRow(
                    person: p,
                    ringColor: firstTeamColor(teams),
                    selected: _sel.contains(p.id),
                    onTap: () => setState(() {
                      if (_sel.contains(p.id)) {
                        _sel.remove(p.id);
                      } else {
                        _sel.add(p.id);
                      }
                    }),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) =>
                const Center(child: Text('Could not load people.')),
          ),
        ),
      ],
    );
  }
}

void _noop() {}

class _PersonRow extends StatelessWidget {
  final Person person;
  final Color ringColor;
  final bool selected;
  final VoidCallback onTap;
  const _PersonRow({
    required this.person,
    required this.ringColor,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return KeelCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      onTap: onTap,
      child: Row(
        children: [
          PersonAvatar(person: person, ringColor: ringColor, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  person.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                if (person.roleTitle.isNotEmpty)
                  Text(
                    person.roleTitle,
                    style: TextStyle(color: context.muted, fontSize: 13),
                  ),
              ],
            ),
          ),
          KeelCheckbox(value: selected, size: 24, onChanged: (_) => onTap()),
        ],
      ),
    );
  }
}

/// Single-select team picker. Returns the chosen team, or null.
Future<Team?> pickTeam(BuildContext context, {required String orgId}) {
  return showKeelSheet<Team>(
    context,
    builder: (context, scrollController) => _TeamPickerSheet(orgId: orgId),
  );
}

class _TeamPickerSheet extends ConsumerWidget {
  final String orgId;
  const _TeamPickerSheet({required this.orgId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teamsAsync = ref.watch(teamsProvider(orgId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Choose a team', style: Theme.of(context).textTheme.displayMedium),
        const SizedBox(height: 12),
        Expanded(
          child: teamsAsync.when(
            data: (teams) {
              if (teams.isEmpty) {
                return const EmptyState(
                  icon: Icons.group_outlined,
                  title: 'No teams yet',
                  body: 'Create a team first, then assign tasks to it.',
                  actionLabel: 'Close',
                  onAction: _noop,
                );
              }
              return ListView.builder(
                itemCount: teams.length,
                itemBuilder: (context, i) {
                  final t = teams[i];
                  final color = KeelTokens.colorFromHex(t.colorHex);
                  return KeelCard(
                    padding: const EdgeInsets.all(14),
                    onTap: () => Navigator.of(context).pop(t),
                    child: Row(
                      children: [
                        Container(
                          width: 12,
                          height: 40,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            t.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        Icon(Icons.chevron_right, color: context.muted),
                      ],
                    ),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => const Center(child: Text('Could not load teams.')),
          ),
        ),
      ],
    );
  }
}

/// Leader picker dialog. Returns the chosen person id, or null if cancelled.
Future<String?> pickLeader(
  BuildContext context, {
  required String orgId,
  required List<Person> candidates,
  String? currentLeaderId,
  String title = 'Choose a leader',
}) async {
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: candidates.length,
          itemBuilder: (context, i) {
            final p = candidates[i];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: PersonAvatar(
                person: p,
                ringColor: KeelTokens.noTeam,
                size: 40,
              ),
              title: Text(p.name),
              subtitle: p.roleTitle.isEmpty ? null : Text(p.roleTitle),
              trailing: p.id == currentLeaderId
                  ? Icon(Icons.check, color: context.accent)
                  : null,
              onTap: () => Navigator.of(context).pop(p.id),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// New Task sheet
// ---------------------------------------------------------------------------

Future<void> showNewTaskSheet(
  BuildContext context, {
  required String orgId,
  String? presetTeamId,
  DateTime? presetDueDate,
}) {
  return showKeelSheet<void>(
    context,
    builder: (context, c) => _NewTaskSheet(
      orgId: orgId,
      presetTeamId: presetTeamId,
      presetDueDate: presetDueDate,
      scrollController: c,
    ),
  );
}

class _NewTaskSheet extends ConsumerStatefulWidget {
  final String orgId;
  final String? presetTeamId;
  final DateTime? presetDueDate;
  final ScrollController scrollController;
  const _NewTaskSheet({
    required this.orgId,
    this.presetTeamId,
    this.presetDueDate,
    required this.scrollController,
  });

  @override
  ConsumerState<_NewTaskSheet> createState() => _NewTaskSheetState();
}

class _NewTaskSheetState extends ConsumerState<_NewTaskSheet> {
  final _title = TextEditingController();
  final _notes = TextEditingController();
  final _sub = TextEditingController();
  DateTime? _due;
  String _priority = 'none';
  String? _teamId;
  final _assignees = <String>{};
  final _subs = <String>[];
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _sub.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _teamId = widget.presetTeamId;
    // From the calendar: the new task is due on the tapped day.
    _due = widget.presetDueDate;
  }

  Future<void> _create() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Give the task a title.');
      return;
    }
    final repo = ref.read(repositoryProvider);
    await repo.createTask(
      orgId: widget.orgId,
      title: _title.text,
      notes: _notes.text,
      dueDate: _due,
      priority: _priority,
      teamId: _teamId,
      assigneeIds: _assignees.toList(),
      subTodoTitles: _subs,
    );
    // A dated task gets its reminders now (1.3.0).
    unawaited(NotificationService.syncForRef(ref));
    if (mounted) {
      Navigator.of(context).pop();
      showKeelSnack(context, 'Task created');
    }
  }

  @override
  Widget build(BuildContext context) {
    final teamsAsync = ref.watch(teamsProvider(widget.orgId));
    final peopleAsync = ref.watch(peopleProvider(widget.orgId));
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueChips = <(String, DateTime?)>[
      ('Today', today),
      ('Tomorrow', today.add(const Duration(days: 1))),
      ('Pick', null),
    ];
    return SheetScaffold(
      title: 'New task',
      buttonLabel: 'Create task',
      onButton: _create,
      scrollController: widget.scrollController,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KeelTextField(
            controller: _title,
            hint: 'Task title',
            autofocus: true,
            errorText: _error,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          KeelTextField(
            controller: _notes,
            hint: 'Notes (optional)',
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          const _Caption('Due date'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final (label, date) in dueChips)
                ChoiceChip(
                  label: Text(
                    label == 'Pick' && _due != null
                        ? '${_due!.day}/${_due!.month}/${_due!.year}'
                        : label,
                  ),
                  selected: label == 'Pick'
                      ? _due != null &&
                            _due != today &&
                            _due != today.add(const Duration(days: 1))
                      : _due == date,
                  selectedColor: context.accent,
                  labelStyle: TextStyle(
                    color:
                        (label == 'Pick'
                            ? _due != null &&
                                  _due != today &&
                                  _due != today.add(const Duration(days: 1))
                            : _due == date)
                        ? Colors.white
                        : context.ink,
                    fontWeight: FontWeight.w600,
                  ),
                  backgroundColor: context.card,
                  side: BorderSide(color: context.line),
                  onSelected: (_) async {
                    if (label == 'Pick') {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _due ?? today,
                        firstDate: today.subtract(const Duration(days: 365)),
                        lastDate: today.add(const Duration(days: 365 * 5)),
                      );
                      if (picked != null) setState(() => _due = picked);
                    } else {
                      setState(() => _due = date);
                    }
                  },
                ),
              if (_due != null)
                ActionChip(
                  label: const Text('Clear'),
                  onPressed: () => setState(() => _due = null),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const _Caption('Priority'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final p in ['none', 'low', 'medium', 'high'])
                ChoiceChip(
                  label: Text(p[0].toUpperCase() + p.substring(1)),
                  selected: _priority == p,
                  selectedColor: context.accent,
                  labelStyle: TextStyle(
                    color: _priority == p ? Colors.white : context.ink,
                    fontWeight: FontWeight.w600,
                  ),
                  backgroundColor: context.card,
                  side: BorderSide(color: context.line),
                  onSelected: (_) => setState(() => _priority = p),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const _Caption('Team'),
          const SizedBox(height: 8),
          teamsAsync.when(
            data: (teams) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('No team'),
                  selected: _teamId == null,
                  selectedColor: context.accent,
                  labelStyle: TextStyle(
                    color: _teamId == null ? Colors.white : context.ink,
                    fontWeight: FontWeight.w600,
                  ),
                  backgroundColor: context.card,
                  side: BorderSide(color: context.line),
                  onSelected: (_) => setState(() => _teamId = null),
                ),
                for (final t in teams)
                  ChoiceChip(
                    label: Text(t.name),
                    selected: _teamId == t.id,
                    selectedColor: KeelTokens.colorFromHex(t.colorHex),
                    labelStyle: TextStyle(
                      color: _teamId == t.id ? Colors.white : context.ink,
                      fontWeight: FontWeight.w600,
                    ),
                    backgroundColor: context.card,
                    side: BorderSide(color: context.line),
                    onSelected: (_) => setState(() => _teamId = t.id),
                  ),
              ],
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 16),
          const _Caption('Assignees'),
          const SizedBox(height: 8),
          peopleAsync.when(
            data: (people) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in people)
                  FilterChip(
                    label: Text(p.name),
                    selected: _assignees.contains(p.id),
                    selectedColor: KeelTokens.tint14(
                      context.accent,
                      context.card,
                    ),
                    checkmarkColor: context.accent,
                    backgroundColor: context.card,
                    side: BorderSide(color: context.line),
                    onSelected: (v) => setState(() {
                      if (v) {
                        _assignees.add(p.id);
                      } else {
                        _assignees.remove(p.id);
                      }
                    }),
                  ),
              ],
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 16),
          const _Caption('Sub-tasks'),
          const SizedBox(height: 8),
          for (var i = 0; i < _subs.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(child: Text('• ${_subs[i]}')),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    color: context.muted,
                    onPressed: () => setState(() => _subs.removeAt(i)),
                    tooltip: 'Remove sub-task',
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _sub,
                  decoration: const InputDecoration(hintText: 'Add a sub-task'),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _addSub(),
                ),
              ),
              IconButton(
                icon: Icon(Icons.add_circle, color: context.accent, size: 28),
                onPressed: _addSub,
                tooltip: 'Add sub-task',
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _addSub() {
    final t = _sub.text.trim();
    if (t.isEmpty) return;
    setState(() {
      _subs.add(t);
      _sub.clear();
    });
  }
}

class _Caption extends StatelessWidget {
  final String text;
  const _Caption(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: context.muted,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// New Person sheet
// ---------------------------------------------------------------------------

/// New / Edit person sheet (1.3.0, DECISIONS.md 37): one sheet for
/// create and edit. Editing opens the same slide-up window,
/// pre-filled — phones, emails, photo, notes and teams all
/// changeable — the way task editing already works. The old small
/// `_editPerson` popup in people.dart is deleted.
Future<void> showNewPersonSheet(
  BuildContext context, {
  required String orgId,
  Person? existing,
}) {
  return showKeelSheet<void>(
    context,
    builder: (context, c) =>
        _NewPersonSheet(orgId: orgId, existing: existing, scrollController: c),
  );
}

class _NewPersonSheet extends ConsumerStatefulWidget {
  final String orgId;
  final Person? existing;
  final ScrollController scrollController;
  const _NewPersonSheet({
    required this.orgId,
    this.existing,
    required this.scrollController,
  });

  @override
  ConsumerState<_NewPersonSheet> createState() => _NewPersonSheetState();
}

class _NewPersonSheetState extends ConsumerState<_NewPersonSheet> {
  late final TextEditingController _name;
  late final TextEditingController _role;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _notes;
  final _teams = <String>{};
  List<PersonPhone> _phones = [];
  List<PersonEmail> _emails = [];
  String? _photoPath;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.name ?? '');
    _role = TextEditingController(text: existing?.roleTitle ?? '');
    _phone = TextEditingController();
    _email = TextEditingController();
    _notes = TextEditingController(text: existing?.notes ?? '');
    _photoPath = existing?.photoPath;
    if (existing != null) {
      // Pre-fill the current phones, emails and teams. Loaded once
      // here (not streamed): adds/removes below update the lists
      // and the DB together, so the sheet never shows stale rows.
      final repo = ref.read(repositoryProvider);
      repo.getPhones(existing.id).then((v) {
        if (mounted) setState(() => _phones = v);
      });
      repo.getEmails(existing.id).then((v) {
        if (mounted) setState(() => _emails = v);
      });
      repo.getTeamsForPerson(existing.id).then((v) {
        if (mounted) setState(() => _teams.addAll(v.map((t) => t.id)));
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _role.dispose();
    _phone.dispose();
    _email.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Give the person a name.');
      return;
    }
    final repo = ref.read(repositoryProvider);
    await repo.createPerson(
      orgId: widget.orgId,
      name: _name.text,
      roleTitle: _role.text,
      notes: _notes.text,
      phones: _phone.text.trim().isEmpty
          ? const []
          : [(label: 'mobile', number: _phone.text)],
      emails: _email.text.trim().isEmpty
          ? const []
          : [(label: 'work', address: _email.text)],
      teamIds: _teams.toList(),
    );
    if (mounted) {
      Navigator.of(context).pop();
      showKeelSnack(context, 'Person added');
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Give the person a name.');
      return;
    }
    final person = widget.existing!;
    final repo = ref.read(repositoryProvider);
    await repo.updatePerson(
      person.id,
      name: _name.text,
      roleTitle: _role.text,
      notes: _notes.text,
      photoPath: Value(_photoPath),
    );
    // Phones/emails added or removed below are already in the DB
    // (they apply live); only the team memberships sync here.
    final current = (await repo.getTeamsForPerson(
      person.id,
    )).map((t) => t.id).toSet();
    for (final id in _teams) {
      if (!current.contains(id)) await repo.addTeamMember(id, person.id);
    }
    for (final id in current) {
      if (_teams.contains(id)) continue;
      try {
        await repo.removeTeamMember(id, person.id);
      } on LeaderRemovalNeedsReplacement {
        // Rule 4: they lead this team — pick a replacement first.
        if (!mounted) return;
        final members = await repo.getTeamMembers(id);
        final candidates = members.where((p) => p.id != person.id).toList();
        if (candidates.isEmpty) {
          if (mounted) {
            showKeelSnack(
              context,
              '${person.name} is the only member of that team. Add someone first.',
            );
          }
          return;
        }
        if (!mounted) return;
        final replacement = await pickLeader(
          context,
          orgId: widget.orgId,
          candidates: candidates,
          title: 'Pick a new leader',
        );
        if (replacement != null) {
          await repo.removeTeamMember(id, person.id, newLeaderId: replacement);
        }
      }
    }
    if (mounted) {
      Navigator.of(context).pop();
      showKeelSnack(context, 'Person updated');
    }
  }

  Future<void> _addPhone() async {
    final number = _phone.text.trim();
    final person = widget.existing;
    if (number.isEmpty || person == null) return;
    final repo = ref.read(repositoryProvider);
    await repo.addPhone(person.id, 'mobile', number);
    final phones = await repo.getPhones(person.id);
    _phone.clear();
    if (mounted) setState(() => _phones = phones);
  }

  Future<void> _addEmail() async {
    final address = _email.text.trim();
    final person = widget.existing;
    if (address.isEmpty || person == null) return;
    final repo = ref.read(repositoryProvider);
    await repo.addEmail(person.id, 'work', address);
    final emails = await repo.getEmails(person.id);
    _email.clear();
    if (mounted) setState(() => _emails = emails);
  }

  /// Photo picker (edit only): camera / gallery / remove, the same
  /// choice sheet the person page uses. The picked file is only
  /// saved to the person when Save is tapped.
  Future<void> _pickPhoto() async {
    final person = widget.existing;
    if (person == null) return;
    final choice = await showKeelDialogSheet<String>(
      context,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Photo',
              style: Theme.of(
                context,
              ).textTheme.displayMedium?.copyWith(fontSize: 22),
            ),
            const SizedBox(height: 14),
            KeelButton(
              label: 'Take a photo',
              onPressed: () => Navigator.of(context).pop('camera'),
              secondary: true,
            ),
            const SizedBox(height: 10),
            KeelButton(
              label: 'Choose from gallery',
              onPressed: () => Navigator.of(context).pop('gallery'),
              secondary: true,
            ),
            if (_photoPath != null) ...[
              const SizedBox(height: 10),
              KeelButton(
                label: 'Remove photo',
                onPressed: () => Navigator.of(context).pop('remove'),
                secondary: true,
              ),
            ],
          ],
        ),
      ),
    );
    if (choice == 'camera' || choice == 'gallery') {
      final source = choice == 'camera'
          ? ImageSource.camera
          : ImageSource.gallery;
      final path = await PhotoService().pickPhoto(
        source: source,
        personId: person.id,
      );
      if (path != null && mounted) setState(() => _photoPath = path);
    } else if (choice == 'remove') {
      final old = _photoPath;
      if (mounted) setState(() => _photoPath = null);
      if (old != null) unawaited(PhotoService().deletePhoto(old));
    }
  }

  @override
  Widget build(BuildContext context) {
    final teamsAsync = ref.watch(teamsProvider(widget.orgId));
    final repo = ref.read(repositoryProvider);
    return SheetScaffold(
      title: _isEdit ? 'Edit person' : 'New person',
      buttonLabel: _isEdit ? 'Save changes' : 'Add person',
      onButton: _isEdit ? _save : _create,
      scrollController: widget.scrollController,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isEdit) ...[
            Row(
              children: [
                PersonAvatar(
                  person: widget.existing!.copyWith(
                    photoPath: Value(_photoPath),
                  ),
                  ringColor: KeelTokens.noTeam,
                  size: 56,
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _pickPhoto,
                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: const Text('Change photo'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.accent,
                    side: BorderSide(color: context.line),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          KeelTextField(
            controller: _name,
            label: 'Name',
            hint: 'Full name',
            autofocus: !_isEdit,
            errorText: _error,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          KeelTextField(
            controller: _role,
            label: 'Role',
            hint: 'Role (optional)',
            textInputAction: TextInputAction.next,
          ),
          if (!_isEdit) ...[
            const SizedBox(height: 12),
            KeelTextField(
              controller: _phone,
              label: 'Phone',
              hint: 'First phone (optional)',
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            KeelTextField(
              controller: _email,
              label: 'Email',
              hint: 'First email (optional)',
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
            ),
          ] else ...[
            const SizedBox(height: 16),
            const _Caption('Phones'),
            const SizedBox(height: 8),
            for (final ph in _phones)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(child: Text('${ph.label}: ${ph.number}')),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      color: context.muted,
                      onPressed: () async {
                        await repo.deletePhone(ph.id);
                        if (mounted) {
                          setState(() => _phones.remove(ph));
                        }
                      },
                      tooltip: 'Delete phone',
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _phone,
                    decoration: const InputDecoration(hintText: 'Add a phone'),
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _addPhone(),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.add_circle, color: context.accent, size: 28),
                  onPressed: _addPhone,
                  tooltip: 'Add phone',
                ),
              ],
            ),
            const SizedBox(height: 16),
            const _Caption('Emails'),
            const SizedBox(height: 8),
            for (final em in _emails)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(child: Text('${em.label}: ${em.address}')),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      color: context.muted,
                      onPressed: () async {
                        await repo.deleteEmail(em.id);
                        if (mounted) {
                          setState(() => _emails.remove(em));
                        }
                      },
                      tooltip: 'Delete email',
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _email,
                    decoration: const InputDecoration(hintText: 'Add an email'),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _addEmail(),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.add_circle, color: context.accent, size: 28),
                  onPressed: _addEmail,
                  tooltip: 'Add email',
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          const _Caption('Teams'),
          const SizedBox(height: 8),
          teamsAsync.when(
            data: (teams) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in teams)
                  FilterChip(
                    label: Text(t.name),
                    selected: _teams.contains(t.id),
                    selectedColor: KeelTokens.tint14(
                      KeelTokens.colorFromHex(t.colorHex),
                      context.card,
                    ),
                    checkmarkColor: KeelTokens.colorFromHex(t.colorHex),
                    backgroundColor: context.card,
                    side: BorderSide(color: context.line),
                    onSelected: (v) => setState(() {
                      if (v) {
                        _teams.add(t.id);
                      } else {
                        _teams.remove(t.id);
                      }
                    }),
                  ),
              ],
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 16),
          KeelTextField(
            controller: _notes,
            label: 'Notes',
            hint: 'Notes (optional)',
            maxLines: 3,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// New Team sheet — leader required (rule 4), leader can be created inline.
// ---------------------------------------------------------------------------

/// New / Edit team sheet (1.3.0, DECISIONS.md 37): one sheet for
/// create and edit. Editing opens the same slide-up window,
/// pre-filled — name, colour, leader, members and (edit only) the
/// main task, all changeable — the way task editing already works.
/// The old small `_editTeam` popup in teams.dart is deleted.
Future<void> showNewTeamSheet(
  BuildContext context, {
  required String orgId,
  Team? existing,
}) {
  return showKeelSheet<void>(
    context,
    builder: (context, c) =>
        _NewTeamSheet(orgId: orgId, existing: existing, scrollController: c),
  );
}

class _NewTeamSheet extends ConsumerStatefulWidget {
  final String orgId;
  final Team? existing;
  final ScrollController scrollController;
  const _NewTeamSheet({
    required this.orgId,
    this.existing,
    required this.scrollController,
  });

  @override
  ConsumerState<_NewTeamSheet> createState() => _NewTeamSheetState();
}

class _NewTeamSheetState extends ConsumerState<_NewTeamSheet> {
  late final TextEditingController _name;
  late String _color;
  String? _leaderId;
  String? _mainTaskId;
  final _members = <String>{};
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.name ?? '');
    _color = existing?.colorHex ?? KeelTokens.hexOf(KeelTokens.teamPresets[0]);
    _leaderId = existing?.leaderPersonId;
    _mainTaskId = existing?.mainTaskId;
    if (existing != null) {
      // Pre-fill the current members. Loaded once here (not
      // streamed): the chips toggle local state until Save.
      ref.read(repositoryProvider).getTeamMembers(existing.id).then((v) {
        if (mounted) setState(() => _members.addAll(v.map((p) => p.id)));
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Give the team a name.');
      return;
    }
    if (_leaderId == null) {
      setState(() => _error = 'Choose a leader for the team.');
      return;
    }
    final repo = ref.read(repositoryProvider);
    await repo.createTeam(
      orgId: widget.orgId,
      name: _name.text,
      colorHex: _color,
      leaderPersonId: _leaderId!,
      memberIds: _members.toList(),
    );
    if (mounted) {
      Navigator.of(context).pop();
      showKeelSnack(context, 'Team created');
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Give the team a name.');
      return;
    }
    if (_leaderId == null) {
      setState(() => _error = 'Choose a leader for the team.');
      return;
    }
    final team = widget.existing!;
    final repo = ref.read(repositoryProvider);
    final current = (await repo.getTeamMembers(
      team.id,
    )).map((p) => p.id).toSet();
    // 1) Add new members first: the new leader must already be a
    //    member before updateTeam accepts them as leader.
    for (final id in _members) {
      if (!current.contains(id)) await repo.addTeamMember(team.id, id);
    }
    // 2) Name / colour / leader.
    await repo.updateTeam(
      team.id,
      name: _name.text,
      colorHex: _color,
      leaderPersonId: _leaderId,
    );
    // 3) Remove deselected members. The current leader's chip is
    //    disabled, so this never removes the leader; the old leader
    //    can leave now that leadership has moved.
    for (final id in current) {
      if (!_members.contains(id)) {
        await repo.removeTeamMember(team.id, id);
      }
    }
    // 4) Main task, if changed.
    if (_mainTaskId != team.mainTaskId) {
      await repo.setMainTask(team.id, _mainTaskId);
    }
    if (mounted) {
      Navigator.of(context).pop();
      showKeelSnack(context, 'Team updated');
    }
  }

  @override
  Widget build(BuildContext context) {
    final peopleAsync = ref.watch(peopleProvider(widget.orgId));
    final tasksAsync = ref.watch(tasksProvider(widget.orgId));
    return SheetScaffold(
      title: _isEdit ? 'Edit team' : 'New team',
      buttonLabel: _isEdit ? 'Save changes' : 'Create team',
      onButton: _isEdit ? _save : _create,
      scrollController: widget.scrollController,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KeelTextField(
            controller: _name,
            hint: 'Team name',
            autofocus: !_isEdit,
            errorText: _error,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          const _Caption('Colour'),
          const SizedBox(height: 10),
          ColorPickerField(
            valueHex: _color,
            onChanged: (v) => setState(() => _color = v),
          ),
          const SizedBox(height: 16),
          const _Caption('Leader'),
          const SizedBox(height: 8),
          peopleAsync.when(
            data: (people) {
              final leader = _leaderId == null
                  ? null
                  : people.where((p) => p.id == _leaderId).firstOrNull;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (leader != null)
                    KeelChip(
                      label: 'Lead: ${leader.name}',
                      color: context.accent,
                      onTap: () => _pickLeader(people),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: () => _pickLeader(people),
                      icon: const Icon(Icons.flag_outlined, size: 18),
                      label: const Text('Choose a leader'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.accent,
                        side: BorderSide(color: context.line),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: () async {
                      await showNewPersonSheet(context, orgId: widget.orgId);
                    },
                    icon: const Icon(Icons.person_add_outlined, size: 18),
                    label: const Text('Or create a person first'),
                    style: TextButton.styleFrom(
                      foregroundColor: context.accent,
                    ),
                  ),
                ],
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 8),
          const _Caption('Members'),
          const SizedBox(height: 8),
          peopleAsync.when(
            data: (people) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in people)
                  FilterChip(
                    label: Text(p.name),
                    selected: _members.contains(p.id) || p.id == _leaderId,
                    selectedColor: KeelTokens.tint14(
                      context.accent,
                      context.card,
                    ),
                    checkmarkColor: context.accent,
                    backgroundColor: context.card,
                    side: BorderSide(color: context.line),
                    onSelected: p.id == _leaderId
                        ? null
                        : (v) => setState(() {
                            if (v) {
                              _members.add(p.id);
                            } else {
                              _members.remove(p.id);
                            }
                          }),
                  ),
              ],
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          if (_isEdit) ...[
            const SizedBox(height: 16),
            const _Caption('Main task'),
            const SizedBox(height: 8),
            tasksAsync.when(
              data: (tasks) {
                final teamTasks = tasks
                    .where((t) => t.teamId == widget.existing!.id)
                    .toList();
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('No main task'),
                      selected: _mainTaskId == null,
                      selectedColor: context.accent,
                      labelStyle: TextStyle(
                        color: _mainTaskId == null ? Colors.white : context.ink,
                        fontWeight: FontWeight.w600,
                      ),
                      backgroundColor: context.card,
                      side: BorderSide(color: context.line),
                      onSelected: (_) => setState(() => _mainTaskId = null),
                    ),
                    for (final t in teamTasks)
                      ChoiceChip(
                        label: Text(t.title),
                        selected: _mainTaskId == t.id,
                        selectedColor: context.accent,
                        labelStyle: TextStyle(
                          color: _mainTaskId == t.id
                              ? Colors.white
                              : context.ink,
                          fontWeight: FontWeight.w600,
                        ),
                        backgroundColor: context.card,
                        side: BorderSide(color: context.line),
                        onSelected: (_) => setState(() => _mainTaskId = t.id),
                      ),
                  ],
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickLeader(List<Person> people) async {
    final id = await pickLeader(
      context,
      orgId: widget.orgId,
      candidates: people,
      currentLeaderId: _leaderId,
    );
    if (id != null) {
      setState(() {
        _leaderId = id;
        _members.add(id);
      });
    }
  }
}

// ---------------------------------------------------------------------------
// Task detail sheet — edit everything, assignees, sub-todos with reorder.
// ---------------------------------------------------------------------------

Future<void> showTaskDetailSheet(
  BuildContext context, {
  required Task task,
  required String orgId,
}) {
  return showKeelSheet<void>(
    context,
    large: true,
    builder: (context, c) =>
        _TaskDetailSheet(task: task, orgId: orgId, scrollController: c),
  );
}

class _TaskDetailSheet extends ConsumerStatefulWidget {
  final Task task;
  final String orgId;
  final ScrollController scrollController;
  const _TaskDetailSheet({
    required this.task,
    required this.orgId,
    required this.scrollController,
  });

  @override
  ConsumerState<_TaskDetailSheet> createState() => _TaskDetailSheetState();
}

class _TaskDetailSheetState extends ConsumerState<_TaskDetailSheet> {
  late final TextEditingController _title;
  late final TextEditingController _notes;
  late final TextEditingController _sub;
  late DateTime? _due;
  late String _priority;
  late String? _teamId;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.task.title);
    _notes = TextEditingController(text: widget.task.notes);
    _sub = TextEditingController();
    _due = widget.task.dueDate;
    _priority = widget.task.priority;
    _teamId = widget.task.teamId;
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _sub.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final repo = ref.read(repositoryProvider);
    await repo.updateTask(
      widget.task.id,
      title: _title.text,
      notes: _notes.text,
      dueDate: Value(_due),
      priority: _priority,
      teamId: Value(_teamId),
    );
    // A changed due date moves (or removes) the reminders (1.3.0).
    unawaited(NotificationService.syncForRef(ref));
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final repo = ref.read(repositoryProvider);
    // Settings captured now: the undo closure runs after this sheet
    // is popped, so it must not touch ref.
    final settings = ref.read(settingsProvider);
    final snap = await repo.deleteTask(widget.task.id);
    unawaited(NotificationService.cancelTaskReminders(widget.task.id));
    if (mounted) {
      Navigator.of(context).pop();
      showUndoSnack(
        context,
        label: 'Task deleted',
        onUndo: () async {
          await repo.restoreSnapshot(snap);
          unawaited(
            NotificationService.syncTaskReminders(
              repo: repo,
              orgId: widget.task.orgId,
              on: settings.remindersOn,
              hour: settings.digestHour,
              minute: settings.digestMinute,
            ),
          );
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(repositoryProvider);
    final teamsAsync = ref.watch(teamsProvider(widget.orgId));
    final assigneesAsync = ref.watch(taskAssigneesProvider(widget.task.id));
    final subsAsync = ref.watch(subTodosProvider(widget.task.id));
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return SheetScaffold(
      title: 'Task',
      buttonLabel: 'Save changes',
      onButton: _save,
      scrollController: widget.scrollController,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              KeelCheckbox(
                value: widget.task.isDone,
                onChanged: (done) => repo.setTaskDone(widget.task.id, done),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: TextField(
                  controller: _title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: const InputDecoration(border: InputBorder.none),
                ),
              ),
            ],
          ),
          KeelTextField(controller: _notes, hint: 'Notes', maxLines: 3),
          const SizedBox(height: 16),
          const _Caption('Due date'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final (label, date) in <(String, DateTime?)>[
                ('Today', today),
                ('Tomorrow', today.add(const Duration(days: 1))),
                ('No date', null),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected:
                      _due == date ||
                      (date != null &&
                          _due != null &&
                          _due!.difference(date).inDays == 0),
                  selectedColor: context.accent,
                  labelStyle: TextStyle(
                    color:
                        (_due == date ||
                            (date != null &&
                                _due != null &&
                                _due!.difference(date).inDays == 0))
                        ? Colors.white
                        : context.ink,
                    fontWeight: FontWeight.w600,
                  ),
                  backgroundColor: context.card,
                  side: BorderSide(color: context.line),
                  onSelected: (_) => setState(() => _due = date),
                ),
              ActionChip(
                label: Text(
                  _due == null
                      ? 'Pick a date'
                      : '${_due!.day}/${_due!.month}/${_due!.year}',
                ),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _due ?? today,
                    firstDate: today.subtract(const Duration(days: 365)),
                    lastDate: today.add(const Duration(days: 365 * 5)),
                  );
                  if (picked != null) setState(() => _due = picked);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _Caption('Priority'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final p in ['none', 'low', 'medium', 'high'])
                ChoiceChip(
                  label: Text(p[0].toUpperCase() + p.substring(1)),
                  selected: _priority == p,
                  selectedColor: context.accent,
                  labelStyle: TextStyle(
                    color: _priority == p ? Colors.white : context.ink,
                    fontWeight: FontWeight.w600,
                  ),
                  backgroundColor: context.card,
                  side: BorderSide(color: context.line),
                  onSelected: (_) => setState(() => _priority = p),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const _Caption('Team'),
          const SizedBox(height: 8),
          teamsAsync.when(
            data: (teams) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('No team'),
                  selected: _teamId == null,
                  selectedColor: context.accent,
                  labelStyle: TextStyle(
                    color: _teamId == null ? Colors.white : context.ink,
                    fontWeight: FontWeight.w600,
                  ),
                  backgroundColor: context.card,
                  side: BorderSide(color: context.line),
                  onSelected: (_) => setState(() => _teamId = null),
                ),
                for (final t in teams)
                  ChoiceChip(
                    label: Text(t.name),
                    selected: _teamId == t.id,
                    selectedColor: KeelTokens.colorFromHex(t.colorHex),
                    labelStyle: TextStyle(
                      color: _teamId == t.id ? Colors.white : context.ink,
                      fontWeight: FontWeight.w600,
                    ),
                    backgroundColor: context.card,
                    side: BorderSide(color: context.line),
                    onSelected: (_) => setState(() => _teamId = t.id),
                  ),
              ],
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const _Caption('Assignees'),
              TextButton(
                onPressed: () async {
                  final current = assigneesAsync.value ?? const [];
                  final ids = await pickPeople(
                    context,
                    orgId: widget.orgId,
                    selected: current.map((p) => p.id).toList(),
                    title: 'Assignees',
                  );
                  if (ids == null) return;
                  final old = current.map((p) => p.id).toSet();
                  for (final id in ids) {
                    if (!old.contains(id)) {
                      await repo.assignPersonToTask(widget.task.id, id);
                    }
                  }
                  for (final id in old) {
                    if (!ids.contains(id)) {
                      await repo.unassignPersonFromTask(widget.task.id, id);
                    }
                  }
                },
                child: Text('Edit', style: TextStyle(color: context.accent)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          assigneesAsync.when(
            data: (people) => people.isEmpty
                ? Text(
                    'Nobody assigned yet.',
                    style: TextStyle(color: context.muted, fontSize: 13),
                  )
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final p in people)
                        KeelChip(label: p.name, color: context.accent),
                    ],
                  ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 16),
          const _Caption('Sub-tasks'),
          const SizedBox(height: 8),
          subsAsync.when(
            data: (subs) => subs.isEmpty
                ? Text(
                    'No sub-tasks yet.',
                    style: TextStyle(color: context.muted, fontSize: 13),
                  )
                : SizedBox(
                    height: (subs.length * 52).clamp(52, 260).toDouble(),
                    child: ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: subs.length,
                      onReorder: (oldIndex, newIndex) async {
                        final ids = subs.map((s) => s.id).toList();
                        if (newIndex > oldIndex) newIndex -= 1;
                        final moved = ids.removeAt(oldIndex);
                        ids.insert(newIndex, moved);
                        await repo.reorderSubTodos(widget.task.id, ids);
                      },
                      itemBuilder: (context, i) {
                        final s = subs[i];
                        return Row(
                          key: ValueKey(s.id),
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
                                  decoration: s.isDone
                                      ? TextDecoration.lineThrough
                                      : null,
                                  color: s.isDone ? context.muted : context.ink,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              color: context.muted,
                              onPressed: () => repo.deleteSubTodo(s.id),
                              tooltip: 'Delete sub-task',
                            ),
                            const Icon(Icons.drag_handle, size: 20),
                          ],
                        );
                      },
                    ),
                  ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _sub,
                  decoration: const InputDecoration(hintText: 'Add a sub-task'),
                  onSubmitted: (_) => _addSub(),
                ),
              ),
              IconButton(
                icon: Icon(Icons.add_circle, color: context.accent, size: 28),
                onPressed: _addSub,
                tooltip: 'Add sub-task',
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline, size: 20),
              label: const Text('Delete task'),
              style: OutlinedButton.styleFrom(
                foregroundColor: KeelTokens.overdue,
                side: const BorderSide(color: KeelTokens.overdue),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(KeelTokens.radiusButton),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addSub() async {
    final t = _sub.text.trim();
    if (t.isEmpty) return;
    await ref.read(repositoryProvider).addSubTodo(widget.task.id, t);
    _sub.clear();
  }
}

// ---------------------------------------------------------------------------
// Team overview sheet — tap a team card.
// ---------------------------------------------------------------------------

Future<void> showTeamOverviewSheet(
  BuildContext context, {
  required Team team,
  required String orgId,
  required VoidCallback onOpenTeamPage,
}) {
  return showKeelDialogSheet<void>(
    context,
    child: _TeamOverviewSheet(
      team: team,
      orgId: orgId,
      onOpenTeamPage: onOpenTeamPage,
    ),
  );
}

class _TeamOverviewSheet extends ConsumerWidget {
  final Team team;
  final String orgId;
  final VoidCallback onOpenTeamPage;
  const _TeamOverviewSheet({
    required this.team,
    required this.orgId,
    required this.onOpenTeamPage,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = KeelTokens.colorFromHex(team.colorHex);
    final membersAsync = ref.watch(teamMembersProvider(team.id));
    final tasksAsync = ref.watch(tasksProvider(orgId));
    final teamTasks = (tasksAsync.value ?? const [])
        .where((t) => t.teamId == team.id)
        .toList();
    final done = teamTasks.where((t) => t.isDone).length;
    final pct = teamTasks.isEmpty ? 0 : (done / teamTasks.length * 100).round();
    final mainTask = team.mainTaskId == null
        ? null
        : teamTasks.where((t) => t.id == team.mainTaskId).firstOrNull;
    final leaderAsync = ref.watch(teamsProvider(orgId));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.group_outlined, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      team.name,
                      style: Theme.of(
                        context,
                      ).textTheme.displayMedium?.copyWith(fontSize: 24),
                    ),
                    FutureBuilder<Person?>(
                      future: ref
                          .read(repositoryProvider)
                          .getPerson(team.leaderPersonId),
                      builder: (context, snap) => Text(
                        'Led by ${snap.data?.name ?? '…'}',
                        style: TextStyle(color: context.muted, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              StatTile(
                value: '${membersAsync.value?.length ?? 0}',
                label: 'People',
              ),
              const SizedBox(width: 8),
              StatTile(value: '${teamTasks.length}', label: 'Tasks'),
              const SizedBox(width: 8),
              StatTile(value: '$pct%', label: 'Done'),
            ],
          ),
          const SizedBox(height: 12),
          KeelCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Main task',
                  style: TextStyle(
                    color: context.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  mainTask?.title ?? 'No main task set',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                ProgressBar(
                  value: teamTasks.isEmpty ? 0 : done / teamTasks.length,
                  color: color,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          membersAsync.when(
            data: (members) => members.isEmpty
                ? const SizedBox.shrink()
                : KeelCard(
                    child: Row(
                      children: [
                        AvatarStack(
                          members: members
                              .map((p) => (person: p, color: color))
                              .toList(),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            members
                                .map((p) => p.name.split(' ').first)
                                .join(', '),
                            style: TextStyle(
                              color: context.muted,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 16),
          KeelButton(
            label: 'Open team page',
            background: color,
            foreground: Colors.white,
            icon: Icons.chevron_right,
            onPressed: () {
              Navigator.of(context).pop();
              onOpenTeamPage();
            },
          ),
          // Keep leaderAsync referenced so the provider stays warm; no UI.
          ...[if (leaderAsync is AsyncLoading) const SizedBox.shrink()],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Task overview sheet — tap a task tile (except its arrow).
// Read-only summary + quick actions. The arrow opens the full task page.
// ---------------------------------------------------------------------------

Future<void> showTaskOverviewSheet(
  BuildContext context, {
  required Task task,
  required String orgId,
  required ValueChanged<Team> onOpenTeamPage,
}) {
  return showKeelDialogSheet<void>(
    context,
    child: _TaskOverviewSheet(
      taskId: task.id,
      orgId: orgId,
      onOpenTeamPage: onOpenTeamPage,
    ),
  );
}

class _TaskOverviewSheet extends ConsumerWidget {
  final String taskId;
  final String orgId;
  final ValueChanged<Team> onOpenTeamPage;
  const _TaskOverviewSheet({
    required this.taskId,
    required this.orgId,
    required this.onOpenTeamPage,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final task = ref.watch(taskProvider(taskId)).value;
    if (task == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 18),
        child: Text('This task no longer exists.'),
      );
    }
    final repo = ref.read(repositoryProvider);
    final teams = ref.watch(teamsProvider(orgId)).value ?? const [];
    final team = teams.where((t) => t.id == task.teamId).firstOrNull;
    final assigneesAsync = ref.watch(taskAssigneesProvider(task.id));
    final subsAsync = ref.watch(subTodosProvider(task.id));
    final overdue = isOverdue(task);
    final dueSoon = isDueSoon(task);
    final dueText = task.dueDate == null
        ? 'No due date'
        : '${dueLabel(task.dueDate, isDone: task.isDone)} · '
              '${task.dueDate!.day}/${task.dueDate!.month}/${task.dueDate!.year}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
                  await repo.setTaskDone(task.id, done);
                  unawaited(NotificationService.syncForRef(ref));
                },
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  task.title,
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                    height: 1.1,
                    color: context.ink,
                    decoration: task.isDone ? TextDecoration.lineThrough : null,
                    decorationColor: context.muted,
                  ),
                ),
              ),
              if (task.priority != 'none') ...[
                const SizedBox(width: 8),
                _OverviewPriorityTag(priority: task.priority),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.event_outlined,
                size: 18,
                color: overdue
                    ? KeelTokens.overdue
                    : dueSoon
                    ? KeelTokens.colorFromHex('#B7791F')
                    : context.muted,
              ),
              const SizedBox(width: 6),
              // Flexible: after Complete the row also carries the
              // "Done <date>" text, which together with the due text
              // overflowed a 390px screen (caught by widget test).
              Flexible(
                child: Text(
                  dueText,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: overdue ? FontWeight.w700 : FontWeight.w400,
                    color: overdue
                        ? KeelTokens.overdue
                        : dueSoon
                        ? KeelTokens.colorFromHex('#B7791F')
                        : context.muted,
                  ),
                ),
              ),
              if (task.completedAt != null) ...[
                const SizedBox(width: 12),
                Text(
                  'Done ${task.completedAt!.day}/${task.completedAt!.month}/${task.completedAt!.year}',
                  style: TextStyle(color: context.muted, fontSize: 13),
                ),
              ],
            ],
          ),
          if (task.notes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              task.notes,
              style: TextStyle(color: context.muted, fontSize: 14, height: 1.4),
            ),
          ],
          subsAsync.when(
            data: (subs) {
              if (subs.isEmpty) return const SizedBox.shrink();
              final doneCount = subs.where((s) => s.isDone).length;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 14),
                  Text(
                    '$doneCount of ${subs.length} sub-tasks done',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: context.muted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ProgressBar(
                    value: doneCount / subs.length,
                    color: context.accent,
                  ),
                  const SizedBox(height: 6),
                  for (final s in subs)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          KeelCheckbox(
                            value: s.isDone,
                            size: 20,
                            onChanged: (done) => repo.toggleSubTodo(s.id, done),
                          ),
                          Expanded(
                            child: Text(
                              s.title,
                              style: TextStyle(
                                fontSize: 14,
                                color: s.isDone ? context.muted : context.ink,
                                decoration: s.isDone
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 14),
          Text(
            'Assigned to',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: context.muted,
            ),
          ),
          const SizedBox(height: 6),
          assigneesAsync.when(
            data: (people) => people.isEmpty
                ? Text(
                    'Nobody assigned yet.',
                    style: TextStyle(color: context.muted, fontSize: 13),
                  )
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final p in people)
                        KeelChip(label: p.name, color: context.accent),
                    ],
                  ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 14),
          if (team != null)
            KeelButton(
              label: 'Team: ${team.name}',
              background: KeelTokens.colorFromHex(team.colorHex),
              foreground: Colors.white,
              icon: Icons.group_outlined,
              onPressed: () {
                Navigator.of(context).pop();
                onOpenTeamPage(team);
              },
            )
          else
            Text(
              'No team assigned.',
              style: TextStyle(color: context.muted, fontSize: 13),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _SheetAction(
                  icon: task.isDone
                      ? Icons.replay_outlined
                      : Icons.check_circle_outline,
                  label: task.isDone ? 'Reopen' : 'Complete',
                  color: KeelTokens.success,
                  onTap: () async {
                    await repo.setTaskDone(task.id, !task.isDone);
                    unawaited(NotificationService.syncForRef(ref));
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SheetAction(
                  icon: Icons.edit_outlined,
                  label: 'Edit',
                  color: context.ink,
                  onTap: () =>
                      showTaskDetailSheet(context, task: task, orgId: orgId),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SheetAction(
                  icon: Icons.delete_outline,
                  label: 'Delete',
                  color: KeelTokens.overdue,
                  onTap: () async {
                    final settings = ref.read(settingsProvider);
                    final snap = await repo.deleteTask(task.id);
                    unawaited(NotificationService.cancelTaskReminders(task.id));
                    if (!context.mounted) return;
                    // Snackbar first: this sheet's context is unmounted
                    // after the pop below, so it could not show one.
                    showUndoSnack(
                      context,
                      label: 'Task deleted',
                      onUndo: () async {
                        await repo.restoreSnapshot(snap);
                        unawaited(
                          NotificationService.syncTaskReminders(
                            repo: repo,
                            orgId: orgId,
                            on: settings.remindersOn,
                            hour: settings.digestHour,
                            minute: settings.digestMinute,
                          ),
                        );
                      },
                    );
                    if (context.mounted) Navigator.of(context).pop();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OverviewPriorityTag extends StatelessWidget {
  final String priority;
  const _OverviewPriorityTag({required this.priority});

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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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

/// One quick-action button inside an overview sheet: tinted tile,
/// icon + label, 48dp tall, radius 18 (kit buttons).
class _SheetAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: KeelTokens.tint14(color, context.card),
            borderRadius: BorderRadius.circular(KeelTokens.radiusButton),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 19, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Person overview sheet — tap a person tile (except its arrow).
// Avatar + name/role/teams on the left; Call on the right with Message
// (WhatsApp) directly below it. The arrow opens the full person page.
// ---------------------------------------------------------------------------

/// WhatsApp deep link for a phone number: digits only, or null when the
/// number has no digits at all. The number is validated here so no
/// user-typed text can reach the URL unchecked.
Uri? whatsappUriFor(String number) {
  final digits = number.replaceAll(RegExp(r'[^0-9+]'), '');
  // wa.me wants digits only (no leading +).
  final clean = digits.replaceAll('+', '');
  if (clean.isEmpty) return null;
  return Uri.parse('https://wa.me/$clean');
}

Future<void> showPersonOverviewSheet(
  BuildContext context, {
  required Person person,
  required String orgId,
}) {
  return showKeelDialogSheet<void>(
    context,
    child: _PersonOverviewSheet(person: person, orgId: orgId),
  );
}

class _PersonOverviewSheet extends ConsumerWidget {
  final Person person;
  final String orgId;
  const _PersonOverviewSheet({required this.person, required this.orgId});

  Future<void> _launch(BuildContext context, Uri uri, String label) async {
    // Launch directly and check the result instead of gating on
    // canLaunchUrl, which false-negatives on Android 11+ without a
    // matching <queries> declaration (see AndroidManifest).
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
  Widget build(BuildContext context, WidgetRef ref) {
    final teams = ref.watch(personTeamsProvider(person.id)).value ?? const [];
    final ringColor = firstTeamColor(teams);
    final repo = ref.read(repositoryProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: FutureBuilder<List<PersonPhone>>(
        future: repo.getPhones(person.id),
        builder: (context, snap) {
          final phones = snap.data ?? const [];
          final firstPhone = phones.isEmpty ? null : phones.first;
          final waUri = firstPhone == null
              ? null
              : whatsappUriFor(firstPhone.number);
          final hasPhone = firstPhone != null;

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  PersonAvatar(person: person, ringColor: ringColor, size: 64),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          person.name,
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                            height: 1.1,
                            color: context.ink,
                          ),
                        ),
                        if (person.roleTitle.isNotEmpty)
                          Text(
                            person.roleTitle,
                            style: TextStyle(
                              color: context.muted,
                              fontSize: 13,
                            ),
                          ),
                        if (hasPhone)
                          Text(
                            firstPhone.number,
                            style: TextStyle(
                              color: context.muted,
                              fontSize: 13,
                            ),
                          ),
                        const SizedBox(height: 6),
                        if (teams.isEmpty)
                          Text(
                            'No team',
                            style: TextStyle(
                              color: context.muted,
                              fontSize: 12,
                            ),
                          )
                        else
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              for (final t in teams)
                                KeelChip(
                                  label: t.name,
                                  color: KeelTokens.colorFromHex(t.colorHex),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Right-hand action column: Call on top, Message
                  // (WhatsApp) directly below it — the most reachable
                  // spot for the right thumb.
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ContactActionButton(
                        icon: Icons.phone_outlined,
                        label: 'Call',
                        color: context.accent,
                        enabled: hasPhone,
                        onTap: hasPhone
                            ? () => _launch(
                                context,
                                Uri.parse('tel:${firstPhone.number}'),
                                'the dialler',
                              )
                            : null,
                      ),
                      const SizedBox(height: 8),
                      _ContactActionButton(
                        icon: Icons.message_outlined,
                        label: 'Message',
                        color: KeelTokens.success,
                        enabled: waUri != null,
                        onTap: waUri == null
                            ? null
                            : () => _launch(context, waUri, 'WhatsApp'),
                      ),
                    ],
                  ),
                ],
              ),
              if (!hasPhone) ...[
                const SizedBox(height: 10),
                Text(
                  'No phone number — add one on the full person page.',
                  style: TextStyle(color: context.muted, fontSize: 13),
                ),
              ] else if (phones.length > 1) ...[
                const SizedBox(height: 10),
                Text(
                  '+${phones.length - 1} more number${phones.length - 1 == 1 ? '' : 's'} on the full person page.',
                  style: TextStyle(color: context.muted, fontSize: 13),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// One stacked Call/Message button in the person overview sheet:
/// solid colour, white icon + label, 48dp tall.
class _ContactActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool enabled;
  final VoidCallback? onTap;
  const _ContactActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Semantics(
        button: true,
        label: enabled ? label : '$label (unavailable)',
        child: GestureDetector(
          onTap: enabled ? onTap : null,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 92,
            height: 48,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 19, color: Colors.white),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Organization switcher sheet — tap the Home header.
// ---------------------------------------------------------------------------

/// New Organization sheet (1.3.0, DECISIONS.md 40): name + a type
/// picker (Studio, Company, Club, Family, Other) in the same
/// uncluttered slide-up pattern as task/team creation — no long
/// form. Used from Settings and from the org switcher. Onboarding
/// keeps its own flow and is untouched. Returns the created org, or
/// null if cancelled, and makes the new org active.
Future<Organization?> showNewOrganizationSheet(BuildContext context) {
  return showKeelSheet<Organization>(
    context,
    builder: (context, c) => _NewOrganizationSheet(scrollController: c),
  );
}

class _NewOrganizationSheet extends ConsumerStatefulWidget {
  final ScrollController scrollController;
  const _NewOrganizationSheet({required this.scrollController});

  @override
  ConsumerState<_NewOrganizationSheet> createState() =>
      _NewOrganizationSheetState();
}

class _NewOrganizationSheetState extends ConsumerState<_NewOrganizationSheet> {
  final _name = TextEditingController();
  String _kind = 'Studio';
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Give the organization a name.');
      return;
    }
    final repo = ref.read(repositoryProvider);
    final settings = ref.read(settingsProvider);
    final org = await repo.createOrganization(name: _name.text, kind: _kind);
    await settings.setActiveOrg(org.id);
    if (mounted) {
      Navigator.of(context).pop(org);
      showKeelSnack(context, 'Organization created');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      title: 'New organization',
      buttonLabel: 'Create organization',
      onButton: _create,
      scrollController: widget.scrollController,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KeelTextField(
            controller: _name,
            label: 'Name',
            hint: 'Organization name',
            autofocus: true,
            errorText: _error,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          const _Caption('Type'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final kind in [
                'Studio',
                'Company',
                'Club',
                'Family',
                'Other',
              ])
                ChoiceChip(
                  label: Text(kind),
                  selected: _kind == kind,
                  selectedColor: context.accent,
                  labelStyle: TextStyle(
                    color: _kind == kind ? Colors.white : context.ink,
                    fontWeight: FontWeight.w600,
                  ),
                  backgroundColor: context.card,
                  side: BorderSide(color: context.line),
                  onSelected: (_) => setState(() => _kind = kind),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> showOrgSwitcherSheet(BuildContext context) {
  return showKeelDialogSheet<void>(context, child: const _OrgSwitcherSheet());
}

class _OrgSwitcherSheet extends ConsumerWidget {
  const _OrgSwitcherSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orgsAsync = ref.watch(organizationsProvider);
    final settings = ref.watch(settingsProvider);
    final activeOrgAsync = ref.watch(activeOrgProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Switch organization',
            style: Theme.of(
              context,
            ).textTheme.displayMedium?.copyWith(fontSize: 24),
          ),
          const SizedBox(height: 12),
          orgsAsync.when(
            data: (orgs) => Column(
              children: [
                for (final org in orgs)
                  KeelCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    onTap: () async {
                      await settings.setActiveOrg(org.id);
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: KeelTokens.tint14(
                              context.accent,
                              context.card,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.business_outlined,
                            color: context.accent,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                org.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                org.kind,
                                style: TextStyle(
                                  color: context.muted,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (activeOrgAsync.value == org.id)
                          Icon(Icons.check_circle, color: context.accent),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      // 1.3.0: name + type picker in a proper sheet,
                      // not a bare name-only popup. The new org is
                      // made active by the sheet itself; closing the
                      // switcher too when one was actually created.
                      final created = await showNewOrganizationSheet(context);
                      if (created != null && context.mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                    icon: const Icon(Icons.add, size: 20),
                    label: const Text('Add organization'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.accent,
                      side: BorderSide(color: context.line),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          KeelTokens.radiusButton,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                  ),
                ),
              ],
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) =>
                const Center(child: Text('Could not load organizations.')),
          ),
        ],
      ),
    );
  }
}
