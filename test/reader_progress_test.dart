import 'package:flutter_test/flutter_test.dart';
import 'package:star_scrapper_app/domain/library/reader_progress.dart';

void main() {
  test('round-trips a position inside a tall webtoon image', () {
    const position = ReaderProgressPosition(
      pageIndex: 2,
      pageFraction: 0.625,
      chapterFraction: 0.38,
      mode: ReaderLayoutMode.webtoon,
    );

    final restored = ReaderProgressPosition.fromJson(position.toJson());
    expect(restored.pageIndex, 2);
    expect(restored.pageFraction, 0.625);
    expect(restored.chapterFraction, 0.38);
    expect(restored.mode, ReaderLayoutMode.webtoon);
  });

  test('storage keys are isolated by source, title and chapter', () {
    final first = readerProgressStorageKey(
      sourceId: 'yomu',
      mangaId: 'title',
      chapterId: '1',
    );
    final second = readerProgressStorageKey(
      sourceId: 'mangadex',
      mangaId: 'title',
      chapterId: '1',
    );
    expect(first, isNot(second));
  });

  test('webtoon completion requires the finished stream and real bottom', () {
    expect(
      readerReachedCompletion(
        mode: ReaderLayoutMode.webtoon,
        streamDone: false,
        currentPage: 0,
        pageCount: 1,
        extentAfter: 0,
        viewportDimension: 800,
      ),
      isFalse,
    );
    expect(
      readerReachedCompletion(
        mode: ReaderLayoutMode.webtoon,
        streamDone: true,
        currentPage: 0,
        pageCount: 1,
        extentAfter: 70,
        viewportDimension: 800,
      ),
      isTrue,
    );
  });

  test('paginated completion requires the final page', () {
    expect(
      readerReachedCompletion(
        mode: ReaderLayoutMode.paginated,
        streamDone: true,
        currentPage: 3,
        pageCount: 5,
      ),
      isFalse,
    );
    expect(
      readerReachedCompletion(
        mode: ReaderLayoutMode.paginated,
        streamDone: true,
        currentPage: 4,
        pageCount: 5,
      ),
      isTrue,
    );
  });
}
