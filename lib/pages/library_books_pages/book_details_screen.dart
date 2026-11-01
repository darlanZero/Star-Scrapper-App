import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, kDebugMode;
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/application/trackers/tracker_controller.dart';
import 'package:star_scrapper_app/classes/app_state.dart';
import 'package:star_scrapper_app/classes/static/fonts_provider.dart';
import 'package:star_scrapper_app/components/Shared/source_badge.dart';
import 'package:star_scrapper_app/data/library/manga_reminder_store.dart';
import 'package:star_scrapper_app/domain/library/manga_reminder.dart';
import 'package:star_scrapper_app/domain/sources/manga_source.dart';
import 'package:star_scrapper_app/pages/library_books_pages/chapter_book_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart' as flutter_webview;
import 'package:webview_windows/webview_windows.dart' as webview_windows;

class BookDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> bookDetails;

  /// Scrapper a ser usado nesta tela. Se null, usa o selectedFontApi global.
  final MangaSource? scrapper;
  final void Function(MangaTaxonomyKind kind, String id, String name)?
      onTaxonomySelected;
  const BookDetailsScreen({
    super.key,
    required this.bookDetails,
    this.scrapper,
    this.onTaxonomySelected,
  });

  @override
  State<BookDetailsScreen> createState() => _BookDetailsScreenState();
}

enum _ChapterProgressAction {
  markOne,
  markThrough,
  unmarkOne,
  unmarkThrough,
}

class _BookDetailsScreenState extends State<BookDetailsScreen> {
  late Map<String, dynamic> bookDetails;
  bool _isChapterReversed = false;
  String _selectedLanguagePrefix = '';
  bool _showWebView = false;
  // ignore: unused_field
  bool _isLoadingChapter = false;
  String? _selectedChapterId;
  bool _syncingTrackers = false;
  final MangaReminderStore _reminderStore = MangaReminderStore();
  Future<List<MangaReminder>>? _remindersFuture;

  Future<void>? _updateFuture;

  List<MangaTaxonomyLink> get _taxonomyLinks =>
      ((bookDetails['taxonomyLinks'] as List?) ?? const [])
          .whereType<Map>()
          .map(MangaTaxonomyLink.fromJson)
          .where((link) => link.id.isNotEmpty && link.name.isNotEmpty)
          .toList(growable: false);

  MangaTaxonomyLink? _taxonomyLink(String name, {MangaTaxonomyKind? kind}) {
    final normalized = name.trim().toLowerCase();
    for (final link in _taxonomyLinks) {
      if ((kind == null || link.kind == kind) &&
          link.name.trim().toLowerCase() == normalized) {
        return link;
      }
    }
    return null;
  }

  void _selectTaxonomy(MangaTaxonomyLink link) {
    widget.onTaxonomySelected?.call(link.kind, link.id, link.name);
    Navigator.of(context).pop();
  }

  Widget _buildTagChip(String rawTag, TextStyle? style) {
    final tag = rawTag.trim();
    final taxonomyLink = _taxonomyLink(tag);
    final legacyTagSearch =
        {'nhentai', 'nhentai_xxx'}.contains(widget.scrapper?.id);
    final canSearch = widget.onTaxonomySelected != null &&
        tag.isNotEmpty &&
        (taxonomyLink != null || legacyTagSearch);
    final chip = Chip(
      label: Text(tag, style: style),
      backgroundColor: Colors.black.withValues(alpha: .62),
      shadowColor: Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      visualDensity: VisualDensity.compact,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: const StadiumBorder(),
      side: const BorderSide(color: Colors.white24),
    );
    if (!canSearch) return chip;
    return GestureDetector(
      onTap: () => taxonomyLink == null
          ? _applyTagSearch([tag])
          : _selectTaxonomy(taxonomyLink),
      onLongPress: legacyTagSearch ? _showCombinedTagSearch : null,
      child: chip,
    );
  }

