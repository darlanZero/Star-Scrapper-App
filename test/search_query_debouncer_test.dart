import 'package:flutter_test/flutter_test.dart';
import 'package:star_scrapper_app/pages/search_screen.dart';

void main() {
  testWidgets('runs only the latest query after typing becomes idle',
      (tester) async {
    final completed = <String>[];
    final debouncer = SearchQueryDebouncer(const Duration(milliseconds: 350));

    debouncer.schedule(() => completed.add('g'));
    await tester.pump(const Duration(milliseconds: 100));
    debouncer.schedule(() => completed.add('gl'));
    await tester.pump(const Duration(milliseconds: 100));
    debouncer.schedule(() => completed.add('gla'));

    await tester.pump(const Duration(milliseconds: 349));
    expect(completed, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(completed, ['gla']);

    debouncer.dispose();
  });

  testWidgets('cancel prevents pending search work', (tester) async {
    var searches = 0;
    final debouncer = SearchQueryDebouncer(const Duration(milliseconds: 350));

    debouncer.schedule(() => searches++);
    debouncer.cancel();
    await tester.pump(const Duration(milliseconds: 350));

    expect(searches, 0);
    debouncer.dispose();
  });
}
