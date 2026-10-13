import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/application/trackers/tracker_controller.dart';
import 'package:star_scrapper_app/components/UI/tracker_media_card.dart';
import 'package:star_scrapper_app/domain/trackers/tracker.dart';
import 'package:star_scrapper_app/pages/tracker_source_search.dart';
import 'package:url_launcher/url_launcher.dart';

class TrackerMediaDetailsScreen extends StatefulWidget {
  final TrackerMedia media;

  const TrackerMediaDetailsScreen({super.key, required this.media});

  @override
  State<TrackerMediaDetailsScreen> createState() =>
      _TrackerMediaDetailsScreenState();
}

class _TrackerMediaDetailsScreenState extends State<TrackerMediaDetailsScreen> {
  late Future<TrackerMediaDetails> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<TrackerController>().loadDetails(widget.media);
  }

  void _retry() => setState(() {
        _future = context.read<TrackerController>().loadDetails(widget.media);
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<TrackerMediaDetails>(
        future: _future,
        builder: (context, snapshot) {
          final details = snapshot.data;
          final media = details?.media ?? widget.media;
          return CustomScrollView(
            slivers: [
              _DetailsAppBar(media: media),
              if (snapshot.connectionState != ConnectionState.done)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (snapshot.hasError)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _DetailsError(
                    media: media,
                    error: snapshot.error,
                    onRetry: _retry,
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 20, 18, 120),
                  sliver: SliverList.list(
                    children: [_DetailsBody(details: details!)],
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openTrackerSourceSearch(context, widget.media),
        icon: const Icon(Icons.search_rounded),
        label: const Text('Search sources'),
      ),
    );
  }
}

class _DetailsAppBar extends StatelessWidget {
  final TrackerMedia media;

  const _DetailsAppBar({required this.media});

  @override
  Widget build(BuildContext context) {
    final title = context.watch<TrackerController>().displayTitle(media);
    final colors = Theme.of(context).colorScheme;
    return SliverAppBar(
      expandedHeight: 310,
      pinned: true,
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (media.bannerUri != null)
              CachedNetworkImage(
                imageUrl: media.bannerUri.toString(),
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(color: colors.surface),
              )
            else
              Container(color: colors.surfaceContainerHighest),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.16),
                    colors.surface.withValues(alpha: 0.98),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 18,
              right: 18,
              bottom: 18,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: TrackerCover(
                      uri: media.coverUri,
                      width: 108,
                      height: 158,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (media.title.native != null) ...[
                          const SizedBox(height: 5),
                          Text(
                            media.title.native!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailsBody extends StatelessWidget {
  final TrackerMediaDetails details;

  const _DetailsBody({required this.details});

  @override
  Widget build(BuildContext context) {
    final media = details.media;
    final facts = <String>[
      if (details.format != null) details.format!,
      if (details.status != null) details.status!,
      if (details.source != null) details.source!,
      if (details.episodes != null) '${details.episodes} episodes',
      if (details.chapters != null) '${details.chapters} chapters',
      if (details.volumes != null) '${details.volumes} volumes',
      if (details.durationMinutes != null)
        '${details.durationMinutes} min / episode',
      if (media.score != null) '${media.score}% score',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (facts.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: facts.map((fact) => Chip(label: Text(fact))).toList(),
          ),
        if (media.startDate != null || media.endDate != null) ...[
          const SizedBox(height: 16),
          Text(
            _dateRange(media.startDate, media.endDate),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
        if (media.description.isNotEmpty) ...[
          const SizedBox(height: 24),
          const _SectionTitle('Synopsis'),
          const SizedBox(height: 8),
          SelectableText(media.description),
        ],
        if (media.genres.isNotEmpty) ...[
          const SizedBox(height: 24),
          const _SectionTitle('Genres'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                media.genres.map((genre) => Chip(label: Text(genre))).toList(),
          ),
        ],
        if (media.tags.isNotEmpty) ...[
          const SizedBox(height: 24),
          const _SectionTitle('Tags'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: media.tags.map((tag) => Chip(label: Text(tag))).toList(),
          ),
        ],
        if (details.studios.isNotEmpty) ...[
          const SizedBox(height: 24),
          const _SectionTitle('Studios & publishers'),
          const SizedBox(height: 8),
          Text(details.studios.join(' • ')),
        ],
        if (details.creators.isNotEmpty) ...[
          const SizedBox(height: 24),
          const _SectionTitle('Creators & staff'),
          const SizedBox(height: 10),
          _CreditsList(credits: details.creators),
        ],
        if (details.voiceActors.isNotEmpty) ...[
          const SizedBox(height: 24),
          const _SectionTitle('Voice cast'),
          const SizedBox(height: 10),
          _CreditsList(credits: details.voiceActors),
        ],
        if (details.reviews.isNotEmpty) ...[
          const SizedBox(height: 24),
          const _SectionTitle('Reviews'),
          const SizedBox(height: 8),
          ...details.reviews.map((review) => _ReviewCard(review: review)),
        ],
        if (media.siteUri != null) ...[
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => launchUrl(
              media.siteUri!,
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('Open on tracker'),
          ),
        ],
      ],
    );
  }

  static String _dateRange(DateTime? start, DateTime? end) {
    final formatter = DateFormat.yMMMd();
    if (start != null && end != null) {
      return '${formatter.format(start)} – ${formatter.format(end)}';
    }
    return start != null
        ? 'Started ${formatter.format(start)}'
        : 'Ended ${formatter.format(end!)}';
  }
}

class _CreditsList extends StatelessWidget {
  final List<TrackerCredit> credits;

  const _CreditsList({required this.credits});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 102,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: credits.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final credit = credits[index];
          return SizedBox(
            width: 210,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      foregroundImage: credit.imageUri == null
                          ? null
                          : NetworkImage(credit.imageUri.toString()),
                      child: const Icon(Icons.person_outline_rounded),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            credit.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          Text(
                            credit.role,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final TrackerReview review;

  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) {
    final heading = review.summary.isNotEmpty ? review.summary : 'Review';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: CircleAvatar(
          foregroundImage: review.avatarUri == null
              ? null
              : NetworkImage(review.avatarUri.toString()),
          child: const Icon(Icons.rate_review_outlined),
        ),
        title: Text(heading, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text([
          if (review.username != null) review.username!,
          if (review.rating != null) '${review.rating} helpful votes',
        ].join(' • ')),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if (review.body.isNotEmpty) SelectableText(review.body),
          if (review.siteUri != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => launchUrl(
                  review.siteUri!,
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Read full review'),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.titleLarge);
}

class _DetailsError extends StatelessWidget {
  final TrackerMedia media;
  final Object? error;
  final VoidCallback onRetry;

  const _DetailsError({
    required this.media,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 44),
              const SizedBox(height: 12),
              Text(
                media.description.isEmpty
                    ? 'Could not load metadata.\n$error'
                    : media.description,
                textAlign: TextAlign.center,
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
}
