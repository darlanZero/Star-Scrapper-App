import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;
import 'package:star_scrapper_app/classes/Scrappers/class_scrappers.dart';

class Book {
  String id;
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
    required this.id,
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
      'id': id,
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
  Map<String, String> _localIds = {};


  @override
  Future<List<dynamic>> getAll(String filter) async {
    _currentPage = 0;
    _allResults.clear();
    await _loadLocalBookIds();
    return await _fetchResults(filter);
  }

  Future<void> _loadLocalBookIds()async{
    Directory directory = await getApplicationDocumentsDirectory();
    String filePath = path.join(directory.path, 'demon_sect_books_local_ids.json');
    File file = File(filePath);

    if (await file.exists()) {
      String content = await file.readAsString();
      _localIds = Map<String, String>.from(jsonDecode(content));
    }
  }

  Future<void> _saveLocalBookIds() async {
    Directory directory = await getApplicationDocumentsDirectory();
    String filePath = path.join(directory.path, 'demon_sect_books_local_ids.json');
    File file = File(filePath);
    await file.writeAsString(jsonEncode(_localIds));
  }

  String _generateRandomBookId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    Random rnd = Random();
    return String.fromCharCodes(Iterable.generate(12, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
  }

  @override
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
      var bookElements = document.querySelectorAll('.listupd .bsx a');
      print('bookElements: ${bookElements.length} in the page: $url');
      List<Book> books = bookElements.map((element) {
        String title = element.querySelector('.bigor .tt')?.text.trim() ?? 'No title';
        String link = element.attributes['href'] ?? '';

        if (link.isNotEmpty && !link.startsWith('/')) {
          link = '$baseUrl$link';
        }

        if (link.isEmpty) {
          print('Warning: Book $title has no available link');
        }
        String imageurl = element.querySelector('img')?.attributes['src'] ?? '';
        String latestChapter = element.querySelector('.adds .epxs')?.text.trim() ?? 'No chapter';
        String ratingString = element.querySelector('.adds .rt .numscore')?.text.trim() ?? '0';
        double rating = double.tryParse(ratingString) ?? 0.0;

        String id = _localIds.containsKey(link) ? _localIds[link]! : _generateRandomBookId();
        if (!_localIds.containsKey(link)) {
          _localIds[link] = id;
        }

        print('Processing book: $title, id:$id, link: $link, image: $imageurl, latestChapter: $latestChapter, rating: $rating');

        return Book(
          id: id,
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

      print('Books: ${books.length}');
      
      _allResults.addAll(books.map((book) => book.toMap()).toList());
      await _saveLocalBookIds();
      return _allResults;
    } else {
      throw Exception('Failed to load page');
    }
  }

  @override
  String getTitle(dynamic bookDetails) {
    if (bookDetails.containsKey('link')) {
      String link = bookDetails['link'];
      for (var book in _allResults) {
        if (book['link'] == link) {
          return book['title'];
        }
      }
    }
    return bookDetails['title'] ?? 'No title';
  }

  @override
  String getCoverImageUrl(dynamic bookDetails) {
    if (bookDetails.containsKey('link')) {
      String link = bookDetails['link'];
      for (var book in _allResults) {
        if (book['link'] == link) {
          return book['imageurl'];
        }
      }
    }
    return bookDetails['imageurl'] ?? 'https://via.placeholder.com/150';
  }

  @override
  String getBookId(dynamic bookDetails) {
    String link = bookDetails['link'];
    return _localIds[link] ?? _generateRandomBookId();
  }

  String _extractMangaId(String link) {
    if (link.isEmpty) {
      print('Warning: Book has no available link');
      return '';
    }

    final trimmedLink = link.endsWith('/') ? link.substring(0, link.length - 1) : link;

    final uri = Uri.parse(trimmedLink);
    if (uri.pathSegments.contains('comics')) {
      final index = uri.pathSegments.indexOf('comics');
      if (index != -1 && index + 1 < uri.pathSegments.length) {
        return uri.pathSegments[index + 1];
      }
    }

    print('Warning: Link structure not recognized: $link');
    return '';
  }

  @override
  Future<dynamic> getBookDetails(String mangaID) async {
    Map<String, dynamic>? selectedBook;
    for (var book in _allResults) {
      String link = book['link'];
      mangaID = _extractMangaId(link);

      String extractedMangaID = _extractMangaId(link);
      if (extractedMangaID == mangaID) {
        selectedBook = book;
        break;
      }
    }
    
    if (selectedBook == null) {
      throw Exception('Book not found for mangaID: $mangaID');
    }

    final url = '$baseUrl/comics/$mangaID';
    final response = await http.get(Uri.parse(url), headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9',
    });

    if (response.statusCode == 200) {
      final document = parser.parse(response.body);

      String authorText = document
        .querySelector('.tsinfo .imptdt:nth-child(3) .author .name')
        ?.text.trim() ?? 
        'Unknown Author';
      String statusText = document
        .querySelector('.tsinfo .imptdt:nth-child(1) i')
        ?.text.trim() ?? 
        'Unknown Status';
      List<String> tags = document
        .querySelectorAll('.wd-full .mgen a')
        .map((e) => e.text.trim())
        .toList();
      String typeText = document
        .querySelector('.tsinfo .imptdt:nth-child(2) a')
        ?.text.trim() ?? 
        'Unknown Type';
      String descriptionText = document
        .querySelector('.wd-full .desc')
        ?.text.trim() ?? 
        'No description';

      
      return {
        'id': selectedBook != null ? selectedBook['id'] : mangaID,
        'title': selectedBook != null ? selectedBook['title'] : 'No title',
        'altTitles': [],
        'description': descriptionText,
        'coverArt': {
          'id': null,
          'filename':  selectedBook['imageurl'],
        },
        'mangaUrl': url,
        'author': {
          'id': '',
          'name': authorText,
        },
        'artist': {
          'id': '',
          'name': authorText,
        },
        'status': statusText,
        'tags': tags,
        'type': typeText,
        'chapters': [],
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
  Stream<Map<String, dynamic>> retrieveLastChapter(String currentChapterId, String mangaId) async* {
    yield {'type': 'error', 'message': 'Navegação entre capítulos não é suportada nesta fonte.'};
  }

  @override
  Stream<Map<String, dynamic>> retrieveNextChapter(String currentChapterId, String mangaId) async* {
    yield {'type': 'error', 'message': 'Navegação entre capítulos não é suportada nesta fonte.'};
  }

  @override
  Stream<Map<String, dynamic>> getChapter(String chapterID, String mangaID) async* {
    yield {'error': 'Not implemented yet'};
  }

  @override
  Future<List<dynamic>> searchTitle(String title) async {
    final url = '$baseUrl/?s=${Uri.encodeComponent(title)}';
    final response = await http.get(Uri.parse(url), headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Accept': 'text/html,application/xhtml+xml',
    });

    if (response.statusCode != 200) throw Exception('Failed to search');

    final document = parser.parse(response.body);
    final bookElements = document.querySelectorAll('.listupd .bsx a');
    await _loadLocalBookIds();

    final results = bookElements.map((element) {
      final title = element.querySelector('.bigor .tt')?.text.trim() ?? 'No title';
      final link = element.attributes['href'] ?? '';
      final imageUrl = element.querySelector('img')?.attributes['src'] ?? '';
      final latestChapter = element.querySelector('.adds .epxs')?.text.trim() ?? '';

      final id = _localIds.containsKey(link)
          ? _localIds[link]!
          : _generateRandomBookId();
      if (!_localIds.containsKey(link)) _localIds[link] = id;

      return {
        'id': id,
        'title': title,
        'link': link,
        'imageurl': imageUrl,
        'latestChapter': latestChapter,
        'type': 'manga',
      };
    }).toList();

    await _saveLocalBookIds();
    return results;
  }
}

