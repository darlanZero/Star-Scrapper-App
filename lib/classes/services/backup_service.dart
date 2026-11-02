import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef BackupDirectoryProvider = Future<Directory> Function();

abstract interface class BackupSecureStore {
  Future<Map<String, String>> readLoginEntries();

  Future<void> replaceLoginEntries(Map<String, String> entries);
}

class FlutterBackupSecureStore implements BackupSecureStore {
  static const _loginPrefixes = <String>[
    'scrapper_session_',
    'tracker_',
  ];

  final FlutterSecureStorage storage;

  const FlutterBackupSecureStore({
    this.storage = const FlutterSecureStorage(),
  });

  bool _isLoginKey(String key) =>
      _loginPrefixes.any((prefix) => key.startsWith(prefix));

  @override
  Future<Map<String, String>> readLoginEntries() async {
    final values = await storage.readAll();
    return {
      for (final entry in values.entries)
        if (_isLoginKey(entry.key) && entry.value.isNotEmpty)
          entry.key: entry.value,
    };
  }

  @override
  Future<void> replaceLoginEntries(Map<String, String> entries) async {
    final current = await storage.readAll();
    for (final key in current.keys.where(_isLoginKey)) {
      await storage.delete(key: key);
    }
    for (final entry in entries.entries) {
      if (!_isLoginKey(entry.key) || entry.value.isEmpty) continue;
      await storage.write(key: entry.key, value: entry.value);
    }
  }
}

class BackupPasswordException implements Exception {
  final String message;

  const BackupPasswordException(this.message);

  @override
  String toString() => message;
}

class BackupService {
  static const MethodChannel _backupFilesChannel =
      MethodChannel('starslibrary/backup_files');
  static const int _backupSchemaVersion = 2;
  static const int _legacySchemaVersion = 1;
  static const int _pbkdf2Iterations = 210000;
  static const String _authenticatedData = 'StarsLibrary backup v2';

  final BackupSecureStore secureStore;
  final BackupDirectoryProvider? backupDirectoryProvider;
  final int pbkdf2Iterations;

  BackupService({
    BackupSecureStore? secureStore,
    this.backupDirectoryProvider,
    this.pbkdf2Iterations = _pbkdf2Iterations,
  }) : secureStore = secureStore ?? const FlutterBackupSecureStore();

  Future<Directory> _ensureBackupDir() async {
    final configured = backupDirectoryProvider;
    final backupDir = configured != null
        ? await configured()
        : Directory(
            path.join(
              (await getApplicationDocumentsDirectory()).path,
              'backups',
            ),
          );
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    return backupDir;
  }

