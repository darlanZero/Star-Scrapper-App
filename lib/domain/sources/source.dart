import 'package:star_scrapper_app/classes/Scrappers/class_scrappers.dart';

enum SourceContentType { manga, anime }

/// A content source exposed by the application.
///
/// [id] is stable and must not change when the display [name] changes because
/// it is used by local persistence.
class Fonte {
  final String id;
  final String image;
  final String name;
  final String languagePrefix;
  final List<String> flags;
  final Scrapper api;
  final SourceContentType contentType;
  bool isActive;
  bool isRRated;
  bool isOutdated;

  Fonte({
    required this.id,
    required this.image,
    required this.name,
    required this.languagePrefix,
    required this.flags,
    required this.api,
    this.contentType = SourceContentType.manga,
    this.isActive = false,
    this.isRRated = false,
    this.isOutdated = false,
  });
}

class LanguageGroup {
  final String languagePrefix;
  final List<Fonte> fonts;

  const LanguageGroup({
    required this.languagePrefix,
    required this.fonts,
  });
}
