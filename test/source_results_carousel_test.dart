import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:star_scrapper_app/components/search/source_results_carousel.dart';

void main() {
  testWidgets('keeps sources vertical and each result carousel horizontal',
      (tester) async {
    var firstMorePressed = false;
    var secondMorePressed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SourceResultsCarousel(
            panels: [
              SourceResultsPanel(
                id: 'first',
                title: 'First source',
                icon: Icons.public,
                resultCount: 3,
                previewCount: 3,
                onMore: () => firstMorePressed = true,
                itemBuilder: (_, index) => Text('First result $index'),
              ),
              SourceResultsPanel(
                id: 'second',
                title: 'Second source',
                icon: Icons.public,
                resultCount: 1,
                previewCount: 1,
                onMore: () => secondMorePressed = true,
                itemBuilder: (_, __) => const Text('Second result'),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('source-panel-first')), findsOneWidget);
    expect(find.byKey(const ValueKey('source-panel-second')), findsOneWidget);
    expect(find.text('First source (3)'), findsOneWidget);
    expect(find.text('Second source (1)'), findsOneWidget);

    final firstCarousel = find.byKey(const ValueKey('source-results-first'));
    final firstList = tester.widget<ListView>(firstCarousel);
    expect(firstList.scrollDirection, Axis.horizontal);

    await tester.drag(firstCarousel, const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('First result 2'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('source-panel-first')),
        matching: find.text('More'),
      ),
    );
    expect(firstMorePressed, isTrue);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('source-panel-second')),
        matching: find.text('More'),
      ),
    );
    expect(secondMorePressed, isTrue);
  });

  testWidgets('allows a tall source error state without overflowing',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SourceResultsCarousel(
            panels: [
              SourceResultsPanel(
                id: 'failed',
                title: 'Failed source',
                icon: Icons.cloud_off,
                resultCount: 0,
                previewCount: 0,
                emptyState: const Padding(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_off, size: 40),
                      SizedBox(height: 10),
                      Text('Could not search this source'),
                      SizedBox(height: 6),
                      Text(
                          'A long explanation that may wrap onto another line.'),
                      SizedBox(height: 10),
                      FilledButton(onPressed: null, child: Text('Verify')),
                    ],
                  ),
                ),
                itemBuilder: (_, __) => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Could not search this source'), findsOneWidget);
  });
}
