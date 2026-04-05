import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/classes/app_state.dart';
import 'package:star_scrapper_app/classes/services/backup_service.dart';
import 'package:star_scrapper_app/classes/static/fonts_provider.dart';

class LibraryBackupRestoreScreen extends StatefulWidget {
  const LibraryBackupRestoreScreen({super.key});

  @override
  State<LibraryBackupRestoreScreen> createState() =>
      _LibraryBackupRestoreScreenState();
}

class _LibraryBackupRestoreScreenState extends State<LibraryBackupRestoreScreen> {
  final BackupService _backupService = BackupService();
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
    setState(() => _isBusy = true);
    try {
      final path = await _backupService.createBackup();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup created in: $path')),
      );
      await _reloadBackupList();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create backup: $e')),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _restoreBackup(String filePath) async {
    final allow = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore Backup'),
        content: const Text(
          'This will overwrite the current app data. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (allow != true) return;

    setState(() => _isBusy = true);
    try {
      await _backupService.restoreBackup(filePath);
      final tabsState = Provider.of<TabsState>(context, listen: false);
      final fontProvider = Provider.of<FontProvider>(context, listen: false);
      await tabsState.reloadLibraryStructure();
      await fontProvider.refreshFromStorage();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup restored successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to restore backup: $e')),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _deleteBackup(String filePath) async {
    await _backupService.deleteBackup(filePath);
    await _reloadBackupList();
  }

  Future<void> _downloadBackup(String filePath) async {
    setState(() => _isBusy = true);
    try {
      final outputPath = await _backupService.copyBackupToDownloads(filePath);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup copiado para: $outputPath')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao baixar backup: $e')),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _loadBackupFromDevice() async {
    setState(() => _isBusy = true);
    try {
      final files = await _backupService.listImportableBackups();
      if (!mounted) return;
      setState(() => _isBusy = false);

      if (files.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No .starsbackup found in Downloads/Documents.'),
          ),
        );
        return;
      }

      final selectedPath = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Load Backup'),
          content: SizedBox(
            width: 560,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: files.length,
              itemBuilder: (context, index) {
                final file = files[index] as File;
                final name = file.path.split(Platform.pathSeparator).last;
                return ListTile(
                  title: Text(name),
                  subtitle: Text(file.path),
                  onTap: () => Navigator.of(context).pop(file.path),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );

      if (selectedPath == null || selectedPath.isEmpty) return;
      await _restoreBackup(selectedPath);
      await _reloadBackupList();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load backup: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    return Scaffold(
      backgroundColor: theme.selectedTheme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.selectedTheme.appBarTheme.backgroundColor,
        title: Text(
          'Backup & Restore',
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
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isBusy ? null : _createBackup,
                    icon: const Icon(Icons.backup_rounded),
                    label: const Text('Create Backup'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isBusy ? null : _loadBackupFromDevice,
                    icon: const Icon(Icons.upload_file_rounded),
                    label: const Text('Load Backup'),
                  ),
                ),
              ],
            ),
          ),
          if (_isBusy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _backupFiles.isEmpty
                ? const Center(child: Text('No backups found.'))
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
                              tooltip: 'Download',
                              icon: const Icon(Icons.download_rounded),
                              onPressed: _isBusy ? null : () => _downloadBackup(file.path),
                            ),
                            IconButton(
                              tooltip: 'Restore',
                              icon: const Icon(Icons.restore_rounded),
                              onPressed: _isBusy ? null : () => _restoreBackup(file.path),
                            ),
                            IconButton(
                              tooltip: 'Delete',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: _isBusy ? null : () => _deleteBackup(file.path),
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
