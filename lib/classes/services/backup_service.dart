import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BackupService {
  static const int _backupSchemaVersion = 1;

  Future<Directory> _ensureBackupDir() async {
    final appDocs = await getApplicationDocumentsDirectory();
    final backupDir = Directory(path.join(appDocs.path, 'backups'));
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    return backupDir;
  }

  Future<String> createBackup() async {
    final prefs = await SharedPreferences.getInstance();
    final backupDir = await _ensureBackupDir();

    final entries = <Map<String, dynamic>>[];
    for (final key in prefs.getKeys()) {
      final encoded = _encodePrefValue(prefs, key);
      if (encoded != null) {
        entries.add(encoded);
      }
    }

    final payload = <String, dynamic>{
      'schemaVersion': _backupSchemaVersion,
      'createdAt': DateTime.now().toIso8601String(),
      'entries': entries,
    };

    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final filePath = path.join(backupDir.path, 'stars_$stamp.starsbackup');
    final file = File(filePath);
    await file.writeAsString(jsonEncode(payload));
    return file.path;
  }

  Future<List<FileSystemEntity>> listBackups() async {
    final backupDir = await _ensureBackupDir();
    final files = backupDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.starsbackup'))
        .toList();
    files.sort(
      (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
    );
    return files;
  }

  Future<void> restoreBackup(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('Backup file not found.');
    }

    final content = await file.readAsString();
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid backup format.');
    }
    final entries = decoded['entries'];
    if (entries is! List) {
      throw Exception('Backup has no entries.');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    for (final raw in entries) {
      if (raw is! Map) continue;
      final key = raw['key']?.toString() ?? '';
      final type = raw['type']?.toString() ?? '';
      final value = raw['value'];
      if (key.isEmpty) continue;
      await _applyPrefValue(prefs, key, type, value);
    }
  }

  Future<void> deleteBackup(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<String> copyBackupToDownloads(String filePath) async {
    final source = File(filePath);
    if (!await source.exists()) {
      throw Exception('Backup file not found.');
    }

    final downloadsDir =
        await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    final destinationPath = path.join(
      downloadsDir.path,
      source.path.split(Platform.pathSeparator).last,
    );
    final destination = File(destinationPath);
    await source.copy(destination.path);
    return destination.path;
  }

  Future<List<FileSystemEntity>> listImportableBackups() async {
    final dirs = <Directory>[];
    final downloads = await getDownloadsDirectory();
    final documents = await getApplicationDocumentsDirectory();
    if (downloads != null) dirs.add(downloads);
    dirs.add(documents);

    final seen = <String>{};
    final files = <FileSystemEntity>[];
    for (final dir in dirs) {
      if (!await dir.exists()) continue;
      for (final entity in dir.listSync()) {
        if (entity is! File) continue;
        if (!entity.path.endsWith('.starsbackup')) continue;
        if (seen.add(entity.path)) {
          files.add(entity);
        }
      }
    }

    files.sort(
      (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
    );
    return files;
  }

  Map<String, dynamic>? _encodePrefValue(SharedPreferences prefs, String key) {
    final value = prefs.get(key);
    if (value is bool) {
      return {'key': key, 'type': 'bool', 'value': value};
    }
    if (value is int) {
      return {'key': key, 'type': 'int', 'value': value};
    }
    if (value is double) {
      return {'key': key, 'type': 'double', 'value': value};
    }
    if (value is String) {
      return {'key': key, 'type': 'string', 'value': value};
    }
    if (value is List) {
      return {
        'key': key,
        'type': 'stringList',
        'value': value.map((e) => e.toString()).toList(),
      };
    }
    return null;
  }

  Future<void> _applyPrefValue(
    SharedPreferences prefs,
    String key,
    String type,
    dynamic value,
  ) async {
    switch (type) {
      case 'bool':
        if (value is bool) await prefs.setBool(key, value);
        break;
      case 'int':
        if (value is int) await prefs.setInt(key, value);
        break;
      case 'double':
        if (value is num) await prefs.setDouble(key, value.toDouble());
        break;
      case 'stringList':
        if (value is List) {
          await prefs.setStringList(key, value.map((e) => e.toString()).toList());
        }
        break;
      case 'string':
        if (value is String) await prefs.setString(key, value);
        break;
      default:
        break;
    }
  }
}