  Future<String> createBackup({required String password}) async {
    _validatePassword(password);
    final prefs = await SharedPreferences.getInstance();
    final backupDir = await _ensureBackupDir();

    final entries = <Map<String, dynamic>>[];
    for (final key in prefs.getKeys().toList()..sort()) {
      final encoded = _encodePrefValue(prefs, key);
      if (encoded != null) entries.add(encoded);
    }

    final secureEntries = await secureStore.readLoginEntries();
    final innerPayload = <String, dynamic>{
      'entries': entries,
      'secureEntries': secureEntries,
    };
    final serializedPayload = jsonEncode(innerPayload);
    final iterations = pbkdf2Iterations;
    final encrypted = await Isolate.run(
      () => _encryptBackupPayload(serializedPayload, password, iterations),
    );
    final payload = <String, dynamic>{
      'schemaVersion': _backupSchemaVersion,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'contents': const [
        'library',
        'history',
        'favorites',
        'tabs',
        'logins',
        'enabledSources',
      ],
      'encryption': encrypted,
    };

    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final filePath = path.join(backupDir.path, 'stars_$stamp.starsbackup');
    final file = File(filePath);
    await file.writeAsString(jsonEncode(payload), flush: true);
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

  Future<bool> backupRequiresPassword(String filePath) async {
    final document = await _readDocument(filePath);
    return _schemaVersion(document) >= _backupSchemaVersion;
  }

  Future<void> restoreBackup(
    String filePath, {
    String? password,
  }) async {
    final document = await _readDocument(filePath);
    final version = _schemaVersion(document);
    final Map<String, dynamic> decodedPayload;

    if (version == _legacySchemaVersion) {
      decodedPayload = document;
    } else if (version == _backupSchemaVersion) {
      if (password == null || password.isEmpty) {
        throw const BackupPasswordException(
          'This backup is encrypted. Enter its password.',
        );
      }
      final encryption = document['encryption'];
      if (encryption is! Map) {
        throw const FormatException('Backup encryption data is missing.');
      }
      final encryptionData = Map<String, dynamic>.from(encryption);
      final plaintext = await Isolate.run(
        () => _decryptBackupPayload(encryptionData, password),
      );
      final value = jsonDecode(plaintext);
      if (value is! Map) {
        throw const FormatException('Invalid encrypted backup payload.');
      }
      decodedPayload = Map<String, dynamic>.from(value);
    } else {
      throw FormatException('Unsupported backup version: $version.');
    }

    final entries = _validatedPreferenceEntries(decodedPayload['entries']);
    final secureEntries = _validatedSecureEntries(
      decodedPayload['secureEntries'],
    );

    // Do not mutate live state until the complete document has been decoded
    // and validated. If persistence fails, restore the previous snapshot.
    final prefs = await SharedPreferences.getInstance();
    final previousPrefs = <Map<String, dynamic>>[
      for (final key in prefs.getKeys())
        if (_encodePrefValue(prefs, key) case final encoded?) encoded,
    ];
    final previousSecure = version >= _backupSchemaVersion
        ? await secureStore.readLoginEntries()
        : const <String, String>{};

    try {
      await _replacePreferences(prefs, entries);
      if (version >= _backupSchemaVersion) {
        await secureStore.replaceLoginEntries(secureEntries);
      }
    } catch (_) {
      await _replacePreferences(prefs, previousPrefs);
      if (version >= _backupSchemaVersion) {
        await secureStore.replaceLoginEntries(previousSecure);
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _readDocument(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('Backup file not found.');
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      throw const FormatException('Invalid backup format.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  int _schemaVersion(Map<String, dynamic> document) {
    final raw = document['schemaVersion'];
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '') ?? _legacySchemaVersion;
  }

  List<Map<String, dynamic>> _validatedPreferenceEntries(Object? rawEntries) {
    if (rawEntries is! List) {
      throw const FormatException('Backup has no preference entries.');
    }
    final result = <Map<String, dynamic>>[];
    for (final raw in rawEntries) {
      if (raw is! Map) {
        throw const FormatException('Invalid preference entry.');
      }
      final entry = Map<String, dynamic>.from(raw);
      final key = entry['key']?.toString() ?? '';
      final type = entry['type']?.toString() ?? '';
      if (key.isEmpty || !_supportedPreferenceType(type)) {
        throw const FormatException('Invalid preference entry metadata.');
      }
      _validatePreferenceValue(type, entry['value']);
      result.add(entry);
    }
    return result;
  }

  Map<String, String> _validatedSecureEntries(Object? rawEntries) {
    if (rawEntries == null) return {};
    if (rawEntries is! Map) {
      throw const FormatException('Invalid secure login entries.');
    }
    return rawEntries.map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    );
  }

  bool _supportedPreferenceType(String type) => const {
        'bool',
        'int',
        'double',
        'string',
        'stringList',
      }.contains(type);

  void _validatePreferenceValue(String type, Object? value) {
    final valid = switch (type) {
      'bool' => value is bool,
      'int' => value is int,
      'double' => value is num,
      'string' => value is String,
      'stringList' => value is List,
      _ => false,
    };
    if (!valid) throw const FormatException('Invalid preference value.');
  }

  Future<void> _replacePreferences(
    SharedPreferences prefs,
    List<Map<String, dynamic>> entries,
  ) async {
    await prefs.clear();
    for (final entry in entries) {
      await _applyPrefValue(
        prefs,
        entry['key'].toString(),
        entry['type'].toString(),
        entry['value'],
      );
    }
  }

  Future<void> deleteBackup(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) await file.delete();
  }

  Future<String> copyBackupToDownloads(String filePath) async {
    final source = File(filePath);
    if (!await source.exists()) {
      throw Exception('Backup file not found.');
    }

    final downloadsDir = await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    final destinationPath = path.join(
      downloadsDir.path,
      source.path.split(Platform.pathSeparator).last,
    );
    await source.copy(destinationPath);
    return destinationPath;
  }

  Future<String?> exportBackup(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw const FileSystemException('The backup file no longer exists.');
    }
    if (Platform.isAndroid) {
      return _backupFilesChannel.invokeMethod<String>('exportBackup', {
        'sourcePath': file.path,
        'fileName': path.basename(file.path),
      });
    }
    return copyBackupToDownloads(filePath);
  }

  Future<String?> selectBackupForImport() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'The native backup picker is currently available on Android.',
      );
    }
    return _backupFilesChannel.invokeMethod<String>('importBackup');
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
        if (entity is! File || !entity.path.endsWith('.starsbackup')) continue;
        if (seen.add(entity.path)) files.add(entity);
      }
    }

    files.sort(
      (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
    );
    return files;
  }

  void _validatePassword(String password) {
    if (password.length < 8) {
      throw const BackupPasswordException(
        'Use a backup password with at least 8 characters.',
      );
    }
  }

  Map<String, dynamic>? _encodePrefValue(SharedPreferences prefs, String key) {
    final value = prefs.get(key);
    if (value is bool) return {'key': key, 'type': 'bool', 'value': value};
    if (value is int) return {'key': key, 'type': 'int', 'value': value};
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
        await prefs.setBool(key, value as bool);
      case 'int':
        await prefs.setInt(key, value as int);
      case 'double':
        await prefs.setDouble(key, (value as num).toDouble());
      case 'stringList':
        await prefs.setStringList(
          key,
          (value as List).map((e) => e.toString()).toList(),
        );
      case 'string':
        await prefs.setString(key, value as String);
    }
  }
}

