import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/domain/sources/anime_source.dart';

/// JSON API integration for AniKage.
///
/// Stable ids are AniKage slugs. Catalog metadata comes from the public browse
/// API, while short-lived stream tokens are resolved only when playback starts.
class AnikageSource implements AnimeSource, FilterableAnimeSource {
  static final Uri _defaultBaseUri = Uri.parse('https://anikage.cc/');
  static final Uri _defaultProxyUri = Uri.parse('https://og.bakayaro.live/');
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/130.0 Mobile Safari/537.36';

  final http.Client _client;
  final Uri _baseUri;
  final Uri _proxyUri;

  AnikageSource({
    http.Client? client,
    Uri? baseUri,
    Uri? proxyUri,
  })  : _client = client ?? http.Client(),
        _baseUri = baseUri ?? _defaultBaseUri,
        _proxyUri = proxyUri ?? _defaultProxyUri;

  @override
  String get id => 'anikage';

  @override
  String get name => 'AniKage';

  @override
  Uri get baseUri => _baseUri;

  @override
  Map<String, String> get requestHeaders => const {
        'Accept': 'application/json, text/plain, */*',
        'User-Agent': _userAgent,
      };

  Map<String, String> get _mediaHeaders => {
        'Accept': '*/*',
        'Origin': _baseUri.origin,
        'Referer': _baseUri.toString(),
        'User-Agent': _userAgent,
      };

  @override
  List<AnimeCatalogFilter> get catalogFilters => const [
        AnimeCatalogFilter.popular,
        AnimeCatalogFilter.added,
        AnimeCatalogFilter.recent,
        AnimeCatalogFilter.airing,
        AnimeCatalogFilter.completed,
      ];

  @override
  Future<AnimeCatalogPage> browse({
    AnimeCatalogFilter filter = AnimeCatalogFilter.popular,
    String? cursor,
  }) {
    final request = switch (filter) {
      AnimeCatalogFilter.added ||
      AnimeCatalogFilter.updated =>
        AnimeSearchRequest(sort: AnimeSearchSort.dateAdded),
      AnimeCatalogFilter.recent =>
        AnimeSearchRequest(sort: AnimeSearchSort.releaseDate),
      AnimeCatalogFilter.airing => AnimeSearchRequest(
          status: 'RELEASING',
          sort: AnimeSearchSort.popularity,
        ),
      AnimeCatalogFilter.completed => AnimeSearchRequest(
          status: 'FINISHED',
          sort: AnimeSearchSort.popularity,
        ),
      _ => AnimeSearchRequest(sort: AnimeSearchSort.popularity),
    };
    return this.filter(request, cursor: cursor);
  }

  @override
  Future<AnimeCatalogPage> search(String query, {String? cursor}) => filter(
        AnimeSearchRequest(query: query.trim()),
        cursor: cursor,
      );

  @override
  Future<AnimeCatalogPage> filter(
    AnimeSearchRequest request, {
    String? cursor,
  }) async {
    final page = int.tryParse(cursor ?? '') ?? 1;
    final parameters = <String, String>{
      'sort': _sortValue(request.sort),
      'limit': '24',
      'adult': 'false',
      'page': '$page',
      if (request.query.trim().isNotEmpty) 'q': request.query.trim(),
      if (request.genres.isNotEmpty) 'genres': request.genres.join(','),
      if (request.tags.isNotEmpty) 'tags': request.tags.join(','),
      if (request.formats.isNotEmpty) 'format': request.formats.join(','),
      if (request.formats.isEmpty && request.type != null)
        'format': request.type!,
      if (request.sources.isNotEmpty) 'source': request.sources.join(','),
      if (request.year != null) ...{
        'yearMin': request.year!,
        'yearMax': request.year!,
      },
      if (request.season != null) 'season': request.season!,
      if (request.status != null) 'status': request.status!,
      if (request.origin != null) 'country': request.origin!,
      if (request.score != null) 'scoreMin': request.score!,
      if (request.audio == 'sub') 'sub': 'true',
      if (request.audio == 'dub') 'dub': 'true',
    };
    final episodeRange = request.episodeRange;
    if (episodeRange != null) {
      final parts = episodeRange.split('-');
      if (parts.first.isNotEmpty) parameters['epMin'] = parts.first;
      if (parts.length > 1 && parts[1].isNotEmpty) {
        parameters['epMax'] = parts[1];
      }
    }

    final uri = _baseUri.resolve('api/media/anime/browse').replace(
          queryParameters: parameters,
        );
    final data = _map(await _getJson(uri));
    final items =
        _maps(data['data']).map(_catalogItem).whereType<AnimeCatalogItem>();
    final hasNext = data['hasNext'] == true;
    return AnimeCatalogPage(
      items: items,
      nextCursor: hasNext ? '${page + 1}' : null,
    );
  }

