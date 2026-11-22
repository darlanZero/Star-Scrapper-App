import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/application/trackers/tracker_controller.dart';
import 'package:star_scrapper_app/domain/trackers/tracker.dart';
import 'package:star_scrapper_app/l10n/l10n.dart';
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
      appBar: AppBar(title: Text(context.l10n.accountTrackersTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 40),
        children: [
          Text(context.l10n.discoveryAndTrackingTitle,
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(
            context.l10n.discoveryAndTrackingDesc,
            style: TextStyle(color: colors.onSurfaceVariant, height: 1.4),
          ),
          const SizedBox(height: 20),
          _TrackerCard(
            title: 'AniList',
            subtitle: context.l10n.aniListSubtitle,
            icon: Icons.auto_awesome_rounded,
            enabled: tracker.aniListEnabled,
            onChanged: tracker.setAniListEnabled,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.aniListOptionalLoginNote),
                const SizedBox(height: 14),
                _AccountStatus(account: tracker.aniListAccount),
                const SizedBox(height: 12),
                if (tracker.aniListConfigurationManaged)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.developer_mode_rounded),
                    title: Text(context.l10n.configuredByBuild),
                    subtitle: Text(
                      '${tracker.aniListClientName} · Client ID ${tracker.aniListClientId}\n${tracker.aniListRedirectUri}',
                    ),
                  )
                else
                  _OAuthFields(
                    clientId: _aniListClientId,
                    redirect: _aniListRedirect,
                    clientIdLabel: context.l10n.aniListClientIdLabel,
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
            subtitle: context.l10n.malSubtitle,
            icon: Icons.list_alt_rounded,
            enabled: tracker.malEnabled,
            onChanged:
                tracker.malClientId.isEmpty ? null : tracker.setMalEnabled,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.malClientIdRequiredNote),
                const SizedBox(height: 14),
                _AccountStatus(account: tracker.malAccount),
                const SizedBox(height: 12),
                _OAuthFields(
                  clientId: _malClientId,
                  redirect: _malRedirect,
                  clientIdLabel: context.l10n.malClientIdLabel,
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
              title: Text(context.l10n.includeAdultContentTitle),
              subtitle: Text(context.l10n.includeAdultContentDesc),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: SwitchListTile(
              value: tracker.preferEnglishTitles,
              onChanged: tracker.setPreferEnglishTitles,
              secondary: const Icon(Icons.translate_rounded),
              title: Text(context.l10n.preferEnglishTitlesTitle),
              subtitle: Text(context.l10n.preferEnglishTitlesDesc),
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
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(context.l10n.trackerSecurityNote),
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
        SnackBar(content: Text(context.l10n.trackerConfigSaved)),
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
        SnackBar(content: Text(context.l10n.trackerAccountConnected(provider))),
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
            decoration: InputDecoration(
              labelText: context.l10n.registeredRedirectUriLabel,
              prefixIcon: const Icon(Icons.link_rounded),
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
            label: Text(context.l10n.save),
          ),
          if (connected)
            FilledButton.tonalIcon(
              onPressed: busy ? null : onDisconnect,
              icon: const Icon(Icons.logout_rounded),
              label: Text(context.l10n.disconnectAction),
            )
          else
            FilledButton.icon(
              onPressed: busy ? null : onConnect,
              icon: const Icon(Icons.login_rounded),
              label: Text(context.l10n.connectAction),
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
                ? context.l10n.notConnected
                : context.l10n.connectedAs(account!.username),
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
