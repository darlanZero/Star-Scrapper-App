import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/classes/Scrappers/class_scrappers.dart';

class Book {
  String title;
  String link;
  String imageUrl;
  String latestChapter;
  double rating;
  String author;
  String status;
  List<String> tags;
  String type;
  Book({
    required this.title,
    required this.link, 
    required this.imageUrl,
    required this.latestChapter,
    required this.rating,
    required this.author,
    required this.status, 
    required this.tags, 
    required this.type
  });

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'link': link,
      'imageurl': imageUrl,
      'latestChapter': latestChapter,
      'rating': rating,
      'author': author,
      'status': status,
      'tags': tags,
      'type': type
    };
  }
}

class DemonSectScrapper extends Scrapper {
  final String baseUrl = 'https://seitacelestial.com';
  int _currentPage = 0;
  List<dynamic> _allResults = [];


  @override
  Future<List<dynamic>> getAll(String filter) async {
    _currentPage = 1;
    _allResults.clear();
    return await _fetchResults(filter);
  }

  Future<List<dynamic>> loadMore(String filter) async {
    _currentPage++;
    return await _fetchResults(filter);
  }

  Future<List<dynamic>> _fetchResults(String filter) async {
    String url;
    switch (filter.toLowerCase()) {
      case 'recent':
        url = '$baseUrl/comics/?page=${_currentPage + 1}&type=&order=update';
        break;
      case 'popular':
        url = '$baseUrl/comics/?page=${_currentPage + 1}&type=&order=popular';
        break;
      case 'trending':
        url = '$baseUrl/comics/?page=${_currentPage + 1}&type=&order=trending';
        break;
      case 'added':
        url = '$baseUrl/comics/?page=${_currentPage + 1}&type=&order=latest';
        break;
      case 'a-z':
        url = '$baseUrl/comics/?page=${_currentPage + 1}&type=&order=title';
        break;
      case 'z-a':
        url = '$baseUrl/comics/?page=${_currentPage + 1}&type=&order=titlereverse';
        break;
      default:
        throw Exception('Invalid filter');
    }

    final response = await http.get(Uri.parse(url), headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9',
    });

    if (response.statusCode == 200) {
      final document = parser.parse(response.body);
      var bookElements = document.querySelectorAll('.listupd .bs .bsx a');
      List<Book> books = bookElements.map((element) {
        String title = element.querySelector('.bigor .tt')?.text.trim() ?? 'No title';
        String link = element.querySelector('a')?.attributes['href'] ?? '';
        String imageurl = element.querySelector('img')?.attributes['src'] ?? '';
        String latestChapter = element.querySelector('.adds .epxs')?.text.trim() ?? 'No chapter';
        String ratingString = element.querySelector('.adds .rt .numscore')?.text.trim() ?? '0';
        double rating = double.tryParse(ratingString) ?? 0.0;

        return Book(
          title: title, 
          link: link, 
          imageUrl: imageurl, 
          latestChapter: latestChapter, 
          rating:rating,
          author: 'Unknown Author',
          status: 'Unknown Status',
          tags: ['tag1, tag2'],
          type: 'Unknown Type'
        );
      }).toList();
      
      _allResults.addAll(books.map((book) => book.toMap()).toList());
      return _allResults;
    } else {
      throw Exception('Failed to load page');
    }
  }

  String getTitle(dynamic bookDetails) {
    String url = '';

    if (bookDetails.containsKey('title')) {
      for (var book in _allResults) {
        if (book['link'] == url) {
          return book['title'];
        }
      }
    }
    return bookDetails['title'] ?? 'No title';
  }
  @override
  Future<dynamic> getBookDetails(String mangaID) async {
    final url = '$baseUrl/comics/$mangaID';
    final response = await http.get(Uri.parse(url), headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9',
    });

    if (response.statusCode == 200) {
      final document = parser.parse(response.body);

      String author = document.querySelector('.tsinfo .imptdt:nth-child(3) .author .name')?.text.trim() ?? 'Unknown Author';
      String status = document.querySelector('.tsinfo .imptdt:nth-child(1) i')?.text.trim() ?? 'Unknown Status';
      List<String> tags = document.querySelectorAll('.wd-full .mgen a').map((e) => e.text.trim()).toList();
      String type = document.querySelector('.tsinfo .imptdt:nth-child(2) a')?.text.trim() ?? 'Unknown Type';

      for (var book in _allResults) {
        if (book['link'] == url) {
          book['author'] = author;
          book['status'] = status;
          book['tags'] = tags;
          book['type'] = type;
          break;
        }
      }

      return {
        'author': author,
        'status': status,
        'tags': tags,
        'type': type
      };
    } else {
      throw Exception('Failed to load page');
    }
  }

  Future<void> saveLocalIds() async {
    Directory directory = await getApplicationDocumentsDirectory();
    String filePath = path.join(directory.path, 'local_ids.json');
    File file = File(filePath);

    List<String> ids = _allResults.map((book) => book['id'] as String).toList();
    await file.writeAsString(jsonEncode(ids));
  }

  Future<List<String>> loadLocalIds() async {
    try {
      Directory directory = await getApplicationDocumentsDirectory();
      String filePath = path.join(directory.path, 'local_ids.json');
      File file = File(filePath);

      if (await file.exists()) {
        String content = await file.readAsString();
        List<dynamic> jsonData = jsonDecode(content);
        return jsonData.cast<String>();
      } else {
        return [];
      }
    } catch (e) {
      return [];
    }
  }

  @override
  Stream<Map<String, dynamic>> getChapter(String chapterID, String mangaID) async* {
    yield {'error': 'Not implemented yet'};
  }

   @override
  Future<dynamic> searchTitle(String title) async {
    final response = await http.get(Uri.parse('$baseUrl/?s=$title'));
    
    if (response.statusCode == 200) {
      return parser.parse(response.body);
    } else {
      throw Exception('Failed to load data');
    }
  }
}

