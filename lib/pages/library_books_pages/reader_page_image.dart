import 'package:flutter/material.dart';

/// Keeps page geometry even when a lazy list discards the decoded image.
/// The chapter owns [aspectRatios], so it outlives individual list children.
class ReaderPageImage extends StatefulWidget {
  const ReaderPageImage({
    super.key,
    required this.image,
    required this.pageIndex,
    required this.aspectRatios,
    required this.onImageReady,
  });

  final ImageProvider<Object> image;
  final int pageIndex;
  final Map<int, double> aspectRatios;
  final VoidCallback onImageReady;

  @override
  State<ReaderPageImage> createState() => _ReaderPageImageState();
}

class _ReaderPageImageState extends State<ReaderPageImage> {
  ImageStream? _stream;
  late final ImageStreamListener _listener = ImageStreamListener(
    (info, synchronousCall) {
      final ratio = info.image.width / info.image.height;
      info.dispose();
      if (!mounted) return;
      if (widget.aspectRatios[widget.pageIndex] != ratio) {
        setState(() => widget.aspectRatios[widget.pageIndex] = ratio);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onImageReady();
      });
    },
    onError: (Object error, StackTrace? stack) {
      // The Image widget presents the error without collapsing the page.
    },
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImage();
  }

  @override
  void didUpdateWidget(ReaderPageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) _resolveImage();
  }

  void _resolveImage() {
    final stream = widget.image.resolve(createLocalImageConfiguration(context));
    if (_stream?.key == stream.key) return;
    _stream?.removeListener(_listener);
    _stream = stream;
    stream.addListener(_listener);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: widget.aspectRatios[widget.pageIndex] ?? 1,
      child: Image(
        image: widget.image,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stack) => const Center(
          child: Icon(Icons.broken_image_outlined),
        ),
      ),
    );
  }
}
