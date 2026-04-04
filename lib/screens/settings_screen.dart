import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/library_provider.dart';

const _kDayLabels = {
  null: 'Never',
  3: '3 days',
  7: '7 days',
  30: '1 month',
  365: '1 year',
};

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _cacheSize = '...';

  @override
  void initState() {
    super.initState();
    _loadCacheSize();
  }

  Future<void> _loadCacheSize() async {
    final size =
        await context.read<LibraryProvider>().getCacheSizeFormatted();
    if (mounted) setState(() => _cacheSize = size);
  }

  Future<void> _exportLibrary(BuildContext context) async {
    try {
      final file = await context.read<LibraryProvider>().exportLibrary();
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'offmusic library backup',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  Future<void> _importLibrary(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || result.files.isEmpty) return;
      final path = result.files.single.path;
      if (path == null) return;
      if (!mounted) return;
      await context.read<LibraryProvider>().importLibrary(path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Library imported successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings', style: theme.textTheme.headlineMedium),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 80),
        children: [
          const _SectionTitle('Offline & Cache'),
          ListTile(
            leading: const Icon(Icons.storage_rounded),
            title: const Text('Cache size'),
            trailing: Text(_cacheSize,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.primary,
                )),
          ),
          ListTile(
            leading: const Icon(Icons.delete_sweep_rounded),
            title: const Text('Clear audio cache'),
            subtitle: const Text('Removes all downloaded audio'),
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Clear cache?'),
                  content: const Text(
                      'This will remove all cached audio. Songs will need to be streamed again.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              );
              if (confirm == true && mounted) {
                final lib = context.read<LibraryProvider>();
                await lib.clearCache();
                _loadCacheSize();
              }
            },
          ),
          const Divider(),
          const _SectionTitle('Auto-cleanup'),
          _AutoDeleteTile(),
          const Divider(),
          const _SectionTitle('Backup'),
          ListTile(
            leading: const Icon(Icons.upload_rounded),
            title: const Text('Export library'),
            subtitle: const Text('Save liked songs, albums, artists & playlists'),
            onTap: () => _exportLibrary(context),
          ),
          ListTile(
            leading: const Icon(Icons.download_rounded),
            title: const Text('Import library'),
            subtitle: const Text('Merge from a backup file'),
            onTap: () => _importLibrary(context),
          ),
          const Divider(),
          const _SectionTitle('Android Auto'),
          _AutoPlayAutoTile(),
          const Divider(),
          const _SectionTitle('About'),
          const ListTile(
            leading: Icon(Icons.info_outline_rounded),
            title: Text('offmusic'),
            subtitle: Text('Version 1.2.2'),
          ),
          ListTile(
            leading: const Icon(Icons.code_rounded),
            title: const Text('Developed by'),
            subtitle: const Text('Amirsalar Darvishpour'),
            onTap: () => launchUrl(
              Uri.parse('https://github.com/salar-shdk'),
              mode: LaunchMode.externalApplication,
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.coffee_rounded),
            title: const Text('Buy me a coffee'),
            subtitle: const Text('Support the development of offmusic'),
            onTap: () => launchUrl(
              Uri.parse('https://buymeacoffee.com/salar_shdk'),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ],
      ),
    );
  }
}

class _AutoDeleteTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryProvider>();
    final current = lib.autoDeleteDays;
    return ListTile(
      leading: const Icon(Icons.auto_delete_rounded),
      title: const Text('Delete unplayed downloads after'),
      subtitle: const Text('Removes audio files for songs you haven\'t played'),
      trailing: DropdownButton<int?>(
        value: current,
        underline: const SizedBox.shrink(),
        onChanged: (days) => lib.setAutoDeleteDays(days),
        items: _kDayLabels.entries
            .map((e) => DropdownMenuItem<int?>(
                  value: e.key,
                  child: Text(e.value),
                ))
            .toList(),
      ),
    );
  }
}

class _AutoPlayAutoTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryProvider>();
    return SwitchListTile(
      secondary: const Icon(Icons.directions_car_rounded),
      title: const Text('Auto-play on connect'),
      subtitle: const Text(
          'Automatically resume playback when Android Auto connects'),
      value: lib.autoPlayOnAutoConnect,
      onChanged: (v) => lib.setAutoPlayOnAutoConnect(v),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
          fontSize: 12,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}
