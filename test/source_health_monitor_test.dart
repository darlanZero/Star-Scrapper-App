import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/application/sources/source_health_monitor.dart';
import 'package:star_scrapper_app/data/sources/source_catalog.dart';

void main() {
  test('migrates health status from display names to stable source IDs',
      () async {
    SharedPreferences.setMockInitialValues({
      'fontHostAutoCheckEnabled': false,
      'fontHostStatusByName': jsonEncode({'Mangadex': 'outdated'}),
    });
    final sources = SourceCatalog.createAll();
    final monitor = SourceHealthMonitor(
      sources: sources,
      onChanged: () {},
      isReachable: (_) async => true,
    );

    await monitor.initialize();

    expect(monitor.statusForName('Mangadex'), FontHostStatus.outdated);
    expect(sources.first.isOutdated, isTrue);
    final prefs = await SharedPreferences.getInstance();
    final persisted = jsonDecode(
      prefs.getString('sourceHostStatusById')!,
    ) as Map<String, dynamic>;
    expect(persisted['mangadex'], 'outdated');
    monitor.dispose();
  });

  test('checks sources through an injectable reachability function', () async {
    SharedPreferences.setMockInitialValues({
      'fontHostAutoCheckEnabled': false,
    });
    final sources = SourceCatalog.createAll();
    final checkedHosts = <String>[];
    final monitor = SourceHealthMonitor(
      sources: sources,
      onChanged: () {},
      isReachable: (uri) async {
        checkedHosts.add(uri.host);
        return uri.host == 'mangadex.org';
      },
    );

    await monitor.initialize();
    await monitor.checkAllNow();

    expect(checkedHosts, isNotEmpty);
    expect(monitor.statusForName('Mangadex'), FontHostStatus.online);
    expect(monitor.statusForName('LuraToons'), FontHostStatus.outdated);
    monitor.dispose();
  });

  test('checks anime sources alongside manga sources', () async {
    SharedPreferences.setMockInitialValues({
      'fontHostAutoCheckEnabled': false,
    });
    final checkedHosts = <String>[];
    final monitor = SourceHealthMonitor(
      sources: SourceCatalog.createAll(),
      animeSources: SourceCatalog.createAnimeSources(),
      onChanged: () {},
      isReachable: (uri) async {
        checkedHosts.add(uri.host);
        return uri.host == 'anitube.online';
      },
    );

    await monitor.initialize();
    await monitor.checkAllNow();

    expect(checkedHosts, contains('anitube.online'));
    expect(checkedHosts, contains('mangadex.org'));
    expect(monitor.statusForId('anitube'), FontHostStatus.online);
    expect(monitor.statusForId('aniwave'), FontHostStatus.outdated);
    expect(
      monitor.entries.where(
        (entry) => entry.contentType.name == 'anime',
      ),
      hasLength(SourceCatalog.createAnimeSources().length),
    );
    monitor.dispose();
  });

  test('automatically checks newly added source IDs', () async {
    SharedPreferences.setMockInitialValues({
      'fontHostAutoCheckEnabled': true,
      'sourceHostStatusById': jsonEncode({'mangadex': 'online'}),
    });
    final checkedHosts = <String>[];
    final monitor = SourceHealthMonitor(
      sources: SourceCatalog.createAll().take(1).toList(),
      animeSources: SourceCatalog.createAnimeSources().take(1).toList(),
      onChanged: () {},
      isReachable: (uri) async {
        checkedHosts.add(uri.host);
        return true;
      },
    );

    await monitor.initialize();
    for (var i = 0;
        i < 10 && monitor.statusForId('anitube') != FontHostStatus.online;
        i++) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(checkedHosts, contains('anitube.online'));
    expect(monitor.statusForId('anitube'), FontHostStatus.online);
    monitor.dispose();
  });
}
