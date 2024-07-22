abstract class Scrapper {
  Future<List<dynamic>> getAll(String filter);
  Future<dynamic> getBookDetails(String mangaID);
  Future<void> getChapter(String chapterID);
  Future<dynamic> searchTitle(String title);
}


