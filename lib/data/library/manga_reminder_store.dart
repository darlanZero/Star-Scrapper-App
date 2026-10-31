import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:star_scrapper_app/domain/library/manga_reminder.dart';

typedef ReminderDirectoryProvider = Future<Directory> Function();

class MangaReminderStore {
  MangaReminderStore({
    ReminderDirectoryProvider? documentsDirectory,
  }) : _documentsDirectory =
            documentsDirectory ?? getApplicationDocumentsDirectory;

  final ReminderDirectoryProvider _documentsDirectory;
  Directory? _root;

  Future<List<MangaReminder>> loadForManga({
    required String sourceId,
    required String mangaId,
  }) async {
    final reminders = await _loadAll();
    return reminders
        .where(
          (reminder) =>
              reminder.sourceId == sourceId && reminder.mangaId == mangaId,
        )
        .toList()
      ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
  }

  Future<MangaReminder> save({
    required File sourceFile,
    required String sourceId,
    required String mangaId,
    required String mangaTitle,
    required String chapterId,
    required String chapterNumber,
    required String chapterTitle,
    required int pageNumber,
    required String mimeType,
    required String note,
  }) async {
    if (!await sourceFile.exists()) {
      throw FileSystemException(
          'Reminder image is unavailable.', sourceFile.path);
    }
    final root = await _rootDirectory();
    final all = await _loadAll();
    final now = DateTime.now().toUtc();
    final id = '${now.microsecondsSinceEpoch}_p$pageNumber';
    final mangaKey = sha1
        .convert(utf8.encode('$sourceId\u0000$mangaId'))
        .toString()
        .substring(0, 16);
    final extension = _extension(sourceFile.path, mimeType);
    final relativeImagePath = path.join('images', mangaKey, '$id.$extension');
    final destination = File(path.join(root.path, relativeImagePath));
    await destination.parent.create(recursive: true);
    await sourceFile.copy(destination.path);

    final reminder = MangaReminder(
      id: id,
      sourceId: sourceId,
      mangaId: mangaId,
      mangaTitle: mangaTitle,
      chapterId: chapterId,
      chapterNumber: chapterNumber,
      chapterTitle: chapterTitle,
      pageNumber: pageNumber,
      relativeImagePath: relativeImagePath,
      mimeType: mimeType,
      note: note.trim(),
      createdAt: now,
    );
    try {
      await _saveAll([...all, reminder]);
    } catch (_) {
      if (await destination.exists()) await destination.delete();
      rethrow;
    }
    return reminder;
  }

  Future<void> delete(MangaReminder reminder) async {
    final all = await _loadAll();
    await _saveAll(all.where((item) => item.id != reminder.id).toList());
    final image = await imageFile(reminder);
    if (await image.exists()) await image.delete();
  }

  Future<File> imageFile(MangaReminder reminder) async {
    final root = await _rootDirectory();
    final resolved = File(path.normalize(
      path.join(root.path, reminder.relativeImagePath),
    ));
    if (!path.isWithin(root.path, resolved.path)) {
      throw const FileSystemException('Invalid reminder image path.');
    }
    return resolved;
  }

  Future<List<MangaReminder>> _loadAll() async {
    final root = await _rootDirectory();
    final index = File(path.join(root.path, 'index.json'));
    if (!await index.exists()) return [];
    try {
      final decoded = jsonDecode(await index.readAsString());
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map(MangaReminder.fromJson)
          .where(
            (item) =>
                item.id.isNotEmpty &&
                item.sourceId.isNotEmpty &&
                item.mangaId.isNotEmpty &&
                item.relativeImagePath.isNotEmpty,
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveAll(List<MangaReminder> reminders) async {
    final root = await _rootDirectory();
    final index = File(path.join(root.path, 'index.json'));
    await index.writeAsString(
      jsonEncode(reminders.map((item) => item.toJson()).toList()),
      flush: true,
    );
  }

  Future<Directory> _rootDirectory() async {
    final cached = _root;
    if (cached != null) return cached;
    final documents = await _documentsDirectory();
    final root = Directory(path.join(documents.path, 'manga_reminders'));
    await root.create(recursive: true);
    return _root = root;
  }

  String _extension(String filePath, String mimeType) {
    final fromPath =
        path.extension(filePath).replaceFirst('.', '').toLowerCase();
    if (const {'jpg', 'jpeg', 'png', 'webp', 'gif'}.contains(fromPath)) {
      return fromPath == 'jpeg' ? 'jpg' : fromPath;
    }
    return switch (mimeType.toLowerCase()) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      'image/gif' => 'gif',
      _ => 'jpg',
    };
  }
}
