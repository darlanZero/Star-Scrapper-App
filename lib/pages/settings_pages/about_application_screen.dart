import 'dart:convert';
import 'dart:io' show HttpException, Platform;

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutApplicationScreen extends StatefulWidget {
  const AboutApplicationScreen({super.key});

  @override
  State<AboutApplicationScreen> createState() => _AboutApplicationScreenState();
}

class _AboutApplicationScreenState extends State<AboutApplicationScreen> {
  static final Uri _repositoryUri =
      Uri.parse('https://github.com/darlanZero/Star-Scrapper-App');
  static final Uri _websiteUri =
      Uri.parse('https://starsford.com/en-US/projects/starslibrary');
  static final Uri _latestReleaseApi = Uri.parse(
    'https://api.github.com/repos/darlanZero/Star-Scrapper-App/releases/latest',
  );

  late final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();
  bool _checkingForUpdates = false;

  Future<void> _open(Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      _showMessage(title: 'Could not open link', message: uri.toString());
    }
  }

  Future<void> _checkForUpdates() async {
    if (_checkingForUpdates) return;
    setState(() => _checkingForUpdates = true);
    try {
      final results =
          await Future.wait([http.get(_latestReleaseApi), _packageInfo]);
      final response = results[0] as http.Response;
      final packageInfo = results[1] as PackageInfo;
      if (response.statusCode != 200) {
        throw HttpException('GitHub returned ${response.statusCode}.');
      }
      final release = jsonDecode(response.body) as Map<String, dynamic>;
      final releaseVersion = release['tag_name']?.toString() ?? '';
      final currentVersion = packageInfo.version;
      if (_compareVersions(releaseVersion, currentVersion) <= 0) {
        if (mounted) {
          _showMessage(
            title: 'StarsLibrary is up to date',
            message: 'You are using version $currentVersion.',
            icon: Icons.verified_rounded,
          );
        }
        return;
      }

      final assets = (release['assets'] as List?) ?? const [];
      final extension = Platform.isAndroid
          ? '.apk'
          : Platform.isWindows
              ? '.exe'
              : null;
      Map<String, dynamic>? asset;
      if (extension != null) {
        for (final candidate in assets.whereType<Map<String, dynamic>>()) {
          final name = candidate['name']?.toString().toLowerCase() ?? '';
          if (name.endsWith(extension)) {
            asset = candidate;
            break;
          }
        }
      }
      final downloadUri = Uri.tryParse(
        asset?['browser_download_url']?.toString() ??
            release['html_url']?.toString() ??
            '',
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.system_update_alt_rounded),
          title: const Text('Update available'),
          content: Text(
            'StarsLibrary $releaseVersion is available. You currently have $currentVersion.',
            textAlign: TextAlign.center,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: downloadUri == null
                  ? null
                  : () {
                      Navigator.of(dialogContext).pop();
                      _open(downloadUri);
                    },
              child: const Text('View update'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) {
        _showMessage(
          title: 'Could not check for updates',
          message: 'Check your connection and try again.',
          icon: Icons.cloud_off_rounded,
        );
      }
    } finally {
      if (mounted) setState(() => _checkingForUpdates = false);
    }
  }

  int _compareVersions(String left, String right) {
    List<int> parts(String value) => RegExp(r'\d+')
        .allMatches(value)
        .map((match) => int.parse(match.group(0)!))
        .take(3)
        .toList();

    final a = parts(left);
    final b = parts(right);
    for (var index = 0; index < 3; index++) {
      final aPart = index < a.length ? a[index] : 0;
      final bPart = index < b.length ? b[index] : 0;
      if (aPart != bPart) return aPart.compareTo(bPart);
    }
    return 0;
  }

  Future<void> _showMessage({
    required String title,
    required String message,
    IconData icon = Icons.info_outline_rounded,
  }) =>
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: Icon(icon),
          title: Text(title, textAlign: TextAlign.center),
          content: Text(message, textAlign: TextAlign.center),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            FilledButton.tonal(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 26, 16, 110),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'About StarsLibrary',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      colors.primaryContainer,
                      colors.surfaceContainerHighest,
                    ],
                  ),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 84,
                      height: 84,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colors.surface.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Image.asset(
                        'lib/assets/starscrapper.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Your stories, one library',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Browse, organize, read manga, and watch anime from your enabled sources — with tracker-powered discovery and native playback.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(
                          avatar: Icon(Icons.hub_outlined, size: 18),
                          label: Text('Multi-source'),
                        ),
                        Chip(
                          avatar: Icon(Icons.block_rounded, size: 18),
                          label: Text('No ads'),
                        ),
                        Chip(
                          avatar: Icon(Icons.code_rounded, size: 18),
                          label: Text('Open source'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Application',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 14),
                      FutureBuilder<PackageInfo>(
                        future: _packageInfo,
                        builder: (context, snapshot) {
                          final info = snapshot.data;
                          return Row(
                            children: [
                              Expanded(
                                child: _AppDatum(
                                  label: 'Version',
                                  value: info?.version ?? '—',
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _AppDatum(
                                  label: 'Build',
                                  value: info?.buildNumber ?? '—',
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed:
                            _checkingForUpdates ? null : _checkForUpdates,
                        icon: _checkingForUpdates
                            ? const SizedBox.square(
                                dimension: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.system_update_alt_rounded),
                        label: Text(
                          _checkingForUpdates
                              ? 'Checking…'
                              : 'Check for updates',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      leading: const FaIcon(FontAwesomeIcons.github),
                      title: const Text('Source code'),
                      subtitle: const Text('View the project on GitHub'),
                      trailing: const Icon(Icons.open_in_new_rounded),
                      onTap: () => _open(_repositoryUri),
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: const Icon(Icons.language_rounded),
                      title: const Text('StarsLibrary website'),
                      subtitle: const Text('Project news and information'),
                      trailing: const Icon(Icons.open_in_new_rounded),
                      onTap: () => _open(_websiteUri),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'StarsLibrary does not host third-party content and is not affiliated with content providers, authors, or publishers.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppDatum extends StatelessWidget {
  final String label;
  final String value;

  const _AppDatum({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}