  @override
  Future<AnimeSearchOptions> getSearchOptions() async {
    final currentYear = DateTime.now().year;
    return AnimeSearchOptions(
      genres: _options(_genreNames),
      tags: _options(_tagNames),
      seasons: _options(const ['WINTER', 'SPRING', 'SUMMER', 'FALL']),
      years: [
        for (var year = currentYear + 1; year >= 1940; year--)
          AnimeFilterOption(value: '$year', label: '$year'),
      ],
      formats: const [
        AnimeFilterOption(value: 'TV', label: 'TV'),
        AnimeFilterOption(value: 'TV_SHORT', label: 'TV Short'),
        AnimeFilterOption(value: 'MOVIE', label: 'Movie'),
        AnimeFilterOption(value: 'SPECIAL', label: 'Special'),
        AnimeFilterOption(value: 'OVA', label: 'OVA'),
        AnimeFilterOption(value: 'ONA', label: 'ONA'),
        AnimeFilterOption(value: 'MUSIC', label: 'Music'),
      ],
      statuses: const [
        AnimeFilterOption(value: 'FINISHED', label: 'Finished'),
        AnimeFilterOption(value: 'RELEASING', label: 'Releasing'),
        AnimeFilterOption(
          value: 'NOT_YET_RELEASED',
          label: 'Not Yet Released',
        ),
        AnimeFilterOption(value: 'CANCELLED', label: 'Cancelled'),
      ],
      sources: const [
        AnimeFilterOption(value: 'ORIGINAL', label: 'Original'),
        AnimeFilterOption(value: 'MANGA', label: 'Manga'),
        AnimeFilterOption(value: 'LIGHT_NOVEL', label: 'Light Novel'),
        AnimeFilterOption(value: 'WEB_NOVEL', label: 'Web Novel'),
        AnimeFilterOption(value: 'NOVEL', label: 'Novel'),
        AnimeFilterOption(value: 'VISUAL_NOVEL', label: 'Visual Novel'),
        AnimeFilterOption(value: 'VIDEO_GAME', label: 'Video Game'),
        AnimeFilterOption(
          value: 'MULTIMEDIA_PROJECT',
          label: 'Multimedia',
        ),
        AnimeFilterOption(value: 'OTHER', label: 'Other'),
      ],
      origins: const [
        AnimeFilterOption(value: 'JP', label: 'Japan'),
        AnimeFilterOption(value: 'KR', label: 'South Korea'),
        AnimeFilterOption(value: 'CN', label: 'China'),
        AnimeFilterOption(value: 'TW', label: 'Taiwan'),
      ],
      scores: const [
        AnimeFilterOption(value: '90', label: '9+ Masterpiece'),
        AnimeFilterOption(value: '80', label: '8+ Great'),
        AnimeFilterOption(value: '70', label: '7+ Good'),
        AnimeFilterOption(value: '60', label: '6+ Decent'),
      ],
      episodeRanges: const [
        AnimeFilterOption(value: '1-1', label: '1 (Movie / one-shot)'),
        AnimeFilterOption(value: '2-12', label: '2-12 (Single cour)'),
        AnimeFilterOption(value: '13-26', label: '13-26 (Two cours)'),
        AnimeFilterOption(value: '27-64', label: '27-64'),
        AnimeFilterOption(value: '65-', label: '65+ (Long-running)'),
      ],
      audioOptions: const [
        AnimeFilterOption(value: 'sub', label: 'Subbed'),
        AnimeFilterOption(value: 'dub', label: 'Dubbed'),
      ],
      sorts: const [
        AnimeSearchSort.popularity,
        AnimeSearchSort.averageScore,
        AnimeSearchSort.trending,
        AnimeSearchSort.favorites,
        AnimeSearchSort.dateAdded,
        AnimeSearchSort.releaseDate,
      ],
      labels: const {
        'formats': 'Format',
        'sources': 'Source',
        'origins': 'Origin',
        'scores': 'Score',
        'episodeRanges': 'Episodes',
        'audioOptions': 'Audio',
      },
    );
  }

