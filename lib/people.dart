import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

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

void openPersonPage(
  BuildContext context, {
  required Person person,
  required String orgId,
}) {
  Navigator.of(context).push(
    PageRouteBuilder(
      pageBuilder: (_, _, _) => PersonPage(personId: person.id, orgId: orgId),
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

/// People tab: live search (name, role, phone, email, team), contacts list.
class PeopleScreen extends ConsumerStatefulWidget {
  const PeopleScreen({super.key});

  @override
  ConsumerState<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends ConsumerState<PeopleScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orgIdAsync = ref.watch(activeOrgProvider);
    final scrollController = ref.watch(tabScrollControllersProvider)[3];

    return orgIdAsync.when(
      data: (orgId) {
        if (orgId == null) return const SizedBox.shrink();
        final peopleAsync = ref.watch(peopleProvider(orgId));
        final people = peopleAsync.value ?? const [];
        final filteredAsync =
            ref.watch(filteredPeopleProvider((orgId: orgId, query: _query)));
        final shown = filteredAsync.value ?? const [];
        final filtering = filteredAsync is AsyncLoading;

        // Lazy list: 200+ people build only their on-screen rows.
        return CustomScrollView(
          controller: scrollController,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 54, 18, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${people.length} contacts',
                                style: TextStyle(
                                  color: context.muted,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'People',
                                style: Theme.of(context).textTheme.displayLarge,
                              ),
                            ],
                          ),
                        ),
                        KeelAddIconButton(
                          onPressed: () =>
                              showNewPersonSheet(context, orgId: orgId),
                          tooltip: 'Add a person',
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _search,
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        hintText: 'Search people',
                        prefixIcon: Icon(
                          Icons.search,
                          color: context.muted,
                          size: 19,
                        ),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () {
                                  _search.clear();
                                  setState(() => _query = '');
                                },
                                tooltip: 'Clear search',
                              ),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                ),
              ),
            ),
            if (people.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 130),
                sliver: SliverToBoxAdapter(
                  child: EmptyState(
                    icon: Icons.person_add_outlined,
                    title: 'No people yet',
                    body:
                        'Add the people you manage — their teams, tasks and contact details live here.',
                    actionLabel: 'Add a person',
                    onAction: () => showNewPersonSheet(context, orgId: orgId),
                  ),
                ),
              )
            else if (filtering)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: 32),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (shown.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 130),
                sliver: SliverToBoxAdapter(
                  child: EmptyState(
                    icon: Icons.person_search_outlined,
                    title: 'No matches',
                    body:
                        'No one matches "$_query". Try a name, role, phone, email or team.',
                    actionLabel: 'Add a person',
                    onAction: () => showNewPersonSheet(context, orgId: orgId),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 130),
                sliver: SliverList.builder(
                  itemCount: shown.length,
                  itemBuilder: (context, i) {
                    final p = shown[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _PersonRow(person: p, orgId: orgId),
                    );
                  },
                ),
              ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const Center(child: Text('Could not load people.')),
    );
  }
}

