enum ReaderLayoutMode { webtoon, paginated }

/// Versioned, source-scoped resume position for the native manga reader.
///
/// [pageFraction] preserves a point inside a tall webtoon image, while
/// [chapterFraction] supports an early approximate jump before that image has
/// been laid out. The exact page anchor wins once its RenderBox is available.
class ReaderProgressPosition {
  static const version = 2;

  final int pageIndex;
  final double pageFraction;
  final double chapterFraction;
  final ReaderLayoutMode mode;
  final bool completed;

  const ReaderProgressPosition({
    required this.pageIndex,
    required this.pageFraction,
    required this.chapterFraction,
    required this.mode,
    this.completed = false,
  });

  factory ReaderProgressPosition.fromJson(Map<dynamic, dynamic> json) {
    final rawMode = json['mode']?.toString();
    return ReaderProgressPosition(
      pageIndex: _integer(json['pageIndex']).clamp(0, 1 << 30),
      pageFraction: _fraction(json['pageFraction']),
      chapterFraction: _fraction(json['chapterFraction']),
      mode: rawMode == ReaderLayoutMode.paginated.name
          ? ReaderLayoutMode.paginated
          : ReaderLayoutMode.webtoon,
      completed: json['completed'] == true,
    );
  }

  Map<String, Object> toJson() => {
        'version': version,
        'pageIndex': pageIndex,
        'pageFraction': pageFraction,
        'chapterFraction': chapterFraction,
        'mode': mode.name,
        'completed': completed,
      };

  static int _integer(Object? value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;

  static double _fraction(Object? value) {
    final parsed = value is num ? value.toDouble() : double.tryParse('$value');
    return (parsed ?? 0).clamp(0.0, 1.0);
  }
}

String readerProgressStorageKey({
  required String sourceId,
  required String mangaId,
  required String chapterId,
}) {
  String part(String value) => Uri.encodeComponent(value);
  return 'reading_progress_v2_${part(sourceId)}::${part(mangaId)}::${part(chapterId)}';
}

double normalizedReaderScrollProgress({
  required double pixels,
  required double maxScrollExtent,
}) {
  if (maxScrollExtent <= 0) return 0;
  return (pixels / maxScrollExtent).clamp(0.0, 1.0);
}

bool readerReachedCompletion({
  required ReaderLayoutMode mode,
  required bool streamDone,
  required int currentPage,
  required int pageCount,
  double extentAfter = double.infinity,
  double viewportDimension = 0,
}) {
  if (!streamDone || pageCount <= 0) return false;
  if (mode == ReaderLayoutMode.paginated) {
    return currentPage >= pageCount - 1;
  }
  final tolerance = (viewportDimension * 0.12).clamp(48.0, 240.0);
  return extentAfter <= tolerance;
}
