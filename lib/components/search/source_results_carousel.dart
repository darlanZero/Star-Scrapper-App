import 'package:flutter/material.dart';

class SourceResultsPanel {
  final String id;
  final String title;
  final IconData icon;
  final int resultCount;
  final int previewCount;
  final IndexedWidgetBuilder itemBuilder;
  final VoidCallback? onMore;
  final Widget? emptyState;
  final bool isLoading;

  const SourceResultsPanel({
    required this.id,
    required this.title,
    required this.icon,
    required this.resultCount,
    required this.previewCount,
    required this.itemBuilder,
    this.onMore,
    this.emptyState,
    this.isLoading = false,
  });
}

/// Displays sources from top to bottom. The titles belonging to each source
/// form an independent horizontal carousel inside that source section.
class SourceResultsCarousel extends StatelessWidget {
  final List<SourceResultsPanel> panels;

  const SourceResultsCarousel({super.key, required this.panels});

  @override
  Widget build(BuildContext context) {
    if (panels.isEmpty) return const SizedBox.shrink();

    return ListView.builder(
      key: const ValueKey('source-results-list'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      itemCount: panels.length,
      itemBuilder: (context, index) {
        final panel = panels[index];
        return Padding(
          padding: EdgeInsets.only(bottom: index == panels.length - 1 ? 0 : 12),
          child: _SourceResultsSection(panel: panel),
        );
      },
    );
  }
}

class _SourceResultsSection extends StatelessWidget {
  final SourceResultsPanel panel;

  const _SourceResultsSection({required this.panel});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      key: ValueKey('source-panel-${panel.id}'),
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 6),
            child: Row(
              children: [
                Icon(panel.icon, size: 20, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    panel.isLoading
                        ? '${panel.title} · Searching…'
                        : '${panel.title} (${panel.resultCount})',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (panel.onMore != null)
                  TextButton(
                    onPressed: panel.onMore,
                    child: const Text('More'),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (panel.isLoading)
            const SizedBox(
              height: 92,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                    SizedBox(width: 12),
                    Text('Searching this source…'),
                  ],
                ),
              ),
            )
          else if (panel.previewCount == 0)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 132),
              child: panel.emptyState ??
                  const Center(child: Text('No results in this source.')),
            )
          else
            SizedBox(
              height: 92,
              child: ListView.separated(
                key: ValueKey('source-results-${panel.id}'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                itemCount: panel.previewCount,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) => SizedBox(
                  width: 276,
                  child: Material(
                    color:
                        colors.surfaceContainerHighest.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(10),
                    clipBehavior: Clip.antiAlias,
                    child: panel.itemBuilder(context, index),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