  @override
  Future<AnimeDetails> getDetails(String animeId) async {
    final response = _map(await _getJson(
      _baseUri.resolve('api/media/anime/${Uri.encodeComponent(animeId)}'),
    ));
    final data = _map(response['anime']);
    final title = _title(data);
    final coverUri = _imageUri(data['coverImage']);
    final studios = _maps(data['studios']);
    return AnimeDetails(
      item: AnimeCatalogItem(
        id: animeId,
        title: title,
        coverUri: coverUri,
        subtitle: _catalogSubtitle(data),
      ),
      description:
          html_parser.parseFragment(_string(data['description'])).text ?? '',
      alternativeTitles: {
        ..._map(data['title']).values.map(_string),
        ..._strings(data['synonyms']),
      }.where((value) => value.isNotEmpty && value != title),
      genres: _strings(data['genres']),
      status: _status(data['status']),
      bannerUri:
          _absoluteUri(data['fanart']) ?? _absoluteUri(data['bannerImage']),
      externalIds: {
        if (data['anilistId'] != null) 'anilist': '${data['anilistId']}',
        if (data['malId'] != null) 'mal': '${data['malId']}',
      },
      studios: studios
          .where((studio) => studio['isAnimationStudio'] == true)
          .map((studio) => _string(studio['name']))
          .where((name) => name.isNotEmpty),
      producers: studios
          .where((studio) => studio['isAnimationStudio'] != true)
          .map((studio) => _string(studio['name']))
          .where((name) => name.isNotEmpty),
    );
  }

  @override
  Future<List<AnimeEpisode>> getEpisodes(String animeId) async {
    final data = await _getJson(
      _baseUri.resolve(
        'api/media/anime/${Uri.encodeComponent(animeId)}/episodes',
      ),
    );
    return _maps(data)
        .map((episode) {
          final number = _number(episode['number']);
          if (number == null) return null;
          return AnimeEpisode(
            id: _episodeId(number),
            animeId: animeId,
            title: _string(episode['title']).isNotEmpty
                ? _string(episode['title'])
                : 'Episode ${_episodeId(number)}',
            number: number,
            season: _integer(episode['seasonNumber']),
            releasedAt: DateTime.tryParse(_string(episode['airDate'])),
            thumbnailUri: _absoluteUri(episode['image']),
          );
        })
        .whereType<AnimeEpisode>()
        .toList(growable: false);
  }

  @override
  Future<AnimePlayback> getPlayback({
    required String animeId,
    required String episodeId,
  }) async {
    final episode = _episodeNumber(episodeId);
    final root =
        'api/media/anime/${Uri.encodeComponent(animeId)}/episodes/$episode';
    final serverData = _map(await _getJson(_baseUri.resolve('$root/servers')));
    final servers = _maps(serverData['servers'])
      ..sort((left, right) {
        final leftDefault = left['default'] == true ? 0 : 1;
        final rightDefault = right['default'] == true ? 0 : 1;
        return leftDefault.compareTo(rightDefault);
      });

    for (final server in servers) {
      final provider = _string(server['providerId']).isNotEmpty
          ? _string(server['providerId'])
          : _string(server['id']);
      if (provider.isEmpty || provider == 'zen') continue;
      final types = _strings(server['subTypes']);
      for (final audio in ['sub', 'dub']) {
        if (types.isNotEmpty && !types.contains(audio)) continue;
        final uri = _baseUri.resolve('$root/sources').replace(
          queryParameters: {
            'provider': provider,
            'lang': audio,
            'server': _string(server['id']),
          },
        );
        try {
          final payload = _map(await _getJson(uri));
          final playback = _playbackFromPayload(
            payload,
            provider: provider,
            audio: audio,
          );
          if (playback != null) return playback;
        } catch (_) {
          // A single upstream host must not prevent trying the next host.
        }
      }
    }

    final choices = <AnimePlaybackChoice>[];
    for (final embed in _maps(serverData['embeds'])) {
      final label = _string(embed['label']).isNotEmpty
          ? _string(embed['label'])
          : _string(embed['key']);
      final urls = _map(embed['urls']);
      for (final entry in urls.entries) {
        final uri = _absoluteUri(entry.value);
        if (uri != null) {
          choices.add(AnimePlaybackChoice(
            entryUri: uri,
            provider: label,
            quality: entry.key.toUpperCase(),
          ));
        }
      }
    }
    if (choices.isNotEmpty) throw AnimePlaybackResolutionRequired(choices);
    throw StateError('AniKage did not return a playable server.');
  }

