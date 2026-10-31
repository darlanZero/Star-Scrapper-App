class MangaReminder {
  const MangaReminder({
    required this.id,
    required this.sourceId,
    required this.mangaId,
    required this.mangaTitle,
    required this.chapterId,
    required this.chapterNumber,
    required this.chapterTitle,
    required this.pageNumber,
    required this.relativeImagePath,
    required this.mimeType,
    required this.note,
    required this.createdAt,
  });

  final String id;
  final String sourceId;
  final String mangaId;
  final String mangaTitle;
  final String chapterId;
  final String chapterNumber;
  final String chapterTitle;
  final int pageNumber;
  final String relativeImagePath;
  final String mimeType;
  final String note;
  final DateTime createdAt;

  factory MangaReminder.fromJson(Map<dynamic, dynamic> json) {
    return MangaReminder(
      id: json['id']?.toString() ?? '',
      sourceId: json['sourceId']?.toString() ?? '',
      mangaId: json['mangaId']?.toString() ?? '',
      mangaTitle: json['mangaTitle']?.toString() ?? '',
      chapterId: json['chapterId']?.toString() ?? '',
      chapterNumber: json['chapterNumber']?.toString() ?? '',
      chapterTitle: json['chapterTitle']?.toString() ?? '',
      pageNumber: int.tryParse(json['pageNumber']?.toString() ?? '') ?? 0,
      relativeImagePath: json['relativeImagePath']?.toString() ?? '',
      mimeType: json['mimeType']?.toString() ?? 'image/jpeg',
      note: json['note']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourceId': sourceId,
        'mangaId': mangaId,
        'mangaTitle': mangaTitle,
        'chapterId': chapterId,
        'chapterNumber': chapterNumber,
        'chapterTitle': chapterTitle,
        'pageNumber': pageNumber,
        'relativeImagePath': relativeImagePath,
        'mimeType': mimeType,
        'note': note,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };
}
