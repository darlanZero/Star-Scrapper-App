typedef BookJson = Map<String, dynamic>;

/// Typed boundary around the flexible book payloads returned by scrapers.
///
/// Unknown fields are preserved so sources can evolve independently while
/// shared library fields are read and normalized consistently.
class BookRecord {
  final BookJson _json;

  BookRecord.fromJson(BookJson json) : _json = _copyJson(json);

  String get id => (_json['id'] ?? '').toString();
  String get title => (_json['title'] ?? '').toString();

  List<String> get tabs {
    final rawTabs = _json['tabs'];
    if (rawTabs is List) {
      return rawTabs.map((tab) => tab.toString()).toList();
    }
    final legacyTab = _json['tab'];
    if (legacyTab is String && legacyTab.isNotEmpty) return [legacyTab];
    return ['Reading'];
  }

  Map<String, List<String>> get subTabsByPrimary {
    final raw = _json['subTabsByPrimary'];
    if (raw is Map) {
      return raw.map((key, value) {
        return MapEntry(
          key.toString(),
          value is List
              ? value.map((subTab) => subTab.toString()).toList()
              : <String>[],
        );
      });
    }

    final legacySubTabs = <String>[];
    final rawLegacy = _json['subTabs'];
    if (rawLegacy is List) {
      legacySubTabs.addAll(rawLegacy.map((subTab) => subTab.toString()));
    } else {
      legacySubTabs.add(_json['isRead'] == true ? 'Read' : 'Unread');
    }
    return {
      for (final tab in tabs)
        tab: List<String>.from(
          legacySubTabs.isEmpty ? const ['Unread'] : legacySubTabs,
        ),
    };
  }

  BookJson toJson() => _copyJson(_json);

  BookJson toLegacyTabMigratedJson() {
    final normalized = toJson();
    if (!normalized.containsKey('tabs')) {
      normalized['tabs'] = tabs;
    }
    normalized.remove('tab');
    return normalized;
  }

  BookJson toNormalizedLibraryJson() {
    return toJson()
      ..['tabs'] = tabs
      ..['subTabsByPrimary'] = subTabsByPrimary
      ..remove('tab')
      ..remove('subTabs');
  }

  void applyOrganizationTo(BookJson target) {
    target['tabs'] = tabs;
    target['subTabsByPrimary'] = subTabsByPrimary;
    target.remove('tab');
    target.remove('subTabs');
  }

  static BookJson _copyJson(Map<String, dynamic> json) {
    return json.map((key, value) => MapEntry(key, _copyValue(value)));
  }

  static dynamic _copyValue(dynamic value) {
    if (value is Map) {
      return value.map(
        (key, nestedValue) => MapEntry(key.toString(), _copyValue(nestedValue)),
      );
    }
    if (value is List) {
      return value.map(_copyValue).toList();
    }
    return value;
  }
}
