import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/application/trackers/tracker_controller.dart';
import 'package:star_scrapper_app/domain/trackers/tracker.dart';

class TrackerMediaCard extends StatelessWidget {
  final TrackerMedia media;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const TrackerMediaCard({
    super.key,
    required this.media,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final title = context.watch<TrackerController>().displayTitle(media);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  TrackerCover(uri: media.coverUri),
                  if (media.score != null)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text('${media.score}%'),
                        avatar: const Icon(Icons.star_rounded, size: 14),
                      ),
                    ),
                  if (media.progress != null)
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: Chip(
                        visualDensity: VisualDensity.compact,
                        avatar: const Icon(Icons.history_rounded, size: 14),
                        label: Text(
                          media.progressTotal == null ||
                                  media.progressTotal == 0
                              ? '${media.progress}'
                              : '${media.progress}/${media.progressTotal}',
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TrackerCover extends StatelessWidget {
  final Uri? uri;
  final double? width;
  final double? height;

  const TrackerCover({super.key, required this.uri, this.width, this.height});

  @override
  Widget build(BuildContext context) {
    if (uri == null || uri.toString().isEmpty) {
      return Container(
        width: width,
        height: height,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Icon(Icons.image_not_supported_outlined),
      );
    }
    return CachedNetworkImage(
      imageUrl: uri.toString(),
      width: width,
      height: height,
      fit: BoxFit.cover,
      errorWidget: (_, __, ___) => const Center(
        child: Icon(Icons.broken_image_outlined),
      ),
    );
  }
}
