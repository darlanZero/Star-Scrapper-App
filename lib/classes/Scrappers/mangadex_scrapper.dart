import 'dart:io';

import 'package:http/http.dart' as http;
import 'dart:convert';

class MangadexScrapper {
  final String _baseUrl = 'https://api.mangadex.org';

  Future<dynamic> getAll(String filter) async {
    String url;
    switch (filter.toLowerCase()) {
      case 'recent':
        url = '$_baseUrl/manga?order[updatedAt]=desc';
        break;

      case 'popular':
        url = '$_baseUrl/manga?order[relevance]=desc';
        break;

      case 'first': 
        url = '$_baseUrl/manga?order[updatedAt]=asc';
        break;

      case 'A-Z':
        url = '$_baseUrl/manga?order[title]=asc';
        break;

      case 'Z-A':
        url = '$_baseUrl/manga?order[title]=desc';
        break;
      default:
        throw Exception('Invalid filter');
    }

    final response = await http.get(Uri.parse(url));
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load data');
    }
  }

  Future<dynamic> getBookDetails(String mangaID) async {
    final url = '$_baseUrl/manga/$mangaID/feed';
    final response = await http.get(Uri.parse(url), headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    });

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final mangaDetails = data['data'][0];
      final attributes = mangaDetails['attributes'];

      final titleLanguageKey = attributes['title'].keys.first;
      final title = attributes['title'][titleLanguageKey];

      List<Map<String, String>> altTitles = [];
      for (var altTitle in attributes['altTitles']) {
        var altTitleLanguageKey = altTitle.keys.first;
        var altTitleValue = altTitle[altTitleLanguageKey];
        altTitles.add({ altTitleLanguageKey: altTitleValue});
      }

      final Map<String, dynamic> details = {
        'id': mangaDetails['id'],
        'title': title,
        'altTitles': altTitles,
        'description': attributes['description']['en'],
        'coverImage': mangaDetails['relationships'].firstWhere((relation) => relation['type'] == 'cover_art'),
        'author': mangaDetails['relationships'].firstWhere((relation) => relation['type'] == 'author', orElse: () => null)?['id'],
        'status': attributes['status'],
        'tags': attributes['tags'].map((tag) => tag['attributes']['name']['en']).toList(),
        'genres': data['data']['attributes']['genres'],
        'type': mangaDetails['type'],
        'chapters': _extractChapters(data['data']['relationships']),
      };
      return details;
    } else {
      throw Exception('Failed to load data');
    }
  }

  List<dynamic> _extractChapters(List<dynamic> relationships) {
    return relationships.where((relation) => relation['type'] == 'chapter').map((chapter) {
      return {
        'title': chapter['attributes']['title'],
        'chapter': chapter['attributes']['chapter'],
        'volume': chapter['attributes']['volume'],
        'language': chapter['attributes']['language'],
      };
    }).toList();
  }

  Future<void> getChapter(String chapterID) async {
    final url = '$_baseUrl/at-home/server/$chapterID';
    final response = await http.get(Uri.parse(url), headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    });

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['result' == 'ok']) {
        final baseUrl = data['baseUrl'];
        final chapterHash = data['chapter']['hash'];
        final List<String> imageFileNames = data['chapter']['data'];

        final String tempMangaDir = '/lib/temp/$chapterID';
        final String tempChapterDir = '$tempMangaDir/$chapterHash';

        await Directory(tempChapterDir).create(recursive: true);

        for (String filename in imageFileNames) {
          final imageUrl = '$baseUrl/$chapterHash/$filename';
          final imagePath = '$tempChapterDir/$filename';

          final imageResponse = await http.get(Uri.parse(imageUrl));
          if (imageResponse.statusCode == 200) {
            final file = File(imagePath);
            await file.writeAsBytes(imageResponse.bodyBytes);
          } else {
            throw Exception('Failed to download image');
          }
        } 
      } else {
        throw Exception('Failed to load chapter details');
      }
    } else {
      throw Exception('Failed to load data');
    }
  }

  Future<dynamic> searchTitle(String title) async {
    final response = await http.get(Uri.parse('$_baseUrl/manga?title=$title'));
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load data');
    }
  }
}