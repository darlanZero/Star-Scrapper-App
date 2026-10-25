import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/classes/static/fonts_provider.dart';
import 'package:star_scrapper_app/components/Shared/scrapper_font.dart';
import 'package:star_scrapper_app/domain/sources/source.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';
import 'package:star_scrapper_app/pages/anime_source_catalog_screen.dart';
import 'package:star_scrapper_app/pages/pages.dart';

class ScrapperActiveFonts extends StatefulWidget {
  const ScrapperActiveFonts({super.key});

  @override
  State<ScrapperActiveFonts> createState() => _ScrapperActiveFontsState();
}

class _ScrapperActiveFontsState extends State<ScrapperActiveFonts> {
  List<Fonte> pinnedFonts = [];
  SourceContentType _contentType = SourceContentType.manga;

  @override
  void initState() {
    super.initState();
    loadActiveFonts();
  }

  Future<void> loadActiveFonts() async {
    final fontProvider = Provider.of<FontProvider>(context, listen: false);
    final prefs = await SharedPreferences.getInstance();
    await fontProvider.sourcesLoaded;

    final restoredPinnedFonts = <Fonte>[];
    for (final font in fontProvider.activeFonts) {
      final stableKey = 'source_${font.id}_pinned';
      final stableValue = prefs.getBool(stableKey);
      final legacyValue = prefs.getBool('${font.name}_pinned');
      final isPinned = stableValue ?? legacyValue ?? false;
      if (stableValue == null && legacyValue != null) {
        await prefs.setBool(stableKey, legacyValue);
      }
      if (isPinned) restoredPinnedFonts.add(font);
    }
    restoredPinnedFonts.sort((a, b) => a.name.compareTo(b.name));

    if (!mounted) return;

    setState(() {
      pinnedFonts = restoredPinnedFonts;
    });
  }

  Future<void> togglePinned(Fonte font) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'source_${font.id}_pinned';
    final isPinned =
        !(prefs.getBool(key) ?? prefs.getBool('${font.name}_pinned') ?? false);
    await prefs.setBool(key, isPinned);

