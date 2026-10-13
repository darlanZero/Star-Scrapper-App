import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/classes/static/fonts_provider.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';
import 'package:star_scrapper_app/domain/sources/source.dart';

export 'package:star_scrapper_app/domain/sources/source.dart';

class ScrapperDownloaderFonts extends StatefulWidget {
  const ScrapperDownloaderFonts({super.key});

  @override
  State<ScrapperDownloaderFonts> createState() =>
      _ScrapperDownloaderFontsState();
}

class _ScrapperDownloaderFontsState extends State<ScrapperDownloaderFonts> {
  List<LanguageGroup> languageGroups = [];
  SourceContentType _contentType = SourceContentType.manga;

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

  List<LanguageGroup> _groupFonts(List<Fonte> fonts) {
    final grouped = <String, List<Fonte>>{};
    for (final font in fonts) {
      grouped.putIfAbsent(font.languagePrefix, () => []).add(font);
    }
    return grouped.entries
        .map(
          (entry) => LanguageGroup(
            languagePrefix: entry.key,
            fonts: entry.value,
          ),
        )
        .toList();
  }

  Future<void> toggleFontState(Fonte font) async {
    await Provider.of<FontProvider>(context, listen: false)
        .toggleFontState(font);
  }

  Widget _buildAnimeSourceTile(
    AnimeSource source,
    FontProvider provider,
  ) {
    final active = provider.isAnimeSourceActive(source);
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: SwitchListTile(
        value: active,
        onChanged: (_) => provider.toggleAnimeSource(source),
        secondary: CircleAvatar(
          backgroundColor: colors.primaryContainer,
          foregroundColor: colors.onPrimaryContainer,
          child: const Icon(Icons.play_arrow_rounded),
        ),
        title: Text(
          source.name,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          source.id == 'smart_animes'
              ? 'Português (Brasil) · Google Drive'
              : 'All languages · Sub/Dub · HLS · Subtitles',
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<FontProvider>(builder: (context, fontProvider, __) {
      final visibleSources = _contentType == SourceContentType.manga
          ? fontProvider.fonts
              .where((source) => source.contentType == _contentType)
              .toList()
          : <Fonte>[];
      languageGroups = _groupFonts(visibleSources);
      return Card(
        color: Color(0xFF262335),
        margin: EdgeInsets.all(8.0),
        elevation: 4.0,
        borderOnForeground: true,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
        child: ListView(
          padding: EdgeInsets.all(16.0),
          scrollDirection: Axis.vertical,
          physics: BouncingScrollPhysics(),
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
            if (_contentType == SourceContentType.anime) ...[
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Anime sources',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Enable providers to browse and play episodes.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              ...fontProvider.animeSources.map(
                (source) => _buildAnimeSourceTile(source, fontProvider),
              ),
            ] else if (visibleSources.isEmpty) ...[
              const SizedBox(height: 28),
              const Icon(Icons.ondemand_video_outlined, size: 48),
              const SizedBox(height: 12),
              const Text(
                'Anime sources will be added in a future update.',
                textAlign: TextAlign.center,
              ),
            ],
            SizedBox(height: 10),
            if (_contentType == SourceContentType.manga &&
                visibleSources.isNotEmpty)
              _buildFontSection('Active Sources', true),
            SizedBox(height: 10),
            if (_contentType == SourceContentType.manga &&
                visibleSources.isNotEmpty)
              _buildFontSection('Inactive Sources', false),
          ],
        ),
      );
    });
  }

  Widget _buildFontSection(String title, bool isActive) {
    return Column(
      children: [
        Center(
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.normal,
              decoration: TextDecoration.underline,
              fontSize: MediaQuery.of(context).size.width >= 600 ? 20 : 16,
              decorationColor: isActive ? Colors.green : Colors.red,
            ),
          ),
        ),
        ...languageGroups.map((group) => ExpansionTile(
              initiallyExpanded: group.languagePrefix == 'All',
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              title: Text(
                group.languagePrefix,
                style: TextStyle(
                  color: isActive ? Colors.lightGreenAccent : Colors.red,
                  fontWeight: FontWeight.normal,
                  fontSize: MediaQuery.of(context).size.width >= 600 ? 20 : 16,
                ),
              ),
              children: group.fonts
                  .where((font) => font.isActive == isActive)
                  .map((font) => _buildFontTile(font, isActive))
                  .toList(),
            )),
      ],
    );
  }

  Widget _buildFontTile(Fonte font, bool isActive) {
    return ListTile(
      leading: _buildSafeFontIcon(font, size: 25),
      title: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                font.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isActive ? Colors.green : Colors.red,
                  decoration: isActive ? null : TextDecoration.lineThrough,
                  shadows: const <Shadow>[
                    Shadow(
                      offset: Offset(1.0, 1.0),
                      blurRadius: 3.0,
                      color: Color.fromARGB(255, 0, 0, 0),
                    ),
                  ],
                  fontSize: MediaQuery.of(context).size.width >= 600 ? 20 : 16,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _buildStatusBadge(font),
          ],
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            font.isRRated
                ? Icons.remove_red_eye
                : Icons.remove_red_eye_outlined,
            color: font.isRRated ? Colors.red : Colors.green,
          ),
          IconButton(
            icon: Icon(
              isActive ? Icons.toggle_on : Icons.toggle_off,
              color: isActive ? Colors.green : Colors.red,
            ),
            onPressed: () => toggleFontState(font),
          ),
        ],
      ),
    );
  }
}