  AnimePlayback? _playbackFromPayload(
    Map<String, dynamic> payload, {
    required String provider,
    required String audio,
  }) {
    final streams = _maps(payload['sources'])
        .map((source) {
          final token = _string(source['url']);
          if (token.isEmpty) return null;
          final isHls = source['isM3U8'] == true || token.contains('.m3u8');
          final uri = _mediaUri(token, isHls ? 'm3u8' : 'stream');
          return AnimeVideoStream(
            uri: uri,
            protocol: isHls ? VideoProtocol.hls : VideoProtocol.progressive,
            quality: [
              _string(source['label']).isNotEmpty
                  ? _string(source['label'])
                  : _string(source['quality']),
              provider.toUpperCase(),
              audio.toUpperCase(),
            ].where((value) => value.isNotEmpty).join(' · '),
            language: audio == 'dub' ? 'en' : 'ja',
            headers: _mediaHeaders,
          );
        })
        .whereType<AnimeVideoStream>()
        .toList(growable: false);
    if (streams.isEmpty) return null;

    final subtitles = _maps(payload['subtitles'])
        .where((track) => _string(track['kind']).toLowerCase() != 'thumbnails')
        .map((track) {
      final token = _string(track['file']).isNotEmpty
          ? _string(track['file'])
          : _string(track['url']);
      if (token.isEmpty) return null;
      final label = _string(track['label']).isNotEmpty
          ? _string(track['label'])
          : 'Subtitles';
      return AnimeSubtitleTrack(
        uri: _mediaUri(token, 'stream'),
        label: label,
        language: _subtitleLanguage(label),
        isDefault: track['default'] == true,
        headers: _mediaHeaders,
      );
    }).whereType<AnimeSubtitleTrack>();

    final skipSegments = <AnimeSkipSegment>[];
    _addSkip(skipSegments, payload['intro'], AnimeSkipType.intro);
    _addSkip(skipSegments, payload['outro'], AnimeSkipType.outro);
    return AnimePlayback(
      streams: streams,
      subtitles: subtitles,
      skipSegments: skipSegments,
    );
  }

  void _addSkip(
    List<AnimeSkipSegment> result,
    Object? value,
    AnimeSkipType type,
  ) {
    final range = _map(value);
    final start = _integer(range['start']);
    final end = _integer(range['end']);
    if (start != null && end != null && end > start) {
      result.add(AnimeSkipSegment(
        start: Duration(seconds: start),
        end: Duration(seconds: end),
        type: type,
      ));
    }
  }

