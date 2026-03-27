abstract class Scrapper {
  Future<List<dynamic>> getAll(String filter);
  Future<List<dynamic>> loadMore(String filter);
  Future<dynamic> getBookDetails(String mangaID);
  Stream<Map<String, dynamic>> getChapter(String chapterID, String mangaID);
  Stream<Map<String, dynamic>> retrieveLastChapter(String currentChapterId, String mangaId);
  Stream<Map<String, dynamic>> retrieveNextChapter(String currentChapterId, String mangaId);
  Future<dynamic> searchTitle(String title);
  String getTitle(dynamic bookDetails);
  String getCoverImageUrl(dynamic bookDetails);
  String getBookId(dynamic bookDetails);
}