  Widget _buildPersonLabel(
    dynamic rawName,
    String fallback, {
    required double fontSize,
    MangaTaxonomyKind kind = MangaTaxonomyKind.artist,
  }) {
    final name = _extractPersonName(rawName);
    final link = name == null ? null : _taxonomyLink(name, kind: kind);
    final text = Text(
      name ?? fallback,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
        color:
            link == null ? Colors.grey : Theme.of(context).colorScheme.primary,
      ),
    );
    if (link == null || widget.onTaxonomySelected == null) return text;
    return InkWell(
      onTap: () => _selectTaxonomy(link),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
        child: text,
      ),
    );
  }

  Widget _buildScrollableTags() {
    final tags = ((bookDetails['tags'] as List?) ?? const [])
        .map((tag) => tag.toString().trim())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (tags.isEmpty) return const SizedBox.shrink();

    return Semantics(
      label: 'Manga tags. Swipe horizontally to see more.',
      child: SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: tags.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (context, index) => _buildTagChip(
            tags[index],
            const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  void _applyTagSearch(List<String> tags) {
    if (tags.isEmpty || widget.onTaxonomySelected == null) return;
    final ids = tags.map((tag) => '/tag/${_slug(tag)}/').join('|');
    widget.onTaxonomySelected!(MangaTaxonomyKind.tag, ids, tags.join(', '));
    Navigator.of(context).pop();
  }

  Future<void> _showCombinedTagSearch() async {
    final tags = ((bookDetails['tags'] as List?) ?? const [])
        .map((tag) => tag.toString().trim())
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);
    final selected = <String>{};
    final result = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Combine tags'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in tags)
                    FilterChip(
                      label: Text(tag),
                      selected: selected.contains(tag),
                      onSelected: (value) => setDialogState(() =>
                          value ? selected.add(tag) : selected.remove(tag)),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, selected.toList()),
              child: Text('Search (${selected.length})'),
            ),
          ],
        ),
      ),
    );
    if (result != null && mounted) _applyTagSearch(result);
  }

  String _slug(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  Widget _sourceCoverImage({
    required MangaSource? source,
    required String imageUrl,
    required BoxFit fit,
    double? width,
    double? height,
    Color? color,
    BlendMode? colorBlendMode,
  }) {
    final uri = Uri.tryParse(imageUrl);
    if (source case final BrowserImageMangaSource browserSource
        when uri != null) {
      return FutureBuilder(
        future: browserSource.loadBrowserImage(uri),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const ColoredBox(
              color: Colors.black12,
              child: Center(child: Icon(Icons.broken_image_outlined)),
            );
          }
          final bytes = snapshot.data;
          if (bytes == null) {
            return const ColoredBox(
              color: Colors.black12,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          return Image.memory(
            bytes,
            width: width,
            height: height,
            fit: fit,
            color: color,
            colorBlendMode: colorBlendMode,
            gaplessPlayback: true,
          );
        },
      );
    }
    return Image.network(
      imageUrl,
      width: width,
      height: height,
      fit: fit,
      headers: source?.coverImageHeaders,
      color: color,
      colorBlendMode: colorBlendMode,
      errorBuilder: (_, __, ___) => const ColoredBox(
        color: Colors.black12,
        child: Center(child: Icon(Icons.broken_image_outlined)),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    bookDetails = Map<String, dynamic>.from(widget.bookDetails);
    if (widget.scrapper != null) {
      bookDetails['sourceId'] ??= widget.scrapper!.id;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final fontProvider = Provider.of<FontProvider>(context, listen: false);

      // Se o livro veio da busca online (sem capítulos), busca os detalhes completos.
      // Usa o scrapper explícito, ou tenta detectá-lo pelo domínio da capa.
      final hasChapters =
          (bookDetails['chapters'] as List?)?.isNotEmpty == true;
      final effectiveScrapper =
          widget.scrapper ?? fontProvider.findScrapperForBook(bookDetails);
      if (effectiveScrapper != null) {
        bookDetails['sourceId'] ??= effectiveScrapper.id;
      }
      fontProvider.addBookToReadBooks(bookDetails);
      if (!hasChapters && effectiveScrapper != null) {
        setState(() {
          _updateFuture = fontProvider
              .updateBookDetails(
            bookDetails['id'],
            scrapper: effectiveScrapper,
          )
              .then((_) {
            // Atualiza o estado local com os dados carregados
            final updated = fontProvider.favoritedBooks.firstWhere(
              (b) => b['id'] == bookDetails['id'],
              orElse: () => fontProvider.readBooks.firstWhere(
                (b) => b['id'] == bookDetails['id'],
                orElse: () => bookDetails,
              ),
            );
            if (mounted) setState(() => bookDetails = updated);
          });
        });
      }
      _refreshReminders();
    });
    Provider.of<FontProvider>(context, listen: false).loadSelectedChapterId();
  }

  void _toogleChapterOrder() {
    setState(() {
      _isChapterReversed = !_isChapterReversed;
    });
  }

  void _filterChaptersByLanguage(String languagePrefix) {
    setState(() {
      _selectedLanguagePrefix = languagePrefix;
    });
  }

  MangaSource _effectiveScrapper() {
    final fontProvider = Provider.of<FontProvider>(context, listen: false);
    return widget.scrapper ??
        fontProvider.findScrapperForBook(bookDetails) ??
        fontProvider.selectedFontApi;
  }

  void _refreshReminders() {
    if (!mounted) return;
    final source = _effectiveScrapper();
    final mangaId = bookDetails['id']?.toString() ?? '';
    setState(() {
      _remindersFuture = mangaId.isEmpty
          ? Future.value(const <MangaReminder>[])
          : _reminderStore.loadForManga(
              sourceId: source.id,
              mangaId: mangaId,
            );
    });
  }

  Widget _buildContinueCard(
    List<dynamic> chapters,
    FontProvider fontProvider,
  ) {
    final mangaId = bookDetails['id']?.toString() ?? '';
    final lastRead = fontProvider.lastReadedChapterId[mangaId];
    if (lastRead == null) return const SizedBox.shrink();
    final chapterId = lastRead['id']?.toString() ?? '';
    Map<dynamic, dynamic>? chapter;
    for (final candidate in chapters) {
      if (candidate is Map && candidate['id']?.toString() == chapterId) {
        chapter = Map<dynamic, dynamic>.from(candidate);
        break;
      }
    }
    if (chapter == null) return const SizedBox.shrink();

    final rawNumber =
        (chapter['chapter'] ?? lastRead['title'] ?? '').toString().trim();
    final number = rawNumber
        .replaceFirst(
          RegExp(
            r'^(?:chapter|cap[ií]tulo|cap\.?)\s*',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
    final label = number.isEmpty ? _buildChapterLabel(chapter) : number;
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(top: 14, bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openChapter(chapter!),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: colors.primaryContainer,
                foregroundColor: colors.onPrimaryContainer,
                child: const Icon(Icons.play_arrow_rounded),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Continue from chapter $label',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Resume from your saved reading position',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReminderSection() {
    return FutureBuilder<List<MangaReminder>>(
      future: _remindersFuture,
      builder: (context, snapshot) {
        final reminders = snapshot.data ?? const <MangaReminder>[];
        final grouped = <String, List<MangaReminder>>{};
        for (final reminder in reminders) {
          grouped.putIfAbsent(reminder.chapterId, () => []).add(reminder);
        }
        final subtitle = snapshot.connectionState == ConnectionState.waiting
            ? 'Loading saved moments…'
            : reminders.isEmpty
                ? 'Save key images from the reader to remember the story'
                : '${reminders.length} saved ${reminders.length == 1 ? 'moment' : 'moments'}';
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            leading: const Icon(Icons.collections_bookmark_outlined),
            title: const Text(
              'Story reminders',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(subtitle),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            children: [
              if (snapshot.hasError)
                ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: const Text('Could not load story reminders'),
                  subtitle: Text(snapshot.error.toString()),
                  trailing: IconButton(
                    tooltip: 'Try again',
                    onPressed: _refreshReminders,
                    icon: const Icon(Icons.refresh),
                  ),
                )
              else if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                )
              else if (reminders.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 8, 12, 16),
                  child: Text(
                    'Long-press an image in the reader and choose '
                    '“Save as Story Reminder”.',
                    textAlign: TextAlign.center,
                  ),
                )
              else
                for (final entry in grouped.entries)
                  _buildReminderChapter(entry.value),
            ],
          ),
        );
      },
    );
  }

  Widget _buildReminderChapter(List<MangaReminder> reminders) {
    final first = reminders.first;
    final chapterName = first.chapterNumber.trim().isNotEmpty
        ? 'Chapter ${first.chapterNumber}'
        : first.chapterTitle.trim().isNotEmpty
            ? first.chapterTitle
            : 'Chapter';
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 8),
      childrenPadding: EdgeInsets.zero,
      leading: const Icon(Icons.menu_book_outlined),
      title: Text(chapterName),
      subtitle: Text(
        '${reminders.length} ${reminders.length == 1 ? 'reminder' : 'reminders'}',
      ),
      children: [
        for (final reminder in reminders) _buildReminderTile(reminder),
      ],
    );
  }

  Widget _buildReminderTile(MangaReminder reminder) {
    return FutureBuilder<File>(
      future: _reminderStore.imageFile(reminder),
      builder: (context, snapshot) {
        final file = snapshot.data;
        final note = reminder.note.trim();
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          child: InkWell(
            onTap: file == null ? null : () => _showReminder(reminder, file),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 76,
                      height: 96,
                      child: file == null
                          ? const ColoredBox(
                              color: Colors.black12,
                              child: Center(
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : Image.file(
                              file,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const ColoredBox(
                                color: Colors.black12,
                                child: Icon(Icons.broken_image_outlined),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          note.isEmpty ? 'Saved key moment' : note,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Page ${reminder.pageNumber} • '
                          '${DateFormat.yMMMd().format(reminder.createdAt.toLocal())}',
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Delete reminder',
                    onPressed: () => _deleteReminder(reminder),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showReminder(MangaReminder reminder, File file) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 720,
            maxHeight: MediaQuery.sizeOf(dialogContext).height * .88,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                automaticallyImplyLeading: false,
                title: Text(
                  reminder.chapterNumber.isEmpty
                      ? 'Story reminder'
                      : 'Chapter ${reminder.chapterNumber} • '
                          'Page ${reminder.pageNumber}',
                ),
                actions: [
                  IconButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Flexible(
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 5,
                  child: Image.file(file, fit: BoxFit.contain),
                ),
              ),
              if (reminder.note.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(reminder.note),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteReminder(MangaReminder reminder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete reminder?'),
        content: const Text(
          'The saved image and its annotation will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _reminderStore.delete(reminder);
    _refreshReminders();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    bool isDesktop = MediaQuery.of(context).size.width > 600;

    return Scaffold(
        backgroundColor: theme.selectedTheme.scaffoldBackgroundColor,
        body: _showWebView
            ? _buildWebView(context)
            : FutureBuilder<void>(
                future: _updateFuture,
                builder: (context, snapshot) {
                  if (_updateFuture == null) {
                    return _reactiveDetailsBook(
                        context, isDesktop, theme, bookDetails);
                  } else {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    } else if (snapshot.hasError) {
                      return Center(child: Text('Error: ${snapshot.error}'));
                    } else {
                      return _reactiveDetailsBook(
                          context, isDesktop, theme, bookDetails);
                    }
                  }
                }),
        floatingActionButton: Column(mainAxisSize: MainAxisSize.min, children: [
          FloatingActionButton(
            heroTag: 'reverse_chapters',
            onPressed: _toogleChapterOrder,
            hoverColor: Colors.blueGrey,
            child: Icon(
              _isChapterReversed ? Icons.arrow_downward : Icons.arrow_upward,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8.0),
          FloatingActionButton(
              heroTag: 'update_book_details',
              onPressed: () async {
                final fontProvider =
                    Provider.of<FontProvider>(context, listen: false);
                final bookId = widget.bookDetails['id'];

                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Row(children: const [
                    Text('Updating book details...'),
                    SizedBox(width: 10),
                    CircularProgressIndicator(),
                  ]),
                  duration: const Duration(minutes: 1),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10.0)),
                ));

                final effectiveScrapper = widget.scrapper ??
                    fontProvider.findScrapperForBook(bookDetails);
                try {
                  await fontProvider.updateBookDetails(bookId,
                      scrapper: effectiveScrapper);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Book details updated successfully!'),
                    duration: Duration(seconds: 2),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10.0)),
                    backgroundColor: Colors.green,
                  ));

                  final updatedBook = fontProvider.favoritedBooks.firstWhere(
                    (book) => book['id'] == bookId,
                    orElse: () => bookDetails,
                  );

                  setState(() {
                    _updateFuture = null;
                    bookDetails = updatedBook;
                  }); // Refresh the screen
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Failed to update book details: $e'),
                    duration: Duration(seconds: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10.0)),
                    backgroundColor: Colors.red,
                  ));

                  if (kDebugMode) {
                    print('Failed to update book details: $e');
                  }

                  setState(() {
                    _updateFuture = null;
                  });
                }
              },
              hoverColor: Colors.blueGrey,
              child: const Icon(
                Icons.update,
                color: Colors.white,
              ))
        ]));
  }

  Widget _reactiveDetailsBook(BuildContext context, bool isDesktop,
      ThemeProvider theme, Map<String, dynamic> bookDetails) {
    final allChapters = List<dynamic>.from(bookDetails['chapters'] ?? []);
    List<dynamic> chapters = List.from(allChapters);

    if (_isChapterReversed) {
      chapters = chapters.reversed.toList();
    }

    if (_selectedLanguagePrefix.isNotEmpty) {
      chapters = chapters
          .where((chapter) => chapter['translatedLanguage']
              .toString()
              .startsWith(_selectedLanguagePrefix))
          .toList();
    }

    String imageUrl = bookDetails['coverImageUrl'] ??
        'https://static.thenounproject.com/png/482114-200.png';
    final fontProvider = context.watch<FontProvider>();
    final effectiveScrapper =
        widget.scrapper ?? fontProvider.findScrapperForBook(bookDetails);
    final sourceDefinition = effectiveScrapper == null
        ? fontProvider.findSourceForBook(bookDetails)
        : fontProvider.findSourceForApi(effectiveScrapper);
    final usesScanCards = effectiveScrapper?.id == 'xcomic';
    final trackers = context.watch<TrackerController>();

    void showManageTabsDialog(BuildContext context) {
      final fontProvider = Provider.of<FontProvider>(context, listen: false);
      final tabsState = Provider.of<TabsState>(context, listen: false);

      final storedBook = fontProvider.favoritedBooks.firstWhere(
        (b) => b['id'] == bookDetails['id'],
        orElse: () => bookDetails,
      );
      final rawTabs = storedBook['tabs'];
      final initialTabs = rawTabs is List
          ? List<String>.from(rawTabs)
          : (storedBook['tab'] is String
              ? [storedBook['tab'] as String]
              : <String>['Reading']);
      final rawSubTabsByPrimary = storedBook['subTabsByPrimary'];
      final Map<String, List<String>> initialSubTabsByPrimary = {};
      if (rawSubTabsByPrimary is Map) {
        rawSubTabsByPrimary.forEach((key, value) {
          if (value is List) {
            initialSubTabsByPrimary[key.toString()] =
                value.map((e) => e.toString()).toList();
          }
        });
      } else {
        for (final tab in initialTabs) {
          final fallback = tabsState.getDefaultSubTabForPrimary(tab);
          initialSubTabsByPrimary[tab] =
              fallback.isEmpty ? <String>[] : <String>[fallback];
        }
      }

      showDialog(
        context: context,
        builder: (BuildContext context) {
          List<String> selectedTabs = List.from(initialTabs);
          final Map<String, List<String>> selectedSubTabsByPrimary =
              Map<String, List<String>>.from(initialSubTabsByPrimary);
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Text('Gerenciar Organização'),
                content: SingleChildScrollView(
                  child: ListBody(
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(bottom: 4),
                        child: Text('Tabs'),
                      ),
                      ...tabsState.libraryTabs.map((libraryTab) {
                        return CheckboxListTile(
                          title: Text(libraryTab),
                          value: selectedTabs.contains(libraryTab),
                          onChanged: (bool? checked) {
                            setDialogState(() {
                              if (checked == true) {
                                if (!selectedTabs.contains(libraryTab)) {
                                  selectedTabs.add(libraryTab);
                                  fontProvider.addBookToTab(
                                      libraryTab, bookDetails);
                                  selectedSubTabsByPrimary.putIfAbsent(
                                    libraryTab,
                                    () {
                                      final fallback =
                                          tabsState.getDefaultSubTabForPrimary(
                                              libraryTab);
                                      return fallback.isEmpty
                                          ? <String>[]
                                          : <String>[fallback];
                                    },
                                  );
                                }
                              } else if (selectedTabs.length > 1) {
                                selectedTabs.remove(libraryTab);
                                fontProvider.removeBookFromTab(
                                    libraryTab, bookDetails);
                              }
                            });
                          },
                        );
                      }),
                      const SizedBox(height: 8),
                      ...selectedTabs.expand((primaryTab) {
                        final subTabs =
                            tabsState.getSubTabsForPrimary(primaryTab);
                        final selectedSubTabs =
                            selectedSubTabsByPrimary[primaryTab] ?? <String>[];

                        return <Widget>[
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text('Subtabs de "$primaryTab"'),
                          ),
                          if (subTabs.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(left: 12, bottom: 8),
                              child:
                                  Text('Sem subtabs para esta tab primária.'),
                            ),
                          ...subTabs.map((subTab) {
                            return CheckboxListTile(
                              title: Text(subTab),
                              value: selectedSubTabs.contains(subTab),
                              onChanged: (bool? checked) {
                                setDialogState(() {
                                  final current =
                                      selectedSubTabsByPrimary[primaryTab] ??
                                          <String>[];
                                  if (checked == true) {
                                    if (!current.contains(subTab)) {
                                      current.add(subTab);
                                      fontProvider.addBookToSubTab(
                                        primaryTab,
                                        subTab,
                                        bookDetails,
                                      );
                                    }
                                  } else if (current.length > 1) {
                                    current.remove(subTab);
                                    fontProvider.removeBookFromSubTab(
                                      primaryTab,
                                      subTab,
                                      bookDetails,
                                    );
                                  }
                                  selectedSubTabsByPrimary[primaryTab] =
                                      current;
                                });
                              },
                            );
                          }),
                          const SizedBox(height: 8),
                        ];
                      }),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    child: const Text('Fechar'),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              );
            },
          );
        },
      );
    }

    return CustomScrollView(
      slivers: <Widget>[
        SliverAppBar(
          iconTheme: const IconThemeData(
              color: Colors.blueGrey,
              size: 30.0,
              shadows: <Shadow>[
                Shadow(color: Colors.black, blurRadius: 10.0),
              ]),
          expandedHeight: isDesktop ? 500.0 : 250.0,
          pinned: true,
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                ClipRRect(
                  child: _sourceCoverImage(
                    source: effectiveScrapper,
                    imageUrl: imageUrl,
                    fit: isDesktop ? BoxFit.cover : BoxFit.fill,
                    color: Colors.black.withValues(alpha: 0.5),
                    colorBlendMode: BlendMode.darken,
                  ),
                ),
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.center,
                        colors: [
                          Colors.black,
                          Colors.transparent,
                        ]),
                  ),
                ),
                Positioned(
                    top: 16.0,
                    left: 16.0,
                    child: Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: _sourceCoverImage(
                          source: effectiveScrapper,
                          imageUrl: imageUrl,
                          width: isDesktop ? 200 : 100,
                          height: isDesktop ? 300 : 200,
                          fit: BoxFit.cover,
                        ),
                      ),
                    )),
                Positioned(
                  top: 16.0,
                  left: isDesktop ? 240 : 130,
                  child: Text(
                    widget.bookDetails['type'] ?? 'No type available',
                    style: const TextStyle(
                        fontSize: 24.0,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        shadows: <Shadow>[
                          Shadow(color: Colors.black, blurRadius: 10.0),
                        ]),
                  ),
                ),
                if (!isDesktop)
                  Positioned(
                      bottom: 52.0,
                      left: 130.0,
                      right: 16.0,
                      child: _buildScrollableTags()),
                if (isDesktop)
                  Positioned(
                    top: 16.0,
                    right: 16.0,
                    child: SizedBox(
                      width: 300,
                      child: SingleChildScrollView(
                        child: Text(
                          bookDetails['description'] ??
                              'No description Available',
                          style: const TextStyle(
                              fontSize: 16.0, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 16.0,
                  left: 16.0,
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildPersonLabel(
                          bookDetails['author'],
                          'No author available',
                          fontSize: isDesktop ? 16.0 : 8.0,
                        ),
                        const SizedBox(width: 8.0),
                        _buildPersonLabel(
                          bookDetails['artist'],
                          'No artist available',
                          fontSize: isDesktop ? 16.0 : 8.0,
                        )
                      ]),
                ),
                if (effectiveScrapper != null)
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: SourceBadge(
                      name: sourceDefinition?.name ?? effectiveScrapper.name,
                      imageUri: Uri.tryParse(sourceDefinition?.image ?? '') ??
                          effectiveScrapper.baseUri.resolve('/favicon.ico'),
                      headers: effectiveScrapper.coverImageHeaders,
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            if (trackers.aniListConnectedAndEnabled)
              IconButton(
                tooltip: 'Add manga to AniList',
                onPressed: _syncingTrackers
                    ? null
                    : () => _addMangaToAniList(trackers),
                icon: _syncingTrackers
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_alt_rounded),
              ),
            Consumer<FontProvider>(
              builder: (context, favoritedBooksState, child) {
                final isFavorited =
                    favoritedBooksState.isFavorited(bookDetails);
                return IconButton(
                    icon: Icon(
                      isFavorited ? Icons.favorite : Icons.favorite_border,
                      color: Colors.red,
                    ),
                    onPressed: () {
                      favoritedBooksState.toggleFavorite(bookDetails);
                      setState(() {});
                    });
              },
            ),
            const SizedBox(width: 16.0),
            IconButton(
              icon: const Icon(Icons.open_in_browser),
              onPressed: () {
                setState(() {
                  _showWebView = !_showWebView;
                });
              },
            ),
            const SizedBox(width: 16.0),
            PopupMenuButton(
                onSelected: (String value) {
                  if (value == 'Manage Tabs') {
                    showManageTabsDialog(context);
                  }
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                      const PopupMenuItem<String>(
                        value: 'Rename Book',
                        child: Text('Rename book'),
                      ),
                      const PopupMenuItem<String>(
                        value: 'Migrate Book',
                        child: Text('Migrate book'),
                      ),
                      const PopupMenuItem<String>(
                        value: 'Manage Tabs',
                        child: Text('Gerenciar tabs'),
                      ),
                    ]),
          ],
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: isDesktop
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              children: [
                Text(
                  bookDetails['title'] ?? 'No title available',
                  style: TextStyle(
                      fontSize: 24.0,
                      fontWeight: FontWeight.bold,
                      color: theme.selectedTheme.textTheme.titleMedium?.color,
                      shadows: const <Shadow>[
                        Shadow(
                            color: Color.fromARGB(255, 87, 25, 25),
                            blurRadius: 2.0),
                        Shadow(
                            color: Color.fromARGB(255, 0, 0, 0),
                            blurRadius: 2.0),
                      ]),
                ),
                if (bookDetails['altTitles'] != null &&
                    bookDetails['altTitles'].isNotEmpty)
                  Card(
                    margin: EdgeInsets.only(top: 16.0),
                    surfaceTintColor: Colors.blueGrey,
                    color: theme.selectedTheme.cardTheme.color,
                    shadowColor: theme.selectedTheme.cardTheme.shadowColor,
                    elevation: theme.selectedTheme.cardTheme.elevation,
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children:
                            bookDetails['altTitles'].map<Widget>((altTitle) {
                          return Text(altTitle.values.first,
                              style: TextStyle(
                                  fontSize: 16.0,
                                  color: theme.selectedTheme.textTheme
                                      .displayMedium?.color));
                        }).toList(),
                      ),
                    ),
                  ),
                const SizedBox(height: 16.0),
                if (!isDesktop)
                  Text(
                    bookDetails['description'] ?? 'No description Available',
                    style: TextStyle(
                        fontSize: 16.0,
                        color:
                            theme.selectedTheme.textTheme.displayMedium?.color),
                  ),
                _buildContinueCard(allChapters, fontProvider),
                _buildReminderSection(),
                if (isDesktop) _buildScrollableTags(),
                Text(
                  'Chapters',
                  style: TextStyle(
                      fontSize: 20.0,
                      fontWeight: FontWeight.bold,
                      color:
                          theme.selectedTheme.textTheme.displayMedium?.color),
                ),
                const SizedBox(height: 8.0),
                SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _buildLanguageFilterButtons(),
                    ))
              ],
            ),
          ),
        ),
        if (usesScanCards)
          SliverToBoxAdapter(
            child: _buildXComicScanCarousel(chapters, allChapters, theme),
          )
        else
          SliverList(
              delegate: SliverChildBuilderDelegate(
            (BuildContext context, int index) {
              if (index >= chapters.length) {
                return const SizedBox.shrink();
              }

              final chapter = chapters[index];
              final readChapterIds =
                  (fontProvider.selectedChapterIds[bookDetails['id']] ?? [])
                      .map((c) => c['id'] as String)
                      .toSet();
              final isRead =
                  readChapterIds.contains(chapter['id'] as String? ?? '');

              return ListTile(
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          _buildChapterLabel(chapter),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: TextStyle(
                              color: theme
                                  .selectedTheme.textTheme.titleSmall?.color,
                              fontSize: 16.0,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (chapter['volume'] != null)
                        Text(
                          'Vol. ${_formatVolume(chapter['volume']?.toString())}',
                          style: TextStyle(
                            color:
                                theme.selectedTheme.textTheme.titleSmall?.color,
                            fontSize: 16.0,
                          ),
                        ),
                      SizedBox(width: 8.0),
                      Text(
                        '${chapter['translatedLanguage'] ?? ''}',
                        style: TextStyle(
                          color:
                              theme.selectedTheme.textTheme.titleSmall?.color,
                          fontSize: 16.0,
                        ),
                      )
                    ],
                  ),
                  leading: Icon(
                    isRead ? Icons.check_circle : Icons.circle_outlined,
                    color: isRead ? Colors.green : Colors.grey,
                    size: 20,
                  ),
                  tileColor: _selectedChapterId == chapter['id']
                      ? const Color(0xFF483D8B).withAlpha(150)
                      : isRead
                          ? Colors.green.withValues(alpha: 0.08)
                          : null,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  subtitle: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (chapter['pages'] != null)
                        Text(
                          '${chapter['pages']} pages',
                          style: TextStyle(
                            color: theme
                                .selectedTheme.textTheme.displayMedium?.color,
                            fontSize: 14.0,
                          ),
                        ),
                      if (chapter['uploader'] != null)
                        Text(
                          chapter['uploader'],
                          style: TextStyle(
                            color: theme
                                .selectedTheme.textTheme.displayMedium?.color,
                            fontSize: 14.0,
                          ),
                        ),
                      Text(
                        _formatDate(chapter['publishedAt']?.toString()),
                        style: TextStyle(
                          color: theme
                              .selectedTheme.textTheme.displayMedium?.color,
                          fontSize: 14.0,
                        ),
                      )
                    ],
                  ),
                  onTap: () => _openChapter(chapter),
                  onLongPress: () =>
                      _showChapterProgressActions(chapter, allChapters));
            },
            childCount: chapters.length,
          ))
      ],
    );
  }

  Widget _buildXComicScanCarousel(
    List<dynamic> chapters,
    List<dynamic> allChapters,
    ThemeProvider theme,
  ) {
    final grouped = <String, List<Map<dynamic, dynamic>>>{};
    for (final rawChapter in chapters) {
      if (rawChapter is! Map) continue;
      final chapter = Map<dynamic, dynamic>.from(rawChapter);
      final scanId = _xComicScanId(chapter);
      grouped.putIfAbsent(scanId, () => []).add(chapter);
    }
    if (grouped.isEmpty) return const SizedBox.shrink();

    final screenWidth = MediaQuery.sizeOf(context).width;
    final cardWidth = (screenWidth * .86).clamp(300.0, 390.0);
    return SizedBox(
      height: 520,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 0, 24, 18),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: grouped.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final entry = grouped.entries.elementAt(index);
          final scanChapters = entry.value;
          final first = scanChapters.first;
          final scanName = _xComicScanName(first);
          final language = first['translatedLanguage']?.toString().trim() ?? '';
          final missing = first['missingChapters']?.toString().trim() ?? '';
          return SizedBox(
            width: cardWidth,
            child: Card(
              clipBehavior: Clip.antiAlias,
              color: theme.selectedTheme.cardTheme.color,
              elevation: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            scanName.isEmpty
                                ? '#${entry.key}'
                                : '#${entry.key} · $scanName',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (language.isNotEmpty)
                          Chip(
                            label: Text(language),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                          ),
                      ],
                    ),
                  ),
                  if (missing.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .tertiaryContainer
                            .withValues(alpha: .45),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, size: 16),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              missing,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      primary: false,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: scanChapters.length,
                      itemBuilder: (context, chapterIndex) {
                        final chapter = scanChapters[chapterIndex];
                        final chapterId = chapter['id']?.toString() ?? '';
                        final title = chapter['title']?.toString().trim() ?? '';
                        final number =
                            chapter['chapter']?.toString().trim() ?? '';
                        final isRead = _isChapterRead(chapterId);
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            isRead ? Icons.check_circle : Icons.circle_outlined,
                            color: isRead ? Colors.green : Colors.grey,
                            size: 20,
                          ),
                          title: Text(
                            title.isNotEmpty
                                ? title
                                : number.isNotEmpty
                                    ? 'Chapter $number'
                                    : 'Chapter ?',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            _formatChapterDate(
                              chapter['publishedAt']?.toString(),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          selected: _selectedChapterId == chapterId,
                          selectedTileColor:
                              const Color(0xFF483D8B).withAlpha(90),
                          onTap: () => _openChapter(chapter),
                          onLongPress: () => _showChapterProgressActions(
                            chapter,
                            allChapters,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _xComicScanId(Map<dynamic, dynamic> chapter) {
    final explicit = chapter['scanId']?.toString().trim() ?? '';
    if (explicit.isNotEmpty) return explicit;

    // Compatibility with xComic details cached before scan metadata became a
    // first-class part of MangaChapter. Those builds appended the scan id to
    // the chapter title/uploader.
    for (final value in [chapter['uploader'], chapter['title']]) {
      final match = RegExp(r'#([a-zA-Z0-9_-]+)').firstMatch('$value');
      if (match != null) return match.group(1)!;
    }
    return 'unknown';
  }

  String _xComicScanName(Map<dynamic, dynamic> chapter) {
    final explicit = chapter['scanName']?.toString().trim() ?? '';
    if (explicit.isNotEmpty) return explicit;
    final uploader = chapter['uploader']?.toString().trim() ?? '';
    if (uploader.isEmpty || uploader.startsWith('missing')) return '';
    return uploader.replaceFirst(RegExp(r'\s*#[a-zA-Z0-9_-]+\s*$'), '').trim();
  }

  String _formatChapterDate(String? rawDate) {
    final value = rawDate?.trim() ?? '';
    if (value.isEmpty) return 'No date';
    if (RegExp(
      r'^(?:today|yesterday|\d+\s*(?:s|m|h|d|w|mo|y)(?:inute|our|ay|eek|onth|ear)?s?\s+ago)$',
      caseSensitive: false,
    ).hasMatch(value)) {
      return value;
    }
    return _formatDate(value);
  }

  bool _isChapterRead(String chapterId) {
    final fontProvider = Provider.of<FontProvider>(context, listen: false);
    return (fontProvider.selectedChapterIds[bookDetails['id']] ?? [])
        .any((chapter) => chapter['id']?.toString() == chapterId);
  }

  Future<void> _showChapterProgressActions(
    Map<dynamic, dynamic> chapter,
    List<dynamic> allChapters,
  ) async {
    final chapterId = chapter['id']?.toString() ?? '';
    if (chapterId.isEmpty) return;
    final through = _chaptersThrough(chapter, allChapters);
    final isRead = _isChapterRead(chapterId);
    final readThrough = through
        .where((candidate) => _isChapterRead(candidate['id']?.toString() ?? ''))
        .length;
    final label = _buildChapterLabel(chapter);

    final action = await showModalBottomSheet<_ChapterProgressAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(label),
              subtitle: const Text('Reading progress'),
            ),
            ListTile(
              enabled: !isRead,
              leading: const Icon(Icons.check_circle_outline_rounded),
              title: const Text('Mark chapter as read'),
              onTap: () => Navigator.pop(
                sheetContext,
                _ChapterProgressAction.markOne,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.done_all_rounded),
              title: const Text('Mark this and previous chapters as read'),
              subtitle: Text('${through.length} chapters in this sequence'),
              onTap: () => Navigator.pop(
                sheetContext,
                _ChapterProgressAction.markThrough,
              ),
            ),
            ListTile(
              enabled: isRead,
              leading: const Icon(Icons.remove_circle_outline_rounded),
              title: const Text('Mark chapter as unread'),
              onTap: () => Navigator.pop(
                sheetContext,
                _ChapterProgressAction.unmarkOne,
              ),
            ),
            ListTile(
              enabled: readThrough > 0,
              leading: const Icon(Icons.playlist_remove_rounded),
              title: const Text('Remove read marks through this chapter'),
              subtitle: Text('$readThrough marked chapters will be affected'),
              onTap: () => Navigator.pop(
                sheetContext,
                _ChapterProgressAction.unmarkThrough,
              ),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    final provider = context.read<FontProvider>();
    final bookId = bookDetails['id']?.toString() ?? '';
    if (bookId.isEmpty) return;
    final selectedRecord = _chapterProgressRecord(chapter);
    late final int changed;
    switch (action) {
      case _ChapterProgressAction.markOne:
        changed = await provider.markChaptersRead(
          bookId,
          [selectedRecord],
          continueFrom: selectedRecord,
        );
        break;
      case _ChapterProgressAction.markThrough:
        changed = await provider.markChaptersRead(
          bookId,
          through.map(_chapterProgressRecord).toList(),
          continueFrom: selectedRecord,
        );
        break;
      case _ChapterProgressAction.unmarkOne:
        changed = await provider.markChaptersUnread(bookId, [chapterId]);
        break;
      case _ChapterProgressAction.unmarkThrough:
        changed = await provider.markChaptersUnread(
          bookId,
          through.map((item) => item['id']?.toString() ?? ''),
        );
        break;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          changed == 0
              ? 'Reading progress was already up to date.'
              : '$changed chapter${changed == 1 ? '' : 's'} updated.',
        ),
      ),
    );
  }

  List<Map<dynamic, dynamic>> _chaptersThrough(
    Map<dynamic, dynamic> selected,
    List<dynamic> allChapters,
  ) {
    final selectedNumber = _chapterNumber(selected);
    final language = selected['translatedLanguage']?.toString() ?? '';
    final explicitScanId = selected['scanId']?.toString() ?? '';
    final hasLegacyScanId = [selected['uploader'], selected['title']]
        .any((value) => RegExp(r'#[a-zA-Z0-9_-]+').hasMatch('$value'));
    final scanId = explicitScanId.isNotEmpty
        ? explicitScanId
        : hasLegacyScanId
            ? _xComicScanId(selected)
            : '';
    final candidates = allChapters
        .whereType<Map>()
        .map((chapter) => Map<dynamic, dynamic>.from(chapter))
        .where((chapter) {
      if (language.isNotEmpty &&
          chapter['translatedLanguage']?.toString() != language) {
        return false;
      }
      if (scanId.isNotEmpty && _xComicScanId(chapter) != scanId) {
        return false;
      }
      final number = _chapterNumber(chapter);
      return selectedNumber == null || number == null
          ? chapter['id']?.toString() == selected['id']?.toString()
          : number <= selectedNumber;
    }).toList();
    candidates.sort((left, right) {
      final leftNumber = _chapterNumber(left) ?? double.infinity;
      final rightNumber = _chapterNumber(right) ?? double.infinity;
      return leftNumber.compareTo(rightNumber);
    });
    return candidates.isEmpty ? [selected] : candidates;
  }

  Map<String, String> _chapterProgressRecord(Map<dynamic, dynamic> chapter) {
    final id = chapter['id']?.toString() ?? '';
    final number = chapter['chapter']?.toString().trim() ?? '';
    final title = chapter['title']?.toString().trim() ?? '';
    return {'id': id, 'title': number.isNotEmpty ? number : title};
  }

  double? _chapterNumber(Map<dynamic, dynamic> chapter) {
    final value = (chapter['chapter'] ?? chapter['title'])?.toString() ?? '';
    final match = RegExp(r'\d+(?:[.,]\d+)?').firstMatch(value);
    return match == null
        ? null
        : double.tryParse(match.group(0)!.replaceAll(',', '.'));
  }

  Future<void> _openChapter(Map<dynamic, dynamic> chapter) async {
    final chapterId = (chapter['id'] ?? '').toString();
    final chapterNumber = (chapter['chapter'] ?? '').toString();
    setState(() {
      _isLoadingChapter = true;
      _selectedChapterId = chapterId;
    });

    final fontProvider = Provider.of<FontProvider>(context, listen: false);
    await fontProvider.saveSingleSelectedChapterId(
      bookDetails['id'],
      chapterId,
      chapterNumber,
    );
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Row(children: [
        Text('Loading chapter...'),
        SizedBox(width: 10),
        CircularProgressIndicator(),
      ]),
      duration: const Duration(minutes: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
    ));

    try {
      final fontApi = widget.scrapper ??
          fontProvider.findScrapperForBook(bookDetails) ??
          fontProvider.selectedFontApi;
      final webViewUrl = fontApi is WebViewChapterMangaSource
          ? (fontApi as WebViewChapterMangaSource)
              .chapterWebUri(
                mangaId: bookDetails['id'].toString(),
                chapterId: chapterId,
              )
              .toString()
          : '';
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ChapterBookScreen(
            bookTitle: bookDetails['title'],
            chapterId: chapterId,
            chapterTitle: chapter['title'],
            mangaID: bookDetails['id'].toString(),
            chapterNumber: chapterNumber,
            chapterWebViewUrl: webViewUrl,
            scrapper: fontApi,
            onChapterCompleted: _mangaProgressCallback(),
          ),
        ),
      );
      if (mounted) _refreshReminders();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to load chapter: $error'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      if (kDebugMode) print('Failed to load chapter: $error');
    } finally {
      if (mounted) setState(() => _isLoadingChapter = false);
    }
  }

  Future<void> _addMangaToAniList(TrackerController trackers) async {
    setState(() => _syncingTrackers = true);
    try {
      final names = await trackers.addMangaToConnectedTrackers(
        title: bookDetails['title']?.toString() ?? '',
        aniListId: _externalTrackerId('anilist'),
        malId: _externalTrackerId('mal'),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added to ${names.join(' and ')}.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    } finally {
      if (mounted) setState(() => _syncingTrackers = false);
    }
  }

  Future<void> Function(int chapter)? _mangaProgressCallback() {
    final trackers = context.read<TrackerController>();
    if (!trackers.aniListConnectedAndEnabled) return null;
    final title = bookDetails['title']?.toString() ?? '';
    final aniListId = _externalTrackerId('anilist');
    final malId = _externalTrackerId('mal');
    return (chapter) async {
      await trackers.updateMangaProgressOnConnectedTrackers(
        title: title,
        chapter: chapter,
        aniListId: aniListId,
        malId: malId,
      );
    };
  }

  int? _externalTrackerId(String tracker) {
    final externalIds = bookDetails['externalIds'];
    final candidates = <dynamic>[
      if (externalIds is Map) externalIds[tracker],
      if (externalIds is Map) externalIds['${tracker}Id'],
      bookDetails[tracker],
      bookDetails['${tracker}Id'],
    ];
    for (final value in candidates) {
      final parsed = int.tryParse(value?.toString() ?? '');
      if (parsed != null) return parsed;
    }
    return null;
  }

  List<Widget> _buildLanguageFilterButtons() {
    List<String> languagePrefixes = ((bookDetails['chapters'] as List?) ?? [])
        .map<String>((chapter) => chapter['translatedLanguage'].toString())
        .toSet()
        .toList();

    return languagePrefixes.map((prefix) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: ElevatedButton(
          onPressed: () {
            _filterChaptersByLanguage(prefix);
          },
          child: Text(prefix),
        ),
      );
    }).toList();
  }

  Widget _buildWebView(BuildContext context) {
    final String url = bookDetails['mangaUrl'] ?? 'https://www.google.com';
    Widget webViewContent;

    if (kIsWeb) {
      return Center(
        child: Text('Web view not supported on this platform.'),
      );
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      final controller = flutter_webview.WebViewController();
      controller.setJavaScriptMode(flutter_webview.JavaScriptMode.unrestricted);
      controller.setBackgroundColor(const Color(0x00000000));
      controller.setNavigationDelegate(flutter_webview.NavigationDelegate(
        onProgress: (int progress) {
          // Update loading bar
        },
        onPageStarted: (String url) {},
        onPageFinished: (String url) {},
        onWebResourceError: (flutter_webview.WebResourceError error) {},
        onNavigationRequest: (flutter_webview.NavigationRequest request) {
          return flutter_webview.NavigationDecision.navigate;
        },
      ));
      controller.loadRequest(Uri.parse(url));

      webViewContent = flutter_webview.WebViewWidget(
        controller: controller,
      );
    } else if (defaultTargetPlatform == TargetPlatform.windows) {
      webViewContent = FutureBuilder<webview_windows.WebviewController>(
          future: _initializeWebviewController(),
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              final controller = snapshot.data!;
              controller.loadUrl(url);

              return webview_windows.Webview(controller);
            } else if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            } else {
              return const Center(child: CircularProgressIndicator());
            }
          });
    } else {
      webViewContent = Center(
        child: Text('Platform not supported.'),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(bookDetails['title']),
        backgroundColor: Color.fromARGB(29, 60, 16, 180),
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(20),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            setState(() {
              _showWebView = false;
            });
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new),
            onPressed: () {
              launchUrl(Uri.parse(url));
            },
          ),
        ],
      ),
      body: webViewContent,
    );
  }
}

