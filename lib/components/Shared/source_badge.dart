import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class SourceBadge extends StatelessWidget {
  final String name;
  final Uri? imageUri;
  final Map<String, String> headers;
  final bool showLabel;
  final double iconSize;

  const SourceBadge({
    super.key,
    required this.name,
    required this.imageUri,
    this.headers = const {},
    this.showLabel = true,
    this.iconSize = 22,
  });

  @override
  Widget build(BuildContext context) {
    final image = imageUri?.toString() ?? '';
    final icon = ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: SizedBox.square(
        dimension: iconSize,
        child: image.toLowerCase().contains('.svg')
            ? SvgPicture.network(
                image,
                headers: headers,
                fit: BoxFit.contain,
                placeholderBuilder: (_) => _fallback(),
              )
            : image.isEmpty
                ? _fallback()
                : CachedNetworkImage(
                    imageUrl: image,
                    httpHeaders: headers,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _fallback(),
                  ),
      ),
    );

    return Semantics(
      label: 'Source: $name',
      child: Tooltip(
        message: 'Source: $name',
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: showLabel ? 8 : 5,
            vertical: 5,
          ),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .72),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              if (showLabel) ...[
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _fallback() => ColoredBox(
        color: const Color(0xFF483D8B),
        child: Center(
          child: Text(
            name.isEmpty ? '?' : name.characters.first.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
}