  Future<Object?> _getJson(Uri uri) async {
    final response = await _client.get(uri, headers: requestHeaders);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
        'AniKage returned HTTP ${response.statusCode}.',
        uri,
      );
    }
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  AnimeCatalogItem? _catalogItem(Map<String, dynamic> data) {
    final slug = _string(data['slug']);
    final title = _title(data);
    if (slug.isEmpty || title.isEmpty) return null;
    return AnimeCatalogItem(
      id: slug,
      title: title,
      coverUri: _imageUri(data['coverImage']),
      subtitle: _catalogSubtitle(data),
    );
  }

  String _catalogSubtitle(Map<String, dynamic> data) => [
        _displayEnum(data['format']),
        if (_integer(data['year']) case final year?) '$year',
        if (_integer(data['averageScore']) case final score?)
          '${(score / 10).toStringAsFixed(1)} ★',
        if (_integer(data['subCount']) case final sub?) 'Sub $sub',
        if (_integer(data['dubCount']) case final dub?) 'Dub $dub',
      ].where((value) => value.isNotEmpty).join(' · ');

  String _title(Map<String, dynamic> data) {
    final title = _map(data['title']);
    return _string(title['english']).isNotEmpty
        ? _string(title['english'])
        : _string(title['romaji']).isNotEmpty
            ? _string(title['romaji'])
            : _string(title['userPreferred']);
  }

  Uri _mediaUri(String value, String kind) {
    final direct = Uri.tryParse(value);
    if (direct != null && direct.hasScheme) return direct;
    return _proxyUri.resolve('$kind/$value');
  }

  static String _sortValue(AnimeSearchSort sort) => switch (sort) {
        AnimeSearchSort.averageScore || AnimeSearchSort.score => 'score',
        AnimeSearchSort.trending => 'trending',
        AnimeSearchSort.favorites => 'favourites',
        AnimeSearchSort.dateAdded ||
        AnimeSearchSort.latestAdded ||
        AnimeSearchSort.latestUpdated =>
          'updated',
        AnimeSearchSort.releaseDate => 'year',
        AnimeSearchSort.name || AnimeSearchSort.nameDescending => 'title',
        AnimeSearchSort.popularity ||
        AnimeSearchSort.defaultOrder ||
        AnimeSearchSort.mostViewed ||
        AnimeSearchSort.episodeCount =>
          'popularity',
      };

  static AnimeStatus _status(Object? value) => switch (_string(value)) {
        'RELEASING' => AnimeStatus.ongoing,
        'FINISHED' => AnimeStatus.completed,
        'NOT_YET_RELEASED' => AnimeStatus.upcoming,
        'HIATUS' => AnimeStatus.hiatus,
        'CANCELLED' => AnimeStatus.cancelled,
        _ => AnimeStatus.unknown,
      };

  static String _subtitleLanguage(String label) {
    final normalized = label.toLowerCase();
    if (normalized.contains('portuguese')) return 'pt-BR';
    if (normalized.contains('spanish')) return 'es';
    if (normalized.contains('english')) return 'en';
    if (normalized.contains('french')) return 'fr';
    if (normalized.contains('german')) return 'de';
    return 'und';
  }

  static String _episodeId(double value) =>
      value == value.truncateToDouble() ? '${value.toInt()}' : '$value';

  static String _episodeNumber(String value) {
    final match = RegExp(r'(\d+(?:\.\d+)?)$').firstMatch(value);
    if (match == null) throw ArgumentError.value(value, 'episodeId');
    return match.group(1)!;
  }

  static String _displayEnum(Object? value) => _string(value)
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => part.length <= 3
          ? part.toUpperCase()
          : '${part[0]}${part.substring(1).toLowerCase()}')
      .join(' ');

  static Uri? _imageUri(Object? value) {
    if (value is String) return _absoluteUri(value);
    final images = _map(value);
    return _absoluteUri(images['extraLarge']) ??
        _absoluteUri(images['large']) ??
        _absoluteUri(images['medium']);
  }

  static Uri? _absoluteUri(Object? value) {
    final uri = Uri.tryParse(_string(value));
    return uri != null && uri.hasScheme ? uri : null;
  }

  static List<AnimeFilterOption> _options(Iterable<String> values) => values
      .map((value) =>
          AnimeFilterOption(value: value, label: _displayEnum(value)))
      .toList(growable: false);

  static Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static List<Map<String, dynamic>> _maps(Object? value) => value is List
      ? value.whereType<Map>().map(Map<String, dynamic>.from).toList()
      : const [];

  static List<String> _strings(Object? value) => value is List
      ? value.map(_string).where((item) => item.isNotEmpty).toList()
      : const [];

  static String _string(Object? value) => value?.toString().trim() ?? '';

  static int? _integer(Object? value) =>
      value is num ? value.toInt() : int.tryParse(_string(value));

  static double? _number(Object? value) =>
      value is num ? value.toDouble() : double.tryParse(_string(value));

  static const _genreNames = [
    'Action',
    'Adventure',
    'Comedy',
    'Drama',
    'Ecchi',
    'Fantasy',
    'Horror',
    'Mahou Shoujo',
    'Mecha',
    'Music',
    'Mystery',
    'Psychological',
    'Romance',
    'Sci-Fi',
    'Slice of Life',
    'Sports',
    'Supernatural',
    'Thriller',
  ];

  // AniKage's browse route uses AniList tag names verbatim. This is a snapshot
  // of the complete tag taxonomy currently exposed by the browse page.
  static const _tagNames = [
    '4-koma',
    'Achromatic',
    'Achronological Order',
    'Acrobatics',
    'Acting',
    'Adoption',
    'Advertisement',
    'Afterlife',
    'Age Gap',
    'Age Regression',
    'Agender',
    'Agriculture',
    'Airsoft',
    'Alchemy',
    'Aliens',
    'Alternate Universe',
    'American Football',
    'Amnesia',
    'Anachronism',
    'Ancient China',
    'Angels',
    'Animals',
    'Anthology',
    'Anthropomorphism',
    'Anti-Hero',
    'Archery',
    'Aromantic',
    'Arranged Marriage',
    'Artificial Intelligence',
    'Asexual',
    'Assassins',
    'Astronomy',
    'Athletics',
    'Augmented Reality',
    'Autobiographical',
    'Aviation',
    'Badminton',
    'Ballet',
    'Band',
    'Bar',
    'Baseball',
    'Basketball',
    'Battle Royale',
    'Biographical',
    'Bisexual',
    'Blackmail',
    'Board Game',
    'Boarding School',
    'Body Horror',
    'Body Image',
    'Body Swapping',
    'Bowling',
    'Boxing',
    'Boys\' Love',
    'Brainwashing',
    'Bullying',
    'Butler',
    'Calligraphy',
    'Camping',
    'Cannibalism',
    'Card Battle',
    'Cars',
    'Centaur',
    'CGI',
    'Cheerleading',
    'Chibi',
    'Chimera',
    'Chuunibyou',
    'Circus',
    'Class Struggle',
    'Classic Literature',
    'Classical Music',
    'Clone',
    'Coastal',
    'Cohabitation',
    'College',
    'Coming of Age',
    'Conspiracy',
    'Cosmic Horror',
    'Cosplay',
    'Cowboys',
    'Creature Taming',
    'Crime',
    'Criminal Organization',
    'Crossdressing',
    'Crossover',
    'Cult',
    'Cultivation',
    'Curses',
    'Cute Boys Doing Cute Things',
    'Cute Girls Doing Cute Things',
    'Cyberpunk',
    'Cyborg',
    'Cycling',
    'Dancing',
    'Death Game',
    'Delinquents',
    'Demons',
    'Denpa',
    'Desert',
    'Detective',
    'Dinosaurs',
    'Disability',
    'Dissociative Identities',
    'Dragons',
    'Drawing',
    'Drugs',
    'Dullahan',
    'Dungeon',
    'Dystopian',
    'E-Sports',
    'Eco-Horror',
    'Economics',
    'Educational',
    'Elderly Protagonist',
    'Elf',
    'Ensemble Cast',
    'Environmental',
    'Episodic',
    'Ero Guro',
    'Espionage',
    'Estranged Family',
    'Exorcism',
    'Fairy',
    'Fairy Tale',
    'Fake Relationship',
    'Family Life',
    'Fashion',
    'Female Harem',
    'Female Protagonist',
    'Femboy',
    'Fencing',
    'Filmmaking',
    'Firefighters',
    'Fishing',
    'Fitness',
    'Flash',
    'Food',
    'Football',
    'Foreign',
    'Found Family',
    'Fugitive',
    'Full CGI',
    'Full Color',
    'Gambling',
    'Gangs',
    'Gekiga',
    'Gender Bending',
    'Ghost',
    'Go',
    'Goblin',
    'Gods',
    'Golf',
    'Gore',
    'Graduation Project',
    'Guns',
    'Gyaru',
    'Handball',
    'Henshin',
    'Heterosexual',
    'Hikikomori',
    'Hip-hop Music',
    'Historical',
    'Homeless',
    'Horticulture',
    'Human Experimentation',
    'Ice Skating',
    'Idol',
    'Indigenous Cultures',
    'Inn',
    'Interspecies',
    'Isekai',
    'Iyashikei',
    'Jazz Music',
    'Josei',
    'Judo',
    'Kabuki',
    'Kaiju',
    'Karuta',
    'Kemonomimi',
    'Kids',
    'Kingdom Management',
    'Konbini',
    'Kuudere',
    'Lacrosse',
    'Language Barrier',
    'LGBTQ+ Themes',
    'Long Strip',
    'Lost Civilization',
    'Love Triangle',
    'Mafia',
    'Magic',
    'Mahjong',
    'Maids',
    'Makeup',
    'Male Harem',
    'Male Protagonist',
    'Manzai',
    'Marriage',
    'Martial Arts',
    'Matchmaking',
    'Matriarchy',
    'Medicine',
    'Medieval',
    'Memory Manipulation',
    'Mermaid',
    'Meta',
    'Metal Music',
    'Military',
    'Mixed Gender Harem',
    'Mixed Media',
    'Modeling',
    'Monster Boy',
    'Monster Girl',
    'Mopeds',
    'Motorcycles',
    'Mountaineering',
    'Musical Theater',
    'Mythology',
    'Natural Disaster',
    'Necromancy',
    'Nekomimi',
    'Ninja',
    'No Dialogue',
    'Noir',
    'Non-fiction',
    'Nudity',
    'Nun',
    'Office',
    'Office Lady',
    'Oiran',
    'Ojou-sama',
    'Orphan',
    'Otaku Culture',
    'Outdoor Activities',
    'Pandemic',
    'Parenthood',
    'Parkour',
    'Parody',
    'Philosophy',
    'Photography',
    'Pirates',
    'Poker',
    'Police',
    'Politics',
    'Polyamorous',
    'Post-Apocalyptic',
    'POV',
    'Pregnancy',
    'Primarily Adult Cast',
    'Primarily Animal Cast',
    'Primarily Child Cast',
    'Primarily Female Cast',
    'Primarily Male Cast',
    'Primarily Teen Cast',
    'Prison',
    'Prophecy',
    'Proxy Battle',
    'Psychosexual',
    'Puppetry',
    'Rakugo',
    'Real Robot',
    'Rehabilitation',
    'Reincarnation',
    'Religion',
    'Rescue',
    'Restaurant',
    'Revenge',
    'Reverse Isekai',
    'Robots',
    'Rock Music',
    'Rotoscoping',
    'Royal Affairs',
    'Rugby',
    'Rural',
    'Samurai',
    'Satire',
    'School',
    'School Club',
    'Scuba Diving',
    'Seinen',
    'Shapeshifting',
    'Ships',
    'Shogi',
    'Short-Form Chapter',
    'Shoujo',
    'Shounen',
    'Shrine Maiden',
    'Skateboarding',
    'Skeleton',
    'Slapstick',
    'Slavery',
    'Snowscape',
    'Software Development',
    'Space',
    'Space Opera',
    'Spearplay',
    'Steampunk',
    'Stop Motion',
    'Succubus',
    'Suicide',
    'Sumo',
    'Super Power',
    'Super Robot',
    'Superhero',
    'Surfing',
    'Surreal Comedy',
    'Survival',
    'Swimming',
    'Swordplay',
    'Table Tennis',
    'Tanks',
    'Tanned Skin',
    'Teacher',
    'Teens\' Love',
    'Tennis',
    'Terrorism',
    'Time Loop',
    'Time Manipulation',
    'Time Skip',
    'Tokusatsu',
    'Tomboy',
    'Torture',
    'Tragedy',
    'Trains',
    'Transgender',
    'Travel',
    'Triads',
    'Tsundere',
    'Twins',
    'Unrequited Love',
    'Urban',
    'Urban Fantasy',
    'Vampire',
    'Vertical Video',
    'Veterinarian',
    'Video Games',
    'Vikings',
    'Villainess',
    'Virtual World',
    'Vocal Synth',
    'Volleyball',
    'VTuber',
    'War',
    'Werewolf',
    'Wilderness',
    'Witch',
    'Work',
    'Wrestling',
    'Writing',
    'Wuxia',
    'Yakuza',
    'Yandere',
    'Youkai',
    'Yuri',
    'Zombie',
  ];
}
