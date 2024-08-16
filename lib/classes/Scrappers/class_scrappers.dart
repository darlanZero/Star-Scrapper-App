abstract class Scrapper {
  Future<List<dynamic>> getAll(String filter);
  Future<dynamic> getBookDetails(String mangaID);
  Stream<Map<String, String>> getChapter(String chapterID);
  Future<dynamic> searchTitle(String title);
}


