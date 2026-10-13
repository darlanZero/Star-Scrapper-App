import 'package:flutter_test/flutter_test.dart';
import 'package:star_scrapper_app/domain/library/chapter_record.dart';

void main() {
  test('normalizes scraper values to persisted strings', () {
    final chapter = ChapterRecord.fromJson({
      'id': 12,
      'title': null,
    });

    expect(chapter.id, '12');
    expect(chapter.title, '');
    expect(chapter.toJson(), {'id': '12', 'title': ''});
  });
}
