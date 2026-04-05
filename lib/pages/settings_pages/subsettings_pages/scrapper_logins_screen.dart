import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/classes/Scrappers/engine/auth_webview_screen.dart';
import 'package:star_scrapper_app/classes/Scrappers/engine/scrapper_profile.dart';
import 'package:star_scrapper_app/classes/Scrappers/engine/session_manager.dart';
import 'package:star_scrapper_app/classes/app_state.dart';
import 'package:star_scrapper_app/classes/static/fonts_provider.dart';
import 'package:star_scrapper_app/components/Shared/scrapper_font.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// ScrapperLoginsScreen
/// ─────────────────────────────────────────────────────────────────────────────
///
/// Página de gerenciamento de sessões por scrapper.
/// Mostra quais scrapers têm login salvo, permite fazer login/logout
/// e visualizar as chaves de sessão armazenadas.
class ScrapperLoginsScreen extends StatefulWidget {
  const ScrapperLoginsScreen({super.key});

  @override
  State<ScrapperLoginsScreen> createState() => _ScrapperLoginsScreenState();
}

class _ScrapperLoginsScreenState extends State<ScrapperLoginsScreen> {
  // siteKey → map de cookies/tokens armazenados
  final Map<String, Map<String, String>> _sessions = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAllSessions();
  }

  Future<void> _loadAllSessions() async {
    final fontProvider = Provider.of<FontProvider>(context, listen: false);
    final authFonts = fontProvider.fonts.where(
      (f) => f.api.scrapperProfile != null,
    );
    final Map<String, Map<String, String>> loaded = {};
    for (final font in authFonts) {
      final key = font.api.siteKey;
      if (key.isNotEmpty) {
        loaded[key] = await SessionManager.loadCookies(key);
      }
    }
    if (mounted) {
      setState(() {
        _sessions.clear();
        _sessions.addAll(loaded);
        _loading = false;
      });
    }
  }

  Future<void> _doLogin(Fonte font) async {
    final profile = font.api.scrapperProfile!;
    await showAuthWebView(
      context: context,
      profile: profile,
      onSuccess: (cookies) => font.api.updateSession(cookies),
    );
    await _loadAllSessions();
  }

  Future<void> _doLogout(Fonte font) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Logout de ${font.name}'),
        content: const Text(
          'This will remove the saved session for this scrapper. Are you sure you want to logout?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Logout', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await font.api.logout();
      await _loadAllSessions();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    final fontProvider = Provider.of<FontProvider>(context);
    final textColor = theme.selectedTheme.textTheme.bodyLarge?.color;
    final subtitleColor = theme.selectedTheme.textTheme.bodySmall?.color;
    final cardColor = theme.selectedTheme.cardColor;

    final authFonts = fontProvider.fonts.where(
      (f) => f.api.scrapperProfile != null,
    ).toList();

    return Scaffold(
      backgroundColor: theme.selectedTheme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.selectedTheme.appBarTheme.backgroundColor,
        iconTheme: theme.selectedTheme.iconTheme,
        title: Text(
          'Scrapper Logins',
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Cabeçalho explicativo ─────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.selectedTheme.dividerColor,
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: theme.selectedTheme.iconTheme.color,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Manage the logins for sites that require authentication. '
                            'Tokens are stored locally on the device. '
                            'Logout to remove an expired or compromised token.',
                            style: TextStyle(
                              color: subtitleColor,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  if (authFonts.isEmpty)
                    Center(
                      child: Text(
                        'No scrappers with authentication configured.',
                        style: TextStyle(color: subtitleColor),
                      ),
                    )
                  else
                    ...authFonts.map((font) {
                      final key = font.api.siteKey;
                      final session = _sessions[key] ?? {};
                      final isLoggedIn = session.isNotEmpty;
                      final profile = font.api.scrapperProfile!;

                      return _ScrapperLoginCard(
                        font: font,
                        profile: profile,
                        session: session,
                        isLoggedIn: isLoggedIn,
                        cardColor: cardColor,
                        textColor: textColor,
                        subtitleColor: subtitleColor,
                        theme: theme,
                        onLogin: () => _doLogin(font),
                        onLogout: () => _doLogout(font),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}

// ─── Card individual de scrapper ────────────────────────────────────────────

class _ScrapperLoginCard extends StatelessWidget {
  final Fonte font;
  final ScrapperProfile profile;
  final Map<String, String> session;
  final bool isLoggedIn;
  final Color? cardColor;
  final Color? textColor;
  final Color? subtitleColor;
  final ThemeProvider theme;
  final VoidCallback onLogin;
  final VoidCallback onLogout;

  const _ScrapperLoginCard({
    required this.font,
    required this.profile,
    required this.session,
    required this.isLoggedIn,
    required this.cardColor,
    required this.textColor,
    required this.subtitleColor,
    required this.theme,
    required this.onLogin,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = isLoggedIn ? Colors.green : Colors.orange;
    final statusLabel = isLoggedIn ? 'Connected' : 'Disconnected';
    final sessionKeys = session.keys.toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLoggedIn
              ? Colors.green.withOpacity(0.35)
              : theme.selectedTheme.dividerColor,
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header: logo + nome + status ───────────────────────────────
          Row(
            children: [
              // Logo
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  font.image,
                  width: 40,
                  height: 40,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: theme.selectedTheme.dividerColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.public,
                      color: textColor,
                      size: 20,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Nome + site
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      font.name,
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      profile.baseUrl,
                      style: TextStyle(
                        color: subtitleColor,
                        fontSize: 11,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Badge de status
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withOpacity(0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isLoggedIn ? Icons.check_circle_outline : Icons.cancel_outlined,
                      color: statusColor,
                      size: 13,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      statusLabel,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ── Tokens armazenados (se logado) ─────────────────────────────
          if (isLoggedIn && sessionKeys.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: sessionKeys.map((k) {
                final val = session[k]!;
                final preview = val.length > 12
                    ? '${val.substring(0, 6)}...${val.substring(val.length - 4)}'
                    : val;
                return Chip(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                  backgroundColor: theme.selectedTheme.dividerColor.withOpacity(0.4),
                  label: Text(
                    '$k: $preview',
                    style: TextStyle(
                      fontSize: 11,
                      color: subtitleColor,
                      fontFamily: 'monospace',
                    ),
                  ),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                );
              }).toList(),
            ),
          ],

          // ── Ações ──────────────────────────────────────────────────────
          const SizedBox(height: 12),
          Row(
            children: [
              if (!isLoggedIn)
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onLogin,
                    icon: const Icon(Icons.login, size: 16),
                    label: const Text('Complete Login'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.selectedTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                )
              else ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onLogin,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Renew Session'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: textColor,
                      side: BorderSide(color: theme.selectedTheme.dividerColor),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: onLogout,
                  icon: const Icon(Icons.logout, size: 16, color: Colors.red),
                  label: const Text('Logout', style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.red.withOpacity(0.5)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