Future<webview_windows.WebviewController> _initializeWebviewController() async {
  final controller = webview_windows.WebviewController();
  await controller.initialize();
  return controller;
}

/// Constrói o label do capítulo tratando os diferentes formatos de scrapper:
///   MangaDex : title pode ser vazio,  chapter = '1'   → 'Chapter 1'
///   LuraToons: title é vazio,         chapter = '1.0' → 'Chapter 1.0'
///   MediocreScan: title = 'Capítulo 1', chapter = null → 'Capítulo 1'
String _buildChapterLabel(Map chapter) {
  final title = chapter['title']?.toString().trim() ?? '';
  final num = chapter['chapter']?.toString().trim() ?? '';
  if (title.isNotEmpty && num.isNotEmpty) return '$title - Chapter $num';
  if (title.isNotEmpty) return title;
  if (num.isNotEmpty) return 'Chapter $num';
  return 'Chapter ?';
}

/// Extrai o nome de um campo de pessoa que pode vir em formatos distintos:
///   - String direta: 'Brandon Chen'         → retorna a própria string
///   - Map com 'name': {'name': 'X', ...}    → retorna map['name']
///   - null                                  → retorna null
String? _extractPersonName(dynamic value) {
  if (value == null) return null;
  if (value is String) return value.isEmpty ? null : value;
  if (value is Map) return value['name']?.toString();
  return value.toString();
}

String _formatDate(String? date) {
  if (date == null) {
    return 'No date';
  }

  try {
    final DateTime parsedDate = DateTime.parse(date);
    return DateFormat('dd MMM yyyy').format(parsedDate);
  } catch (e) {
    return 'Invalid date';
  }
}

String _formatVolume(String? volume) {
  if (volume == null) {
    return 'No volume';
  }

  try {
    final int parsedVolume = int.parse(volume);
    return parsedVolume.toString();
  } catch (e) {
    return 'Invalid volume';
  }
}
