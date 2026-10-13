import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/application/sources/source_controller.dart';
import 'package:star_scrapper_app/data/sources/source_catalog.dart';

void main() {
  test('loads stable active IDs and persists toggles', () async {
    final sources = SourceCatalog.createAll();
    SharedPreferences.setMockInitialValues({
      'activeSourceIds': [sources.first.id],
    });
    var changes = 0;
    final controller = SourceController(
      sources: sources,
      onChanged: () => changes++,
    );

    await controller.initialize();
    await controller.toggle(sources[1]);

    expect(controller.active.map((source) => source.id), [
      sources.first.id,
      sources[1].id,
    ]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('activeSourceIds'), [
      sources.first.id,
      sources[1].id,
    ]);
    expect(changes, 2);
  });

  test('migrates legacy source names to stable IDs', () async {
    final sources = SourceCatalog.createAll();
    SharedPreferences.setMockInitialValues({
      'activeFonts': [sources[2].name],
    });
    final controller = SourceController(
      sources: sources,
      onChanged: () {},
    );

    await controller.initialize();

    expect(controller.active.single.id, sources[2].id);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('activeSourceIds'), [sources[2].id]);
  });

  test('resolves a scraper from source and subdomain hosts', () async {
    SharedPreferences.setMockInitialValues({});
    final sources = SourceCatalog.createAll();
    final controller = SourceController(
      sources: sources,
      onChanged: () {},
    );
    await controller.initialize();

    final resolved = controller.findScrapperForBook({
      'coverImageUrl': 'https://cdn.mangadex.org/covers/book.jpg',
    });

    expect(resolved, same(sources.first.api));
    expect(
        controller.findScrapperForBook({'coverImageUrl': 'invalid'}), isNull);
    expect(controller.selected, same(sources.first));
  });
}
