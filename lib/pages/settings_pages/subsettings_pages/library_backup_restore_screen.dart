import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/classes/app_state.dart';
import 'package:star_scrapper_app/classes/services/backup_service.dart';
import 'package:star_scrapper_app/application/library/anime_library_controller.dart';
import 'package:star_scrapper_app/application/trackers/tracker_controller.dart';
import 'package:star_scrapper_app/classes/static/fonts_provider.dart';
import 'package:star_scrapper_app/application/notifications/app_notification_service.dart';
import 'package:star_scrapper_app/l10n/l10n.dart';

class LibraryBackupRestoreScreen extends StatefulWidget {
  const LibraryBackupRestoreScreen({super.key});

  @override
  State<LibraryBackupRestoreScreen> createState() =>
      _LibraryBackupRestoreScreenState();
}

class _LibraryBackupRestoreScreenState
    extends State<LibraryBackupRestoreScreen> {
  final BackupService _backupService = BackupService();
  final AppNotificationService _notifications = AppNotificationService.instance;
  List<FileSystemEntity> _backupFiles = [];
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _reloadBackupList();
  }

  Future<void> _reloadBackupList() async {
    final files = await _backupService.listBackups();
    if (!mounted) return;
    setState(() => _backupFiles = files);
  }

  Future<void> _createBackup() async {
    final password = await _requestBackupPassword(confirm: true);
    if (password == null || !mounted) return;
    setState(() => _isBusy = true);
    try {
      final path = await _backupService.createBackup(password: password);
      await _notifications.notifyBackupCreated(_fileName(path));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.backupCreatedIn(path))),
      );
      await _reloadBackupList();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.backupCreateFailed('$e'))),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _restoreBackup(String filePath) async {
    final l10n = context.l10n;
    final allow = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.restoreBackupTitle),
        content: Text(l10n.restoreBackupConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.restoreAction),
          ),
        ],
      ),
    );
    if (allow != true || !mounted) return;

    String? password;
    if (await _backupService.backupRequiresPassword(filePath)) {
      if (!mounted) return;
      password = await _requestBackupPassword();
      if (password == null || !mounted) return;
    }
    if (!mounted) return;

    final tabsState = Provider.of<TabsState>(context, listen: false);
    final animeTabsState = Provider.of<AnimeTabsState>(context, listen: false);
    final fontProvider = Provider.of<FontProvider>(context, listen: false);
    final animeLibrary =
        Provider.of<AnimeLibraryController>(context, listen: false);
    final trackerController =
        Provider.of<TrackerController>(context, listen: false);

    setState(() => _isBusy = true);
    try {
      await _backupService.restoreBackup(filePath, password: password);
      await Future.wait([
        tabsState.reloadLibraryStructure(),
        animeTabsState.reloadLibraryStructure(),
      ]);
      await Future.wait([
        fontProvider.refreshFromStorage(),
        animeLibrary.initialize(),
        trackerController.initialize(),
      ]);
      await _notifications.notifyBackupRestored(_fileName(filePath));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.backupRestoredSuccess)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.backupRestoreFailed('$e'))),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  String _fileName(String filePath) =>
      filePath.split(Platform.pathSeparator).last;

  Future<String?> _requestBackupPassword({bool confirm = false}) async {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BackupPasswordDialog(confirm: confirm),
    );
  }

  Future<void> _deleteBackup(String filePath) async {
    await _backupService.deleteBackup(filePath);
    await _reloadBackupList();
  }

  Future<void> _downloadBackup(String filePath) async {
    setState(() => _isBusy = true);
    try {
      final outputPath = await _backupService.exportBackup(filePath);
      if (!mounted) return;
      if (outputPath == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.backupSavedSuccess)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.backupDownloadFailed('$e'))),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _loadBackupFromDevice() async {
    try {
      final selectedPath = await _backupService.selectBackupForImport();
      if (selectedPath == null || selectedPath.isEmpty) return;
      if (!mounted) return;
      await _restoreBackup(selectedPath);
      await _reloadBackupList();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.backupLoadFailed('$e'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Provider.of<ThemeProvider>(context);
    return Scaffold(
      backgroundColor: theme.selectedTheme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.selectedTheme.appBarTheme.backgroundColor,
        title: Text(
          l10n.backupAndRestoreTitle,
          style: TextStyle(
            color: theme.selectedTheme.textTheme.titleLarge?.color,
            fontSize: MediaQuery.of(context).size.width >= 600 ? 24 : 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Card(
              child: ListTile(
                leading: const Icon(Icons.lock_rounded),
                title: Text(l10n.encryptedCompleteBackupTitle),
                subtitle: Text(l10n.encryptedCompleteBackupDesc),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isBusy ? null : _createBackup,
                    icon: const Icon(Icons.backup_rounded),
                    label: Text(l10n.createBackupButton),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isBusy ? null : _loadBackupFromDevice,
                    icon: const Icon(Icons.upload_file_rounded),
                    label: Text(l10n.loadBackupButton),
                  ),
                ),
              ],
            ),
          ),
          if (_isBusy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _backupFiles.isEmpty
                ? Center(child: Text(l10n.noBackupsFound))
                : ListView.builder(
                    itemCount: _backupFiles.length,
                    itemBuilder: (context, index) {
                      final file = _backupFiles[index] as File;
                      final name = file.path.split(Platform.pathSeparator).last;
                      final modified = file.statSync().modified;
                      return ListTile(
                        title: Text(name),
                        subtitle: Text(modified.toString()),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: l10n.downloadTooltip,
                              icon: const Icon(Icons.download_rounded),
                              onPressed: _isBusy
                                  ? null
                                  : () => _downloadBackup(file.path),
                            ),
                            IconButton(
                              tooltip: l10n.restoreTooltip,
                              icon: const Icon(Icons.restore_rounded),
                              onPressed: _isBusy
                                  ? null
                                  : () => _restoreBackup(file.path),
                            ),
                            IconButton(
                              tooltip: l10n.deleteTooltip,
                              icon: const Icon(Icons.delete_outline),
                              onPressed: _isBusy
                                  ? null
                                  : () => _deleteBackup(file.path),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _BackupPasswordDialog extends StatefulWidget {
  const _BackupPasswordDialog({required this.confirm});

  final bool confirm;

  @override
  State<_BackupPasswordDialog> createState() => _BackupPasswordDialogState();
}

class _BackupPasswordDialogState extends State<_BackupPasswordDialog> {
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _obscurePassword = true;
  String? _validationMessage;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  void _submit() {
    final password = _passwordController.text;
    final message = password.length < 8
        ? 'Use at least 8 characters.'
        : widget.confirm && password != _confirmationController.text
            ? 'The passwords do not match.'
            : null;
    if (message != null) {
      setState(() => _validationMessage = message);
      return;
    }
    Navigator.of(context).pop(password);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
        title: Text(
          widget.confirm ? l10n.protectBackupTitle : l10n.unlockBackupTitle,
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.confirm ? l10n.protectBackupDesc : l10n.unlockBackupDesc,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                autofocus: true,
                obscureText: _obscurePassword,
                onSubmitted: (_) {
                  if (!widget.confirm) _submit();
                },
                decoration: InputDecoration(
                  labelText: l10n.backupPasswordLabel,
                  errorText: _validationMessage,
                  suffixIcon: IconButton(
                    onPressed: () => setState(
                      () => _obscurePassword = !_obscurePassword,
                    ),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                    ),
                  ),
                ),
              ),
              if (widget.confirm) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _confirmationController,
                  obscureText: _obscurePassword,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: l10n.confirmPasswordLabel,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: _submit,
            child: Text(
              widget.confirm ? l10n.createBackupAction : l10n.unlockAction,
            ),
          ),
        ],
      );
  }
}
