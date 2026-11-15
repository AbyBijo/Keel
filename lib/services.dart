import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'repo.dart';

// ---------------------------------------------------------------------------
// Photos — copied into app-private storage; the DB stores only the path.
// ---------------------------------------------------------------------------

class PhotoService {
  final _picker = ImagePicker();

  /// Returns the app-private path of the copied photo, or null if the
  /// user cancelled. The file is validated as an image before copying.
  Future<String?> pickPhoto({
    required ImageSource source,
    required String personId,
  }) async {
    final picked = await _picker.pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 88,
    );
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    // Validate: must decode as an image (JPEG/PNG magic bytes).
    if (!_looksLikeImage(bytes)) return null;
    final dir = await getApplicationDocumentsDirectory();
    final photosDir = Directory(p.join(dir.path, 'photos'));
    await photosDir.create(recursive: true);
    final ext = p.extension(picked.path).toLowerCase();
    final safeExt = (ext == '.png' || ext == '.jpg' || ext == '.jpeg')
        ? ext
        : '.jpg';
    final dest = File(
      p.join(photosDir.path, '${personId}_${DateTime.now().millisecondsSinceEpoch}$safeExt'),
    );
    await dest.writeAsBytes(bytes, flush: true);
    return dest.path;
  }

  bool _looksLikeImage(List<int> bytes) {
    if (bytes.length < 4) return false;
    // JPEG: FF D8 FF · PNG: 89 50 4E 47 · WebP: RIFF....WEBP
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return true;
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return true;
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return true;
    }
    return false;
  }

  Future<void> deletePhoto(String? path) async {
    if (path == null) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // A missing photo file must never break a delete.
    }
  }
}

// ---------------------------------------------------------------------------
// Backup / restore — one zip (keel-backup.json + photos/) via the system
// file picker (Storage Access Framework). No permissions beyond that.
// ---------------------------------------------------------------------------

