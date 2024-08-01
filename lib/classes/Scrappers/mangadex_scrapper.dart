import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:star_scrapper_app/classes/Scrappers/class_scrappers.dart';

  class MangadexScrapper extends Scrapper {
    final String _baseUrl = 'https://api.mangadex.org';

    @override
    Future<List<dynamic>> getAll(String filter) async {  
    String url;  
    switch (filter.toLowerCase()) {  
      case 'recent':  
        url = '$_baseUrl/manga?order[latestUploadedChapter]=desc&includes[]=cover_art&limit=60';  
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
    final url = '$_baseUrl/manga/$mangaID?includes[]=cover_art&includes[]=author&includes[]=artist';
    final response = await http.get(Uri.parse(url), headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    });

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final mangaDetails = data['data'];
      final attributes = mangaDetails['attributes'];

      final titleLanguageKey = attributes['title'].keys.first;
      final title = attributes['title'][titleLanguageKey];

      final coverArt = mangaDetails['relationships'].firstWhere((relation) => relation['type'] == 'cover_art', orElse: () => {'id': null, 'attributes': {'fileName': null}});

      final author = mangaDetails['relationships'].firstWhere((relation) => relation['type'] == 'author', orElse: () => {'id': null}); 

      final artist = mangaDetails['relationships'].firstWhere((relation) => relation['type'] == 'artist', orElse: () => {'id': null});

      String getCoverImageUrl() {
      String coverFileName = coverArt['attributes']['fileName'] ?? '';  
      String mangaId = mangaDetails['id'];  
      return coverFileName.isNotEmpty  
          ? 'https://uploads.mangadex.org/covers/$mangaId/$coverFileName'  
          : 'https://via.placeholder.com/150';  
    }

      List<Map<String, String>> altTitles = [];
      for (var altTitle in attributes['altTitles']) {
        var altTitleLanguageKey = altTitle.keys.first;
        var altTitleValue = altTitle[altTitleLanguageKey];
        altTitles.add({ altTitleLanguageKey: altTitleValue});
      }


      List<dynamic> chapters = [];
      int offset = 0;
      bool hasMoreChapters = true;

      while (hasMoreChapters) {
        final chaptersFeedUrl = '$_baseUrl/manga/$mangaID/feed?order[volume]=desc&order[chapter]=desc&includes[]=scanlation_group&includes[]=user&limit=100&offset=$offset';

        final chaptersResponse = await http.get(Uri.parse(chaptersFeedUrl), headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        });


        if (chaptersResponse.statusCode == 200) {
          final chaptersData = jsonDecode(chaptersResponse.body);
          final List<dynamic> fetchedChapters = chaptersData['data'].map((chapter) {
            final chapterAttributes = chapter['attributes'];
            return {
              'id': chapter['id'],
              'title': chapterAttributes['title'],
              'chapter': chapterAttributes['chapter'],
              'volume': chapterAttributes['volume'],
              'language': chapterAttributes['language'],
              'pages': chapterAttributes['pages'],
              'translatedLanguage': chapterAttributes['translatedLanguage'],
              'uploader': chapterAttributes['uploader'],
              'publishedAt': chapterAttributes['publishAt'],
              'createdAt': chapterAttributes['createdAt'],
              'updatedAt': chapterAttributes['updatedAt'],
            };
          }).toList();

          chapters.addAll(fetchedChapters);
          offset += 100;
          hasMoreChapters = fetchedChapters.length == 100;
        } else {
          throw Exception('Failed to load chapters');
        }
      }


      final Map<String, dynamic> details = {
        'id': mangaDetails['id'],
        'title': title,
        'altTitles': altTitles,
        'description': attributes['description']['en'],
        'coverArt': {
          'id': coverArt['id'],
          'fileName': coverArt['attributes']['fileName'],
        },
        'coverImageUrl': getCoverImageUrl(),
        'mangaUrl': 'https://mangadex.org/manga/$mangaID',
        'author': {
          'id': author['id'],
          'name': author['attributes']['name'],
        },
        'artist': {
          'id': artist['id'],
          'name': artist['attributes']['name'],
        },
        'status': attributes['status'],
        'tags': attributes['tags'].map((tag) => tag['attributes']['name']['en']).toList(),
        'genres': data['data']['attributes']['genres'],
        'type': mangaDetails['type'],
        'chapters': chapters,
      };
      return details;
    } else {
      throw Exception('Failed to load data');
    }
  }

  @override
  Future<Map<String, dynamic>> getChapter(String chapterID) async {  
    final url = '$_baseUrl/at-home/server/$chapterID';  
    final response = await http.get(Uri.parse(url), headers: {  
      'Content-Type': 'application/json',  
      'Accept': 'application/json',  
    });  

    if (response.statusCode == 200) {  
      final data = jsonDecode(response.body);  
      if (data['result'] == 'ok') {  
        final baseUrl = data['baseUrl'] as String;  
        final chapterHash = data['chapter']['hash'] as String;  
        final List<String> imageFileNames = List<String>.from(data['chapter']['data']);  

        // Obter o diretório de documentos do aplicativo  
        final appDocDir = await getApplicationDocumentsDirectory();  
        final String tempMangaDir = path.join(appDocDir.path, 'temp', chapterID);  
        final String tempChapterDir = path.join(tempMangaDir, chapterHash);  

        await Directory(tempChapterDir).create(recursive: true);  

        List<String> imagePaths = [];  
        for (String filename in imageFileNames) {  
          final imageUrl = '$baseUrl/data/$chapterHash/$filename';  
          final imagePath = path.join(tempChapterDir, filename);  

          final imageResponse = await http.get(Uri.parse(imageUrl));  
          if (imageResponse.statusCode == 200) {  
            final file = File(imagePath);  
            await file.writeAsBytes(imageResponse.bodyBytes);  
            // Use o caminho do arquivo diretamente  
            imagePaths.add(file.path);  
          } else {  
            print('Failed to download image: $filename');  
          }  
        }  

        return {  
          'chapterID': chapterID,  
          'imagePaths': imagePaths,
          'chapterWebviewUrl': 'https://mangadex.org/chapter/$chapterID',  
        };  
      } else {  
        throw Exception('Failed to load chapter details: ${data['result']}');  
      }  
    } else {  
      throw Exception('Failed to load data: ${response.statusCode}');  
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