class _PersonRow extends ConsumerWidget {
  final Person person;
  final String orgId;
  const _PersonRow({required this.person, required this.orgId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teams = ref.watch(personTeamsProvider(person.id)).value ?? const [];
    return KeelCard(
      onTap: () => showPersonOverviewSheet(context, person: person, orgId: orgId),
      semanticLabel: 'Person: ${person.name}',
      child: Row(
        children: [
          PersonAvatar(person: person, ringColor: firstTeamColor(teams), size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(person.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                if (person.roleTitle.isNotEmpty)
                  Text(person.roleTitle, style: TextStyle(color: context.muted, fontSize: 13)),
                const SizedBox(height: 4),
                if (teams.isEmpty)
                  Text('No team', style: TextStyle(color: context.muted, fontSize: 12))
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
          // Arrow: opens the full person page. The card tap (handled by
          // KeelCard) opens the overview sheet instead.
          Semantics(
            button: true,
            label: 'Open full profile for ${person.name}',
            child: GestureDetector(
              onTap: () => openPersonPage(context, person: person, orgId: orgId),
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: KeelTokens.tint14(context.accent, context.card),
                  borderRadius: BorderRadius.circular(14),
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
    );
  }
}

/// Person card: 96 avatar + camera badge, Call/Email/Message intents,
/// unlimited phones/emails, team chips, assigned tasks, notes.
class PersonPage extends ConsumerStatefulWidget {
  final String personId;
  final String orgId;
  const PersonPage({super.key, required this.personId, required this.orgId});

  @override
  ConsumerState<PersonPage> createState() => _PersonPageState();
}

class _PersonPageState extends ConsumerState<PersonPage> {
  final _photo = PhotoService();

  Future<void> _pickPhoto(ImageSource source) async {
    final path = await _photo.pickPhoto(
      source: source,
      personId: widget.personId,
    );
    if (path == null) {
      if (mounted) showKeelSnack(context, 'That photo could not be used.');
      return;
    }
    final repo = ref.read(repositoryProvider);
    final person = await repo.getPerson(widget.personId);
    final old = person?.photoPath;
    await repo.updatePerson(widget.personId, photoPath: Value(path));
    if (old != null && old != path) await _photo.deletePhoto(old);
  }

  Future<void> _launch(String scheme, String value, String label) async {
    final uri = Uri.parse('$scheme:$value');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (mounted) {
      showKeelSnack(context, 'Could not open $label.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final personAsync = ref.watch(peopleProvider(widget.orgId));
    final person = (personAsync.value ?? const [])
        .where((p) => p.id == widget.personId)
        .firstOrNull;
    if (person == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Person')),
        body: const Center(child: Text('This person no longer exists.')),
      );
    }
    final teams = ref.watch(personTeamsProvider(person.id)).value ?? const [];
    final ringColor = firstTeamColor(teams);
    final phones = ref.watch(watchPhonesProvider(person.id)).value ?? const [];
    final emails = ref.watch(watchEmailsProvider(person.id)).value ?? const [];
    final assignedTasks =
        ref.watch(personTasksProvider(person.id)).value ?? const [];
    final allTeams = ref.watch(teamsProvider(widget.orgId)).value ?? const [];
    final repo = ref.read(repositoryProvider);

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.chevron_left, color: context.accent, size: 28),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Back to People',
        ),
        title: Text('People', style: TextStyle(color: context.accent, fontSize: 17)),
        centerTitle: false,
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_horiz, color: context.ink),
            tooltip: 'Person options',
            onSelected: (value) async {
              if (value == 'edit') {
                await _editPerson(context, ref, person);
              } else if (value == 'delete') {
                await _deletePerson(context, ref, person);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit person')),
              PopupMenuItem(
                value: 'delete',
                child: Text(
                  'Delete person',
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
          // Large avatar + camera badge.
          Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                PersonAvatar(person: person, ringColor: ringColor, size: 96),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: GestureDetector(
                    onTap: () => _photoSheet(context),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: context.ink,
                        border: Border.all(color: context.bg, width: 3),
                      ),
                      child: Icon(Icons.camera_alt, size: 15, color: context.bg),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              person.name,
              style: Theme.of(context).textTheme.displayMedium,
              textAlign: TextAlign.center,
            ),
          ),
          if (person.roleTitle.isNotEmpty)
            Center(
              child: Text(
                person.roleTitle,
                style: TextStyle(color: context.muted, fontSize: 14),
              ),
            ),
          const SizedBox(height: 16),
          // Call / Email / Message.
          Row(
            children: [
              _ActionButton(
                icon: Icons.phone_outlined,
                label: 'Call',
                onTap: phones.isEmpty
                    ? null
                    : () => _launch('tel', phones.first.number, 'the dialler'),
              ),
              const SizedBox(width: 10),
              _ActionButton(
                icon: Icons.mail_outline,
                label: 'Email',
                onTap: emails.isEmpty
                    ? null
                    : () => _launch('mailto', emails.first.address, 'email'),
              ),
              const SizedBox(width: 10),
              _ActionButton(
                icon: Icons.message_outlined,
                label: 'Message',
                onTap: phones.isEmpty
                    ? null
                    : () => _launch('sms', phones.first.number, 'messages'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Phones.
          KeelCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Column(
              children: [
                for (final ph in phones)
                  _ContactRow(
                    label: ph.label,
                    value: ph.number,
                    onTap: () => _launch('tel', ph.number, 'the dialler'),
                    onDelete: () => repo.deletePhone(ph.id),
                  ),
                _AddRow(
                  label: 'Add number',
                  onTap: () => _addContact(context, isPhone: true),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _SectionLabel('Email'),
          const SizedBox(height: 8),
          KeelCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Column(
              children: [
                for (final em in emails)
                  _ContactRow(
                    label: em.label,
                    value: em.address,
                    onTap: () => _launch('mailto', em.address, 'email'),
                    onDelete: () => repo.deleteEmail(em.id),
                  ),
                _AddRow(
                  label: 'Add email',
                  onTap: () => _addContact(context, isPhone: false),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _SectionLabel('Teams · colour follows the team'),
          const SizedBox(height: 8),
          KeelCard(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in teams)
                  KeelChip(
                    label: t.name,
                    color: KeelTokens.colorFromHex(t.colorHex),
                    leading: GestureDetector(
                      onTap: () => _removeFromTeam(context, ref, t.id),
                      child: const Icon(Icons.close, size: 13, color: Colors.white),
                    ),
                  ),
                ActionChip(
                  label: const Text('+ Add to team'),
                  onPressed: () async {
                    final notIn = allTeams
                        .where((t) => !teams.any((x) => x.id == t.id))
                        .toList();
                    if (notIn.isEmpty) {
                      showKeelSnack(context, 'Already in every team.');
                      return;
                    }
                    final chosen = await pickTeam(context, orgId: widget.orgId);
                    if (chosen != null) {
                      await repo.addTeamMember(chosen.id, person.id);
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Assigned tasks (${assignedTasks.length})',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.muted),
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  final tasks = await repo.getTasks(widget.orgId);
                  if (!context.mounted) return;
                  final assignedIds = assignedTasks.map((t) => t.id).toSet();
                  final unassigned =
                      tasks.where((t) => !assignedIds.contains(t.id)).toList();
                  if (unassigned.isEmpty) {
                    showKeelSnack(context, 'No unassigned tasks to add.');
                    return;
                  }
                  if (!context.mounted) return;
                  final chosen = await showDialog<Task>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Assign a task'),
                      content: SizedBox(
                        width: double.maxFinite,
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: unassigned.length,
                          itemBuilder: (context, i) {
                            final t = unassigned[i];
                            return ListTile(
                              title: Text(t.title),
                              onTap: () => Navigator.of(context).pop(t),
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
                  if (chosen != null) {
                    await repo.assignPersonToTask(chosen.id, person.id);
                  }
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Assign task'),
                style: TextButton.styleFrom(foregroundColor: context.accent),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (assignedTasks.isEmpty)
            KeelCard(
              child: Text(
                'No tasks assigned yet.',
                style: TextStyle(color: context.muted, fontSize: 14),
              ),
            )
          else
            for (final t in assignedTasks)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TaskCard(
                  task: t,
                  team: allTeams.where((x) => x.id == t.teamId).firstOrNull,
                  onTap: () => showTaskOverviewSheet(
                    context,
                    task: t,
                    orgId: widget.orgId,
                    onOpenTeamPage: (team) => openTeamPage(
                      context,
                      team: team,
                      orgId: widget.orgId,
                    ),
                  ),
                  onOpenPage: () =>
                      openTaskPage(context, task: t, orgId: widget.orgId),
                ),
              ),
          if (person.notes.isNotEmpty) ...[
            const SizedBox(height: 16),
            const _SectionLabel('Notes'),
            const SizedBox(height: 8),
            KeelCard(child: Text(person.notes, style: const TextStyle(fontSize: 15, height: 1.4))),
          ],
        ],
      ),
    );
  }

  Future<void> _photoSheet(BuildContext context) async {
    final choice = await showKeelDialogSheet<String>(
      context,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Photo', style: Theme.of(context).textTheme.displayMedium?.copyWith(fontSize: 22)),
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
            const SizedBox(height: 10),
            KeelButton(
              label: 'Remove photo',
              onPressed: () => Navigator.of(context).pop('remove'),
              secondary: true,
            ),
          ],
        ),
      ),
    );
    if (choice == 'camera') {
      await _pickPhoto(ImageSource.camera);
    } else if (choice == 'gallery') {
      await _pickPhoto(ImageSource.gallery);
    } else if (choice == 'remove') {
      final repo = ref.read(repositoryProvider);
      final person = await repo.getPerson(widget.personId);
      await repo.updatePerson(widget.personId, photoPath: const Value(null));
      if (person?.photoPath != null) {
        await _photo.deletePhoto(person!.photoPath);
      }
    }
  }

  Future<void> _addContact(BuildContext context, {required bool isPhone}) async {
    final value = TextEditingController();
    final label = TextEditingController(text: isPhone ? 'mobile' : 'work');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isPhone ? 'Add number' : 'Add email'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: label,
              decoration: const InputDecoration(hintText: 'Label (mobile, work…)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: value,
              autofocus: true,
              keyboardType: isPhone ? TextInputType.phone : TextInputType.emailAddress,
              decoration: InputDecoration(
                hintText: isPhone ? 'Phone number' : 'Email address',
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
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (saved != true || value.text.trim().isEmpty) {
      value.dispose();
      label.dispose();
      return;
    }
    final number = value.text;
    final lbl = label.text.trim();
    value.dispose();
    label.dispose();
    final repo = ref.read(repositoryProvider);
    if (isPhone) {
      await repo.addPhone(widget.personId, lbl, number);
    } else {
      await repo.addEmail(widget.personId, lbl, number);
    }
  }

  Future<void> _removeFromTeam(BuildContext context, WidgetRef ref, String teamId) async {
    final repo = ref.read(repositoryProvider);
    final team = await repo.getTeam(teamId);
    if (team == null) return;
    try {
      await repo.removeTeamMember(teamId, widget.personId);
    } on LeaderRemovalNeedsReplacement {
      final members = await repo.getTeamMembers(teamId);
      final candidates =
          members.where((p) => p.id != widget.personId).toList();
      if (!context.mounted) return;
      final replacement = await pickLeader(
        context,
        orgId: widget.orgId,
        candidates: candidates,
        title: 'Pick a new leader for ${team.name}',
      );
      if (replacement != null) {
        await repo.removeTeamMember(
          teamId,
          widget.personId,
          newLeaderId: replacement,
        );
      }
    }
  }

  Future<void> _editPerson(
    BuildContext context,
    WidgetRef ref,
    Person person,
  ) async {
    final name = TextEditingController(text: person.name);
    final role = TextEditingController(text: person.roleTitle);
    final notes = TextEditingController(text: person.notes);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit person'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(hintText: 'Name')),
              const SizedBox(height: 10),
              TextField(controller: role, decoration: const InputDecoration(hintText: 'Role')),
              const SizedBox(height: 10),
              TextField(
                controller: notes,
                maxLines: 3,
                decoration: const InputDecoration(hintText: 'Notes'),
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
    );
    if (saved == true && name.text.trim().isNotEmpty) {
      await ref.read(repositoryProvider).updatePerson(
            person.id,
            name: name.text,
            roleTitle: role.text,
            notes: notes.text,
          );
    }
    name.dispose();
    role.dispose();
    notes.dispose();
  }

  Future<void> _deletePerson(
    BuildContext context,
    WidgetRef ref,
    Person person,
  ) async {
    final repo = ref.read(repositoryProvider);
    // Rule 4: if they lead teams, pick replacements first.
    final ledTeams = (await repo.getTeams(widget.orgId))
        .where((t) => t.leaderPersonId == person.id)
        .toList();
    final replacements = <String, String>{};
    for (final team in ledTeams) {
      final members = await repo.getTeamMembers(team.id);
      final candidates = members.where((p) => p.id != person.id).toList();
      if (candidates.isEmpty) {
        if (context.mounted) {
          showKeelSnack(
            context,
            '${person.name} is the only member of ${team.name}. Add someone first.',
          );
        }
        return;
      }
      if (!context.mounted) return;
      final replacement = await pickLeader(
        context,
        orgId: widget.orgId,
        candidates: candidates,
        title: 'New leader for ${team.name}',
      );
      if (replacement == null) return;
      replacements[team.id] = replacement;
    }
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${person.name}?'),
        content: const Text(
          'Their assignments and team memberships will be removed. Teams and tasks stay.',
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
    final snap = await repo.deletePerson(
      person.id,
      leaderReplacements: replacements,
    );
    if (context.mounted) {
      Navigator.of(context).pop();
      showUndoSnack(
        context,
        label: 'Person deleted',
        onUndo: () => repo.restoreSnapshot(snap),
      );
    }
  }
}

// Providers for the person's contact lists (thin wrappers over repo streams).
final watchPhonesProvider =
    StreamProvider.family<List<PersonPhone>, String>((ref, personId) {
  return ref.watch(repositoryProvider).watchPhones(personId);
});

final watchEmailsProvider =
    StreamProvider.family<List<PersonEmail>, String>((ref, personId) {
  return ref.watch(repositoryProvider).watchEmails(personId);
});

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.muted),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _ActionButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: KeelCard(
          padding: const EdgeInsets.symmetric(vertical: 12),
          onTap: onTap,
          semanticLabel: onTap == null ? '$label (unavailable)' : label,
          child: Column(
            children: [
              Icon(icon, color: context.accent, size: 22),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: context.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _ContactRow({
    required this.label,
    required this.value,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(color: context.muted, fontSize: 12)),
                  Text(value, style: const TextStyle(fontSize: 15)),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            color: context.muted,
            onPressed: onDelete,
            tooltip: 'Delete $label',
          ),
        ],
      ),
    );
  }
}

class _AddRow extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _AddRow({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(Icons.add, size: 18, color: context.accent),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: context.accent,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
