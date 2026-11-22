import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/classes/app_state.dart';
import 'package:star_scrapper_app/components/Shared/active_scrappers.dart';
import 'package:star_scrapper_app/components/Shared/library_history.dart';
import 'package:star_scrapper_app/components/Shared/scrapper_font.dart';
import 'package:star_scrapper_app/l10n/l10n.dart';

class ScrappersScreen extends StatefulWidget {
  const ScrappersScreen({super.key});

  @override
  State<ScrappersScreen> createState() => _ScrappersScreenState();
}

class _ScrappersScreenState extends State<ScrappersScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final l10n = context.l10n;
    final tabsState = Provider.of<TabsState>(context, listen: false);
    final theme = Provider.of<ThemeProvider>(context, listen: false);
    final width = MediaQuery.of(context).size.width;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final colors = theme.selectedTheme.colorScheme;
      final appBarBase = colors.surfaceContainer;
      final scaffoldBase = theme.selectedTheme.scaffoldBackgroundColor;
      final accent = colors.primary;

      Color blend(Color a, Color b, double t) => Color.lerp(a, b, t) ?? a;
      tabsState.setAppBarBottom(
          2,
          PreferredSize(
            preferredSize: const Size.fromHeight(46.0),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: blend(appBarBase, scaffoldBase, 0.35)
                          .withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: colors.outlineVariant),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      tabs: [
                        Tab(text: l10n.sourcesTabSources),
                        Tab(text: l10n.sourcesTabManage),
                        Tab(text: l10n.sourcesTabHistory),
                        Tab(text: l10n.sourcesTabMigrate),
                      ],
                      isScrollable: true,
                      dividerColor: Colors.transparent,
                      splashBorderRadius: BorderRadius.circular(10),
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicator: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        gradient: LinearGradient(
                          colors: [
                            blend(accent, appBarBase, 0.45),
                            blend(accent, scaffoldBase, 0.25),
                          ],
                        ),
                      ),
                      labelColor: colors.onPrimary,
                      unselectedLabelColor: colors.onSurfaceVariant,
                      labelStyle: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: width >= 600 ? 14 : 12,
                      ),
                      labelPadding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                  ),
                ),
              ),
            ),
          ));
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TabBarView(
      controller: _tabController,
      children: [
        const Center(child: ScrapperActiveFonts()),
        const Center(child: ScrapperDownloaderFonts()),
        const Center(child: LibraryHistory()),
        Center(child: Text(context.l10n.sourcesTabMigrate)),
      ],
    );
  }
}
