import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:star_scrapper_app/pages/library_books_pages/reader_page_image.dart';

class _ControlledCompleter extends ImageStreamCompleter {
  void deliver(ui.Image image) => setImage(ImageInfo(image: image));
}

class _DelayedImage extends ImageProvider<_DelayedImage> {
  final completer = _ControlledCompleter();

  _DelayedImage() {
    final handle = completer.keepAlive();
    addTearDown(handle.dispose);
  }

  @override
  Future<_DelayedImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  void resolveStreamForKey(ImageConfiguration configuration, ImageStream stream,
      _DelayedImage key, ImageErrorListener handleError) {
    stream.setCompleter(completer);
  }
}

Future<ui.Image> _tallImage(WidgetTester tester) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(Colors.purple, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await tester.runAsync(() => picture.toImage(100, 600));
  picture.dispose();
  return image!;
}

void main() {
  testWidgets('reserves page height after disposal and delayed re-decode',
      (tester) async {
    final ratios = <int, double>{};
    final first = _DelayedImage();
    Widget page(ImageProvider<Object> image) => MaterialApp(
          home: SingleChildScrollView(
            child: ReaderPageImage(
              image: image,
              pageIndex: 0,
              aspectRatios: ratios,
              onImageReady: () {},
            ),
          ),
        );

    await tester.pumpWidget(page(first));
    expect(tester.getSize(find.byType(ReaderPageImage)).height, 800);
    first.completer.deliver(await _tallImage(tester));
    await tester.pump();
    expect(tester.getSize(find.byType(ReaderPageImage)).height, 4800);
    await tester.pumpWidget(const SizedBox());

    final reloaded = _DelayedImage();
    await tester.pumpWidget(page(reloaded));
    expect(tester.getSize(find.byType(ReaderPageImage)).height, 4800);
    reloaded.completer.reportError(
      exception: StateError('image temporarily unavailable'),
      silent: true,
    );
    await tester.pump();
    expect(tester.getSize(find.byType(ReaderPageImage)).height, 4800);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'scroll stays deep while pages reload and the stream appends pages',
      (tester) async {
    final ratios = <int, double>{for (var i = 0; i < 10; i++) i: 1 / 6};
    final controller = ScrollController();
    final pages = List.generate(12, (_) => _DelayedImage());
    Widget reader(int count) => MaterialApp(
          home: ListView.builder(
            controller: controller,
            itemCount: count,
            itemBuilder: (context, index) => ReaderPageImage(
              image: pages[index],
              pageIndex: index,
              aspectRatios: ratios,
              onImageReady: () {},
            ),
          ),
        );
    await tester.pumpWidget(reader(10));
    controller.jumpTo(15000);
    await tester.pump();
    expect(controller.offset, 15000);
    await tester.pumpWidget(reader(12));
    expect(controller.offset, 15000);
    controller.jumpTo(6000);
    await tester.pump();
    expect(controller.offset, 6000);
    pages[1].completer.deliver(await _tallImage(tester));
    await tester.pump();
    expect(controller.offset, 6000);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
