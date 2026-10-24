import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/application/trackers/tracker_controller.dart';
import 'package:star_scrapper_app/domain/trackers/tracker.dart';
import 'package:star_scrapper_app/pages/settings_pages/subsettings_pages/tracker_oauth_webview_screen.dart';

class TrackerSettingsScreen extends StatefulWidget {
  const TrackerSettingsScreen({super.key});

  @override
  State<TrackerSettingsScreen> createState() => _TrackerSettingsScreenState();
}

class _TrackerSettingsScreenState extends State<TrackerSettingsScreen> {
  late final TextEditingController _aniListClientId;
  late final TextEditingController _aniListRedirect;
  late final TextEditingController _malClientId;
  late final TextEditingController _malRedirect;

  @override
  void initState() {
    super.initState();
    final tracker = context.read<TrackerController>();
    _aniListClientId = TextEditingController(text: tracker.aniListClientId);
    _aniListRedirect = TextEditingController(text: tracker.aniListRedirectUri);
    _malClientId = TextEditingController(text: tracker.malClientId);
    _malRedirect = TextEditingController(text: tracker.malRedirectUri);
  }

  @override
  Widget build(BuildContext context) {
    final tracker = context.watch<TrackerController>();
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Trackers')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 40),
        children: [
          Text('Discovery and tracking',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(
            'Discover anime and manga with tracker metadata, then match titles against your enabled sources.',
            style: TextStyle(color: colors.onSurfaceVariant, height: 1.4),
          ),
          const SizedBox(height: 20),
          _TrackerCard(
            title: 'AniList',
            subtitle: 'Public catalog, dynamic tags and airing calendar',
            icon: Icons.auto_awesome_rounded,
            enabled: tracker.aniListEnabled,
            onChanged: tracker.setAniListEnabled,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Login is optional for discovery and required only for future personal-list synchronization.',
                ),
                const SizedBox(height: 14),
                _AccountStatus(account: tracker.aniListAccount),
                const SizedBox(height: 12),
                if (tracker.aniListConfigurationManaged)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.developer_mode_rounded),
                    title: const Text('Configured by this build'),
                    subtitle: Text(
                      '${tracker.aniListClientName} · Client ID ${tracker.aniListClientId}\n${tracker.aniListRedirectUri}',
                    ),
                  )
                else
                  _OAuthFields(
                    clientId: _aniListClientId,
                    redirect: _aniListRedirect,
                    clientIdLabel: 'AniList Client ID',
                  ),
                const SizedBox(height: 12),
                _OAuthActions(
                  connected: tracker.aniListConnected,
                  busy: tracker.authBusy,
                  onSave: _save,
                  onConnect: _connectAniList,
                  onDisconnect: () => tracker.disconnect(TrackerKind.aniList),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _TrackerCard(
            title: 'MyAnimeList',
            subtitle: 'Rankings, seasonal catalogs and account lists',
            icon: Icons.list_alt_rounded,
            enabled: tracker.malEnabled,
            onChanged:
                tracker.malClientId.isEmpty ? null : tracker.setMalEnabled,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                    'MAL requires a Client ID even for public requests.'),
                const SizedBox(height: 14),
                _AccountStatus(account: tracker.malAccount),
                const SizedBox(height: 12),
                _OAuthFields(
                  clientId: _malClientId,
                  redirect: _malRedirect,
                  clientIdLabel: 'MAL Client ID',
                ),
                const SizedBox(height: 12),
                _OAuthActions(
                  connected: tracker.malConnected,
                  busy: tracker.authBusy,
                  onSave: _save,
                  onConnect: _connectMal,
                  onDisconnect: () =>
                      tracker.disconnect(TrackerKind.myAnimeList),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: SwitchListTile(
              value: tracker.includeAdult,
              onChanged: tracker.setIncludeAdult,
              secondary: const Icon(Icons.visibility_outlined),
              title: const Text('Include adult content'),
              subtitle: const Text(
                'Works with public tracker data; login is not required.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: SwitchListTile(
              value: tracker.preferEnglishTitles,
              onChanged: tracker.setPreferEnglishTitles,
              secondary: const Icon(Icons.translate_rounded),
              title: const Text('Prefer English titles'),
              subtitle: const Text(
                'Off by default. Romaji titles are used whenever available.',
              ),
            ),
          ),
          if (tracker.authError != null) ...[
            const SizedBox(height: 12),
            Card(
              color: colors.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(tracker.authError!,
                    style: TextStyle(color: colors.onErrorContainer)),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Card(
            color: colors.secondaryContainer.withValues(alpha: 0.45),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Register StarsLibrary in each tracker and use the exact redirect URI shown here. Tokens are kept in secure device storage; passwords and client secrets are never stored.',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    await context.read<TrackerController>().setOAuthConfiguration(
          aniListClientId: _aniListClientId.text,
          aniListRedirectUri: _aniListRedirect.text,
          malClientId: _malClientId.text,
          malRedirectUri: _malRedirect.text,
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tracker configuration saved.')),
      );
    }
  }

  Future<void> _connectAniList() async {
    try {
      await _save();
      if (!mounted) return;
      final tracker = context.read<TrackerController>();
      final redirect = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => TrackerOAuthWebViewScreen(
            providerName: 'AniList',
            authorizationUri: tracker.createAniListAuthorizationUri(),
            redirectUri: tracker.aniListRedirectUri,
          ),
        ),
      );
      if (redirect == null || !mounted) return;
      await tracker.completeAniListAuthorization(redirect);
      if (mounted) _showConnected('AniList');
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _connectMal() async {
    try {
      await _save();
      if (!mounted) return;
      final tracker = context.read<TrackerController>();
      final session = tracker.createMalAuthorization();
      final redirect = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => TrackerOAuthWebViewScreen(
            providerName: 'MyAnimeList',
            authorizationUri: session.authorizationUri,
            redirectUri: tracker.malRedirectUri,
          ),
        ),
      );
      if (redirect == null || !mounted) return;
      await tracker.completeMalAuthorization(session, redirect);
      if (mounted) _showConnected('MyAnimeList');
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  void _showConnected(String provider) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$provider account connected.')),
      );

  void _showError(Object error) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );

  @override
  void dispose() {
    _aniListClientId.dispose();
    _aniListRedirect.dispose();
    _malClientId.dispose();
    _malRedirect.dispose();
    super.dispose();
  }
}

class _OAuthFields extends StatelessWidget {
  final TextEditingController clientId;
  final TextEditingController redirect;
  final String clientIdLabel;