class BackupService {
  /// Returns a human summary, or null if the user cancelled the picker.
  Future<String?> backup(KeelRepository repo) async {
    final data = await repo.exportAll();
    final jsonBytes = utf8.encode(jsonEncode(data));

    final archive = Archive();
    archive.addFile(
      ArchiveFile('keel-backup.json', jsonBytes.length, Uint8List.fromList(jsonBytes)),
    );
    // Photos: include every referenced photo file that still exists.
    final people = data['people'] as List;
    final seen = <String>{};
    for (final row in people) {
      final path = (row as Map)['photoPath'] as String?;
      if (path == null || path.isEmpty || !seen.add(path)) continue;
      final file = File(path);
      if (!await file.exists()) continue;
      final bytes = await file.readAsBytes();
      archive.addFile(
        ArchiveFile('photos/${p.basename(path)}', bytes.length, bytes),
      );
    }
    final zipBytes = ZipEncoder().encode(archive);

    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final pickedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Back up Keel',
      fileName: 'keel-backup-$stamp.zip',
      bytes: Uint8List.fromList(zipBytes),
    );
    if (pickedPath == null) return null;
    final counts =
        '${(data['organizations'] as List).length} orgs, '
        '${(data['people'] as List).length} people, '
        '${(data['teams'] as List).length} teams, '
        '${(data['tasks'] as List).length} tasks';
    return counts;
  }

  /// Restores from a picker-chosen zip. Validates the file BEFORE replacing
  /// any data. Returns a summary string, or throws a [FormatException]
  /// with a user-readable message.
  Future<({int orgs, int people, int teams, int tasks})> restore(
    KeelRepository repo,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Restore Keel backup',
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (result == null || result.files.single.path == null) {
      throw const FormatException('cancelled');
    }
    final zipFile = File(result.files.single.path!);
    if (await zipFile.length() > 100 * 1024 * 1024) {
      throw const FormatException('Backup file is too large (over 100 MB).');
    }
    final bytes = await zipFile.readAsBytes();
    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException('That file is not a valid Keel backup zip.');
    }
    // Zip-slip / zip-bomb guards, checked BEFORE anything is written:
    // entries are never extracted by name (photos use basename only,
    // see below), and a hostile file cannot smuggle in thousands of
    // entries or gigabytes of expanded data past these caps.
    if (archive.files.length > 5000) {
      throw const FormatException(
        'Backup has too many files to restore safely.',
      );
    }
    var totalUncompressed = 0;
    for (final f in archive.files) {
      if (f.size > 25 * 1024 * 1024) {
        throw const FormatException(
          'Backup contains a file that is too large to restore safely.',
        );
      }
      totalUncompressed += f.size;
      if (totalUncompressed > 100 * 1024 * 1024) {
        throw const FormatException(
          'Backup is too large to restore safely.',
        );
      }
    }
    final jsonFile = archive.files.where((f) => f.name == 'keel-backup.json');
    if (jsonFile.isEmpty) {
      throw const FormatException('Backup zip has no keel-backup.json inside.');
    }
    Map<String, dynamic> data;
    try {
      data = jsonDecode(utf8.decode(jsonFile.first.content as List<int>))
          as Map<String, dynamic>;
    } catch (_) {
      throw const FormatException('Backup data is damaged and cannot be read.');
    }
    final error = KeelRepository.validateBackup(data);
    if (error != null) throw FormatException(error);

    // Restore photos into app-private storage first, then rewrite DB paths.
    final dir = await getApplicationDocumentsDirectory();
    final photosDir = Directory(p.join(dir.path, 'photos'));
    await photosDir.create(recursive: true);
    final photoByName = <String, String>{};
    for (final f in archive.files) {
      if (!f.name.startsWith('photos/') || f.name == 'photos/') continue;
      final dest = File(p.join(photosDir.path, p.basename(f.name)));
      await dest.writeAsBytes(f.content as List<int>, flush: true);
      photoByName[p.basename(f.name)] = dest.path;
    }
    for (final row in data['people'] as List) {
      final m = row as Map<String, dynamic>;
      final old = m['photoPath'] as String?;
      if (old != null && old.isNotEmpty) {
        m['photoPath'] = photoByName[p.basename(old)];
      }
    }

    return repo.importAll(data);
  }

  /// Export the active org's tasks to CSV via the file picker.
  Future<bool> exportTasksCsv(KeelRepository repo, String orgId) async {
    final tasks = await repo.getTasks(orgId);
    final buf = StringBuffer('Title,Team,Due date,Priority,Status,Assignees\n');
    String esc(String s) => '"${s.replaceAll('"', '""')}"';
    for (final t in tasks) {
      final team = t.teamId == null
          ? ''
          : (await repo.getTeam(t.teamId!))?.name ?? '';
      final assignees = (await repo.getTaskAssignees(t.id))
          .map((e) => e.name)
          .join('; ');
      buf.writeln(
        [
          esc(t.title),
          esc(team),
          esc(t.dueDate?.toIso8601String().substring(0, 10) ?? ''),
          esc(t.priority),
          esc(t.isDone ? 'Done' : 'Open'),
          esc(assignees),
        ].join(','),
      );
    }
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Export tasks to CSV',
      fileName: 'keel-tasks.csv',
      bytes: utf8.encode(buf.toString()),
    );
    return path != null;
  }
}

// ---------------------------------------------------------------------------
// Local notifications — daily digest only. No network, no server.
// ---------------------------------------------------------------------------

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> init() async {
    tzdata.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: android),
    );
    _ready = true;
  }

  static Future<bool> requestPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.requestNotificationsPermission() ?? true;
  }

  /// Schedule (or cancel) the daily digest at [hour]:[minute] local time.
  static Future<void> setDailyDigest({
    required bool on,
    required int hour,
    required int minute,
    required Future<({int overdue, int dueSoon, int open})> Function()
    counts,
  }) async {
    if (!_ready) return;
    await _plugin.cancel(1001);
    if (!on) return;
    final now = tz.TZDateTime.now(tz.local);
    var at = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (at.isBefore(now)) at = at.add(const Duration(days: 1));
    final c = await counts();
    final body = c.overdue > 0
        ? '${c.overdue} overdue · ${c.dueSoon} due soon · ${c.open} open tasks'
        : '${c.dueSoon} due soon · ${c.open} open tasks';
    await _plugin.zonedSchedule(
      1001,
      'Keel — today',
      body,
      at,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'keel_digest',
          'Daily digest',
          channelDescription: 'Daily summary of due and overdue tasks',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }
}

// ---------------------------------------------------------------------------
// Undo snackbar — 6 seconds, restores the snapshot on Undo (rule 10).
// ---------------------------------------------------------------------------

void showUndoSnack(
  BuildContext context, {
  required String label,
  required Future<void> Function() onUndo,
}) {
  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(label),
      duration: const Duration(seconds: 6),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () {
          // Fire and forget: the restore is a DB write, the lists update
          // through their streams.
          unawaited(onUndo());
        },
      ),
    ),
  );
}

void showKeelSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
  );
}