    setState(() {
      if (isPinned) {
        pinnedFonts.add(font);
        pinnedFonts.sort((a, b) => a.name.compareTo(b.name));
      } else {
        pinnedFonts.removeWhere((f) => f.name == font.name);
      }
    });
  }

  Widget _buildOutdatedDummy(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.grey.shade800,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(
        Icons.public_off_rounded,
        size: size * 0.75,
        color: Colors.white70,
      ),
    );
  }

  Widget _buildSafeFontIcon(Fonte font, {double size = 25}) {
    final status = Provider.of<FontProvider>(context, listen: false)
        .getFontHostStatus(font.name);
    if (status == FontHostStatus.outdated) return _buildOutdatedDummy(size);

    return Image.network(
      font.image,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => _buildOutdatedDummy(size),
    );
  }

  Widget _buildStatusBadge(Fonte font) {
    final status = Provider.of<FontProvider>(context, listen: false)
        .getFontHostStatus(font.name);
    String label;
    Color color;
    switch (status) {
      case FontHostStatus.online:
        label = 'ONLINE';
        color = Colors.green;
        break;
      case FontHostStatus.outdated:
        label = 'OUTDATED';
        color = Colors.redAccent;
        break;
      case FontHostStatus.checking:
        label = 'CHECKING';
        color = Colors.orangeAccent;
        break;
      case FontHostStatus.unknown:
        label = 'UNKNOWN';
        color = Colors.grey;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          color: color,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildFontTile(Fonte font) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isMobile = MediaQuery.of(context).size.width < 600;
    final fontSize = isMobile ? 12.0 : 16.0;

    final popularButton = OutlinedButton.icon(
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FontBooksGalleryScreen(
              initialView: 'popular',
              selectedFont: font,
            ),
          ),
        );
      },
      icon: const Icon(Icons.trending_up_rounded, size: 18),
      label: Text(
        'Popular',
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: fontSize),
      ),
    );

    final recentButton = OutlinedButton.icon(
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FontBooksGalleryScreen(
              initialView: 'recent',
              selectedFont: font,
            ),
          ),
        );
      },
      icon: const Icon(Icons.schedule_rounded, size: 18),
      label: Text(
        'Recent',
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: fontSize),
      ),
    );

    final pinButton = IconButton(
      icon: Icon(
        pinnedFonts.contains(font) ? Icons.push_pin : Icons.push_pin_outlined,
        color: pinnedFonts.contains(font)
            ? colors.primary
            : colors.onSurfaceVariant,
      ),
      tooltip: pinnedFonts.contains(font) ? 'Unpin source' : 'Pin source',
      onPressed: () => togglePinned(font),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: isMobile
            ? Column(
                children: [
                  Row(
                    children: [
                      _buildSafeFontIcon(font, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                font.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: colors.onSurface,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            _buildStatusBadge(font),
                          ],
                        ),
                      ),
                      pinButton,
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.start,
                    children: [popularButton, recentButton],
                  ),
                ],
              )
            : Row(
                children: [
                  _buildSafeFontIcon(font, size: 25),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            font.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: fontSize,
                              color: colors.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildStatusBadge(font),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  popularButton,
                  const SizedBox(width: 8),
                  recentButton,
                  const SizedBox(width: 8),
                  pinButton,
                ],
              ),
      ),
    );
  }

  Widget _buildAnimeSourceTile(AnimeSource source) {
    final colors = Theme.of(context).colorScheme;
    void open(AnimeCatalogFilter filter) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AnimeSourceCatalogScreen(
            source: source,
            initialFilter: filter,
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
                        source.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '${source.languageLabel} · ${source.audioLabel}',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'ACTIVE',
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => open(AnimeCatalogFilter.recent),
                    icon: const Icon(Icons.schedule_rounded),
                    label: const Text('Latest'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => open(AnimeCatalogFilter.popular),
                    icon: const Icon(Icons.trending_up_rounded),
                    label: const Text('Trending'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<FontProvider>(
      builder: (context, fontProvider, child) {
        final activeAnimeSources = fontProvider.activeAnimeSources;
        final animeLanguageGroups =
            activeAnimeSources.groupedByLanguage.entries.toList();
        final activeFonts = fontProvider.activeFonts
            .where((source) => source.contentType == _contentType)
            .toList();
        final activePinnedFonts =
            pinnedFonts.where((font) => activeFonts.contains(font)).toList();
        final grouped = <String, List<Fonte>>{};
        for (final font in activeFonts) {
          grouped.putIfAbsent(font.languagePrefix, () => []).add(font);
        }
        final languageGroups = grouped.entries
            .map(
              (entry) => LanguageGroup(
                languagePrefix: entry.key,
                fonts: entry.value,
              ),
            )
            .toList();

        final colors = Theme.of(context).colorScheme;

        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
          children: [
            SegmentedButton<SourceContentType>(
              segments: const [
                ButtonSegment(
                  value: SourceContentType.manga,
                  icon: Icon(Icons.menu_book_rounded),
                  label: Text('Manga'),
                ),
                ButtonSegment(
                  value: SourceContentType.anime,
                  icon: Icon(Icons.play_circle_rounded),
                  label: Text('Anime'),
                ),
              ],
              selected: {_contentType},
              onSelectionChanged: (selection) {
                setState(() => _contentType = selection.first);
              },
            ),
            const SizedBox(height: 12),
            if (_contentType == SourceContentType.anime &&
                activeAnimeSources.isNotEmpty)
              ...animeLanguageGroups.indexed.map((entry) {
                final index = entry.$1;
                final group = entry.$2;
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ExpansionTile(
                    initiallyExpanded: index == 0,
                    leading:
                        Icon(Icons.language_rounded, color: colors.primary),
                    title: Text(
                      group.key,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${group.value.length} ${group.value.length == 1 ? 'source' : 'sources'}',
                    ),
                    children: group.value.map(_buildAnimeSourceTile).toList(),
                  ),
                );
              }),
            if ((_contentType == SourceContentType.anime
                ? activeAnimeSources.isEmpty
                : activeFonts.isEmpty))
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 36,
                  ),
                  child: Column(
                    children: [
                      Icon(
                        _contentType == SourceContentType.anime
                            ? Icons.ondemand_video_outlined
                            : Icons.source_outlined,
                        size: 46,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _contentType == SourceContentType.anime
                            ? 'No active anime sources.'
                            : 'No active manga sources.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _contentType == SourceContentType.anime
                            ? 'Enable AniTube in the Manage tab.'
                            : 'Enable a source in the Manage tab.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            if (_contentType == SourceContentType.manga &&
                activePinnedFonts.isNotEmpty) ...[
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ExpansionTile(
                  leading: Icon(Icons.push_pin_rounded, color: colors.primary),
                  title: const Text(
                    'Pinned sources',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text('${activePinnedFonts.length} saved'),
                  children: activePinnedFonts.map(_buildFontTile).toList(),
                ),
              ),
            ],
            if (_contentType == SourceContentType.manga)
              ...languageGroups.indexed.map((entry) {
                final index = entry.$1;
                final group = entry.$2;
                final visibleFonts = group.fonts
                    .where((font) => !activePinnedFonts.contains(font))
                    .toList();
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ExpansionTile(
                    initiallyExpanded: index == 0,
                    leading:
                        Icon(Icons.language_rounded, color: colors.primary),
                    title: Text(
                      group.languagePrefix,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${visibleFonts.length} ${visibleFonts.length == 1 ? 'source' : 'sources'}',
                    ),
                    children: visibleFonts.map(_buildFontTile).toList(),
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}
