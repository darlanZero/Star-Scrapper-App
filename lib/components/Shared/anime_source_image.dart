import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:star_scrapper_app/domain/sources/anime_source.dart';

class AnimeSourceImage extends StatelessWidget {
  final AnimeSource source;
  final Uri uri;
  final BoxFit fit;
  final double? width;
  final double? height;
  final WidgetBuilder? placeholderBuilder;
  final WidgetBuilder? errorBuilder;

  const AnimeSourceImage({
    super.key,
    required this.source,
    required this.uri,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholderBuilder,
    this.errorBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final placeholder = placeholderBuilder?.call(context) ??
        const Center(child: CircularProgressIndicator());
    final error = errorBuilder?.call(context) ??
        const Center(child: Icon(Icons.broken_image_outlined));
    if (source case final BrowserImageAnimeSource browserSource) {
      return FutureBuilder(
        future: browserSource.loadBrowserImage(uri),
        builder: (context, snapshot) {
          if (snapshot.hasError) return error;
          final bytes = snapshot.data;
          if (bytes == null) return placeholder;
          return Image.memory(
            bytes,
            width: width,
            height: height,
            fit: fit,
            gaplessPlayback: true,
          );
        },
      );
    }
    return CachedNetworkImage(
      imageUrl: uri.toString(),
      httpHeaders: source.requestHeaders,
      width: width,
      height: height,
      fit: fit,
      placeholder: (_, __) => placeholder,
      errorWidget: (_, __, ___) => error,
    );
  }
}
