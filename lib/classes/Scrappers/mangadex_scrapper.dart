import 'dart:io';

import 'package:http/http.dart' as http;
import 'dart:convert';

import 'package:star_scrapper_app/classes/Scrappers/class_scrappers.dart';

  class MangadexScrapper extends Scrapper {
    final String _baseUrl = 'https://api.mangadex.org';

    @override
    Future<List<dynamic>> getAll(String filter) async {  
    String url;  
    switch (filter.toLowerCase()) {  
      case 'recent':  
        url = '$_baseUrl/manga?order[updatedAt]=desc&includes[]=cover_art&limit=60';  
        break;  
      case 'popular':  
        url = '$_baseUrl/manga?order[relevance]=desc&includes[]=cover_art&limit=60';  
        break;  
      case 'first':   
        url = '$_baseUrl/manga?order[updatedAt]=asc&includes[]=cover_art&limit=60';  
        break;  
      case 'a-z':  
        url = '$_baseUrl/manga?order[title]=asc&includes[]=cover_art&limit=60';  
        break;  
      case 'z-a':  
        url = '$_baseUrl/manga?order[title]=desc&includes[]=cover_art&limit=60';  
        break;  
      default:  
        throw Exception('Invalid filter');  
    }  

    final response = await http.get(Uri.parse(url), headers: {  
      'Content-Type': 'application/json',  
      'Accept': 'application/json',  
    });  
    
    if (response.statusCode == 200) {  
      final data = jsonDecode(response.body);  
      if (data['result'] == 'ok') {  
        final List<dynamic> mangaList = data['data'];  
        final mangaDetails = mangaList.map((manga) {  
          final attributes = manga['attributes'];  
          final titleLanguageKey = attributes['title'].keys.first;  
          final title = attributes['title'][titleLanguageKey];  
          final coverArt = manga['relationships'].firstWhere(  
            (relation) => relation['type'] == 'cover_art',  
            orElse: () => {'id': null, 'attributes': {'fileName': null}},  
          );  
          return {  
            'id': manga['id'],  
            'title': title,  
            'coverArt': {  
              'id': coverArt['id'],  
              'fileName': coverArt['attributes']['fileName'],  
            },  
            'author': manga['relationships'].firstWhere(  
              (relation) => relation['type'] == 'author',  
              orElse: () => {'id': null},  
            )['id'],  
            'status': attributes['status'],  
            'tags': attributes['tags'].map((tag) => tag['attributes']['name']['en']).toList(),  
            'type': manga['type'],  
          };  
        }).toList();  
        return mangaDetails;  
      } else {  
        throw Exception('API returned an error: ${data['result']}');  
      }  
    } else {  
      throw Exception('Failed to load data');  
    }  
  }

  String getTitle(dynamic bookDetails) {
    return bookDetails['title'] ?? 'No title';
  }

  String getCoverImageUrl(dynamic bookDetails) {  
    String coverFileName = bookDetails['coverArt']['fileName'] ?? '';  
    String mangaId = bookDetails['id'];  
    return coverFileName.isNotEmpty  
        ? 'https://uploads.mangadex.org/covers/$mangaId/$coverFileName'  
        : 'https://via.placeholder.com/150';  
  }  

  String getBookId(dynamic bookDetails) {  
    return bookDetails['id'];  
  }    

  @override
  Future<dynamic> getBookDetails(String mangaID) async {
    final url = '$_baseUrl/manga/$mangaID?includes[]=cover_art';
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
        'coverArt': {
          ...mangaDetails['relationships'].firstWhere((relation) => relation['type'] == 'cover_art'),
          'relationships': mangaDetails['relationships']
          .firstWhere((relation) => relation['type'] == 'cover_art')['attributes']['fileName'],
        },
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

  @override
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

  @override
  Future<dynamic> searchTitle(String title) async {
    final response = await http.get(Uri.parse('$_baseUrl/manga?title=$title'));
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load data');
    }
  }
}