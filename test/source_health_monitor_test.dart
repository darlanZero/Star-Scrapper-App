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
}
