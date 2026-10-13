typedef ChapterJson = Map<String, String>;

/// A chapter reference stored in reading progress.
class ChapterRecord {
  final String id;
  final String title;

  const ChapterRecord({required this.id, required this.title});

  factory ChapterRecord.fromJson(Map<dynamic, dynamic> json) {
    return ChapterRecord(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
    );
  }

  ChapterJson toJson() => {'id': id, 'title': title};
}
