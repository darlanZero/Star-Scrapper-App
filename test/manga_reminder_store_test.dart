import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:star_scrapper_app/data/library/manga_reminder_store.dart';

void main() {
  late Directory documents;
  late MangaReminderStore store;

  setUp(() async {
    documents = await Directory.systemTemp.createTemp('manga_reminders_test_');
    store = MangaReminderStore(documentsDirectory: () async => documents);
  });

  tearDown(() async {
    if (await documents.exists()) {
      await documents.delete(recursive: true);
    }
  });

  test('stores annotated images by source, manga and chapter', () async {
    final source = File(path.join(documents.path, 'page.webp'));
    await source.writeAsBytes([82, 73, 70, 70]);

    final reminder = await store.save(
      sourceFile: source,
      sourceId: 'mediocrescan',
      mangaId: 'manga-7',
      mangaTitle: 'Example',
      chapterId: 'chapter-3',
      chapterNumber: '3',
      chapterTitle: 'The reveal',
      pageNumber: 12,
      mimeType: 'image/webp',
      note: '  The culprit appears.  ',
    );

    final loaded = await store.loadForManga(
      sourceId: 'mediocrescan',
      mangaId: 'manga-7',
    );
    expect(loaded, hasLength(1));
    expect(loaded.single.note, 'The culprit appears.');
    expect(loaded.single.chapterNumber, '3');
    expect(loaded.single.pageNumber, 12);
    final savedImage = await store.imageFile(reminder);
    expect(await savedImage.exists(), isTrue);
    expect(
      await store.loadForManga(sourceId: 'another-source', mangaId: 'manga-7'),
      isEmpty,
    );
  });

  test('deletes both reminder metadata and its private image', () async {
    final source = File(path.join(documents.path, 'page.png'));
    await source.writeAsBytes([137, 80, 78, 71]);
    final reminder = await store.save(
      sourceFile: source,
      sourceId: 'source',
      mangaId: 'manga',
      mangaTitle: 'Manga',
      chapterId: '1',
      chapterNumber: '1',
      chapterTitle: '',
      pageNumber: 1,
      mimeType: 'image/png',
      note: '',
    );
    final savedImage = await store.imageFile(reminder);

    await store.delete(reminder);

    expect(await savedImage.exists(), isFalse);
    expect(
      await store.loadForManga(sourceId: 'source', mangaId: 'manga'),
      isEmpty,
    );
  });
}
