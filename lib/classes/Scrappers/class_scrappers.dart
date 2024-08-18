abstract class Scrapper {
  Future<List<dynamic>> getAll(String filter);
  Future<dynamic> getBookDetails(String mangaID);
  Stream<Map<String, dynamic>> getChapter(String chapterID, String mangaID);
  Future<dynamic> searchTitle(String title);
}


