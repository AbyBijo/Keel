import 'repo.dart';

/// Optional demo dataset behind Settings → "Load sample data".
/// The app itself always starts empty. Values copied from the UI kit
/// (Northwind Studio, 3 teams, 6 people, 6 tasks).
Future<void> loadSampleData(KeelRepository repo, String orgId) async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  final maya = await repo.createPerson(
    orgId: orgId,
    name: 'Maya Chen',
    roleTitle: 'Design Lead',
    phones: [(label: 'mobile', number: '+1 415 555 0142')],
    emails: [(label: 'work', address: 'maya@northwind.co')],
    notes: 'Prefers morning check-ins. Owns the brand voice.',
  );
  final leo = await repo.createPerson(
    orgId: orgId,
    name: 'Leo Park',
    roleTitle: 'Illustrator',
    phones: [(label: 'mobile', number: '+1 415 555 0127')],
    emails: [(label: 'work', address: 'leo@northwind.co')],
  );
  final sam = await repo.createPerson(
    orgId: orgId,
    name: 'Sam Ortiz',
    roleTitle: 'Tech Lead',
    phones: [(label: 'mobile', number: '+1 415 555 0163')],
    emails: [(label: 'work', address: 'sam@northwind.co')],
    notes: 'On call this week.',
  );
  final priya = await repo.createPerson(
    orgId: orgId,
    name: 'Priya Nair',
    roleTitle: 'Developer',
    phones: [(label: 'mobile', number: '+1 415 555 0171')],
    emails: [(label: 'work', address: 'priya@northwind.co')],
  );
  final dana = await repo.createPerson(
    orgId: orgId,
    name: 'Dana Reyes',
    roleTitle: 'Ops Lead',
    phones: [(label: 'mobile', number: '+1 415 555 0188')],
    emails: [(label: 'work', address: 'dana@northwind.co')],
    notes: 'Vendor contacts live in her sheet.',
  );
  final tom = await repo.createPerson(
    orgId: orgId,
    name: 'Tom Weber',
    roleTitle: 'Accountant',
    phones: [(label: 'mobile', number: '+1 415 555 0105')],
    emails: [(label: 'work', address: 'tom@weber.biz')],
    notes: 'External. Invoices on the 1st.',
  );

  final design = await repo.createTeam(
    orgId: orgId,
    name: 'Design',
    colorHex: '#E5604D',
    leaderPersonId: maya.id,
    memberIds: [maya.id, leo.id, priya.id],
  );
  final engineering = await repo.createTeam(
    orgId: orgId,
    name: 'Engineering',
    colorHex: '#4F6BED',
    leaderPersonId: sam.id,
    memberIds: [sam.id, priya.id],
  );
  final operations = await repo.createTeam(
    orgId: orgId,
    name: 'Operations',
    colorHex: '#E3A21A',
    leaderPersonId: dana.id,
    memberIds: [dana.id],
  );

  final logo = await repo.createTask(
    orgId: orgId,
    title: 'Finalize logo directions',
    dueDate: today,
    teamId: design.id,
    assigneeIds: [maya.id, leo.id],
    subTodoTitles: ['Moodboard', 'Three sketches', 'Client review'],
  );
  // Mark the first two sub-todos done, as in the kit.
  final logoSubs = await repo.getSubTodos(logo.id);
  await repo.toggleSubTodo(logoSubs[0].id, true);
  await repo.toggleSubTodo(logoSubs[1].id, true);

  final onboarding = await repo.createTask(
    orgId: orgId,
    title: 'Ship onboarding flow',
    dueDate: today.add(const Duration(days: 4)),
    teamId: engineering.id,
    assigneeIds: [sam.id, priya.id],
    subTodoTitles: ['API endpoints', 'Screens'],
  );
  final obSubs = await repo.getSubTodos(onboarding.id);
  await repo.toggleSubTodo(obSubs[0].id, true);

  await repo.createTask(
    orgId: orgId,
    title: 'Renew vendor contracts',
    dueDate: today.add(const Duration(days: 1)),
    teamId: operations.id,
    assigneeIds: [dana.id],
  );
  await repo.createTask(
    orgId: orgId,
    title: 'Send payroll summary',
    dueDate: today.subtract(const Duration(days: 1)),
    assigneeIds: [tom.id],
  );
  final offsite = await repo.createTask(
    orgId: orgId,
    title: 'Book team offsite',
    dueDate: today.add(const Duration(days: 7)),
    teamId: operations.id,
    assigneeIds: [dana.id, maya.id],
  );
  await repo.setTaskDone(offsite.id, true);
  final crash = await repo.createTask(
    orgId: orgId,
    title: 'Fix login crash',
    dueDate: today.add(const Duration(days: 2)),
    teamId: engineering.id,
    assigneeIds: [sam.id],
  );
  await repo.setTaskDone(crash.id, true);

  // Main tasks: the highlighted task per team (rule 5).
  await repo.setMainTask(design.id, logo.id);
  await repo.setMainTask(engineering.id, onboarding.id);
}
