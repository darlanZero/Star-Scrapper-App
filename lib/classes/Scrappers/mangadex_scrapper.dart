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

  Future<dynamic> searchTitle(String title) async {
    final response = await http.get(Uri.parse('$_baseUrl/manga?title=$title'));
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load data');
    }
  
  }
}