  const _OAuthFields({
    required this.clientId,
    required this.redirect,
    required this.clientIdLabel,
  });

  @override
  Widget build(BuildContext context) => Column(
        children: [
          TextField(
            controller: clientId,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: clientIdLabel,
              prefixIcon: const Icon(Icons.key_outlined),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: redirect,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Registered redirect URI',
              prefixIcon: Icon(Icons.link_rounded),
            ),
          ),
        ],
      );
}

class _OAuthActions extends StatelessWidget {
  final bool connected;
  final bool busy;
  final VoidCallback onSave;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  const _OAuthActions({
    required this.connected,
    required this.busy,
    required this.onSave,
    required this.onConnect,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: busy ? null : onSave,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save'),
          ),
          if (connected)
            FilledButton.tonalIcon(
              onPressed: busy ? null : onDisconnect,
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Disconnect'),
            )
          else
            FilledButton.icon(
              onPressed: busy ? null : onConnect,
              icon: const Icon(Icons.login_rounded),
              label: const Text('Connect'),
            ),
        ],
      );
}

class _AccountStatus extends StatelessWidget {
  final TrackerAccount? account;
  const _AccountStatus({required this.account});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          foregroundImage: account?.avatarUri == null
              ? null
              : NetworkImage('${account!.avatarUri}'),
          child: Icon(account == null ? Icons.person_outline : Icons.person),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            account == null
                ? 'Not connected'
                : 'Connected as ${account!.username}',
            style: TextStyle(
              color: account == null ? colors.onSurfaceVariant : colors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _TrackerCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool enabled;
  final ValueChanged<bool>? onChanged;
  final Widget child;

  const _TrackerCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.enabled,
    required this.onChanged,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: colors.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: TextStyle(color: colors.onSurfaceVariant)),
                    ],
                  ),
                ),
                Switch(value: enabled, onChanged: onChanged),
              ],
            ),
            const SizedBox(height: 14),
            DefaultTextStyle.merge(
              style: TextStyle(color: colors.onSurfaceVariant, height: 1.35),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}