Map<String, dynamic> _encryptBackupPayload(
  String plaintext,
  String password,
  int iterations,
) {
  final salt = _randomBackupBytes(16);
  final nonce = _randomBackupBytes(12);
  final key = _deriveBackupKey(password, salt, iterations);
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      true,
      AEADParameters(
        KeyParameter(key),
        128,
        nonce,
        Uint8List.fromList(utf8.encode(BackupService._authenticatedData)),
      ),
    );
  final encrypted = cipher.process(Uint8List.fromList(utf8.encode(plaintext)));
  return {
    'algorithm': 'AES-256-GCM',
    'kdf': 'PBKDF2-HMAC-SHA256',
    'iterations': iterations,
    'salt': base64Encode(salt),
    'nonce': base64Encode(nonce),
    'cipherText': base64Encode(encrypted),
  };
}

String _decryptBackupPayload(Map<String, dynamic> data, String password) {
  try {
    if (data['algorithm'] != 'AES-256-GCM' ||
        data['kdf'] != 'PBKDF2-HMAC-SHA256') {
      throw const FormatException('Unsupported backup encryption.');
    }
    final iterations = data['iterations'] as int;
    if (iterations <= 0 || iterations > 1000000) {
      throw const FormatException('Invalid backup key derivation cost.');
    }
    final salt = base64Decode(data['salt'].toString());
    final nonce = base64Decode(data['nonce'].toString());
    final encrypted = base64Decode(data['cipherText'].toString());
    final key = _deriveBackupKey(password, salt, iterations);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(
          KeyParameter(key),
          128,
          nonce,
          Uint8List.fromList(utf8.encode(BackupService._authenticatedData)),
        ),
      );
    return utf8.decode(cipher.process(encrypted));
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const BackupPasswordException(
      'Incorrect password or corrupted backup.',
    );
  }
}

Uint8List _deriveBackupKey(
  String password,
  Uint8List salt,
  int iterations,
) {
  final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
    ..init(Pbkdf2Parameters(salt, iterations, 32));
  return derivator.process(Uint8List.fromList(utf8.encode(password)));
}

Uint8List _randomBackupBytes(int length) {
  final random = Random.secure();
  return Uint8List.fromList(
    List<int>.generate(length, (_) => random.nextInt(256)),
  );
}
