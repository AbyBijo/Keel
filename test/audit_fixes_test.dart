import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/db.dart';
import 'package:keel/repo.dart';
import 'package:keel/sheets.dart';

Future<KeelRepository> freshRepo() async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  return KeelRepository(db);
}

void main() {
  group('Audit fix — validateBackup rejects damaged foreign files', () {
    test('a real export validates', () async {
      final repo = await freshRepo();
      final org = await repo.createOrganization(name: 'Org', kind: 'Studio');
      await repo.createPerson(orgId: org.id, name: 'Ann', roleTitle: '');
      final data = await repo.exportAll();
      expect(KeelRepository.validateBackup(data), isNull);
    });

    test('missing phones list is rejected', () async {
      final repo = await freshRepo();
      final data = await repo.exportAll();
      data.remove('phones');
      expect(KeelRepository.validateBackup(data), contains('phones'));
    });

    test('missing emails list is rejected', () async {
      final repo = await freshRepo();
      final data = await repo.exportAll();
      data.remove('emails');
      expect(KeelRepository.validateBackup(data), contains('emails'));
    });

    test('a non-map row is rejected, not a raw TypeError at restore', () async {
      final repo = await freshRepo();
      final data = await repo.exportAll();
      // A foreign JSON file decodes to List<dynamic>; rebuild it that way
      // so the damaged row can actually be added (a typed List<Map>
      // would throw at .add instead).
      final tasks = List<dynamic>.from(data['tasks'] as List)
        ..add('not-a-row');
      data['tasks'] = tasks;
      expect(KeelRepository.validateBackup(data), contains('damaged'));
    });

    test('wrong format is rejected', () async {
      final repo = await freshRepo();
      final data = await repo.exportAll();
      data['format'] = 'something-else';
      expect(
        KeelRepository.validateBackup(data),
        contains('not a Keel backup'),
      );
    });
  });

  group('Audit fix — WhatsApp links are digits-only', () {
    test('international number keeps its digits, drops + and spaces', () {
      expect(
        whatsappUriFor('+91 85903 86329')?.toString(),
        'https://wa.me/918590386329',
      );
    });

    test('plain number passes through', () {
      expect(
        whatsappUriFor('8590386329')?.toString(),
        'https://wa.me/8590386329',
      );
    });

    test('no digits means no link (button stays disabled)', () {
      expect(whatsappUriFor(''), isNull);
      expect(whatsappUriFor('call me'), isNull);
      expect(whatsappUriFor('+'), isNull);
    });
  });

  group('Audit fix — JOIN rewrites return the same rows as the old N+1 code', () {
    test('team members come back complete and name-sorted', () async {
      final repo = await freshRepo();
      final org = await repo.createOrganization(name: 'Org', kind: 'Studio');
      final a = await repo.createPerson(orgId: org.id, name: 'Zed', roleTitle: '');
      final b = await repo.createPerson(orgId: org.id, name: 'Ann', roleTitle: '');
      final c = await repo.createPerson(orgId: org.id, name: 'Mia', roleTitle: '');
      final team = await repo.createTeam(
        orgId: org.id,
        name: 'Design',
        colorHex: '#E5604D',
        leaderPersonId: a.id,
        memberIds: [b.id, c.id],
      );
      final members = await repo.getTeamMembers(team.id);
      expect(members.map((p) => p.name), ['Ann', 'Mia', 'Zed']);
      expect(
        (await repo.getTeamsForPerson(b.id)).map((t) => t.id),
        [team.id],
      );
    });

    test('task assignees and per-person tasks match from both sides', () async {
      final repo = await freshRepo();
      final org = await repo.createOrganization(name: 'Org', kind: 'Studio');
      final a = await repo.createPerson(orgId: org.id, name: 'Ann', roleTitle: '');
      final b = await repo.createPerson(orgId: org.id, name: 'Ben', roleTitle: '');
      final t1 = await repo.createTask(orgId: org.id, title: 'One');
      final t2 = await repo.createTask(orgId: org.id, title: 'Two');
      await repo.assignPersonToTask(t1.id, a.id);
      await repo.assignPersonToTask(t1.id, b.id);
      await repo.assignPersonToTask(t2.id, a.id);
      expect(
        (await repo.getTaskAssignees(t1.id)).map((p) => p.id).toSet(),
        {a.id, b.id},
      );
      expect(
        (await repo.getTasksForPerson(a.id)).map((t) => t.id).toSet(),
        {t1.id, t2.id},
      );
      expect(
        (await repo.getTasksForPerson(b.id)).map((t) => t.id),
        [t1.id],
      );
    });
  });
}
