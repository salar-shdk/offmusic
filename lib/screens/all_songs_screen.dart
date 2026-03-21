import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../providers/library_provider.dart';
import '../widgets/song_tile.dart';

/// Full-list screen for either liked songs or downloaded songs.
class AllSongsScreen extends StatelessWidget {
  final String title;
  final bool isDownloads;

  const AllSongsScreen({
    super.key,
    required this.title,
    required this.isDownloads,
  });

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final songs = isDownloads ? library.cachedSongs : library.likedSongs;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: songs.isEmpty
          ? Center(
              child: Text(
                isDownloads ? 'No downloaded songs' : 'No liked songs',
                style: const TextStyle(color: Colors.white38),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 100),
              itemCount: songs.length,
              itemBuilder: (context, i) {
                final song = songs[i];
                if (isDownloads) {
                  return _DownloadedSongTile(
                    song: song,
                    queue: songs,
                    index: i,
                  );
                }
                return SongTile(song: song, queue: songs, index: i);
              },
            ),
    );
  }
}

class _DownloadedSongTile extends StatelessWidget {
  final Song song;
  final List<Song> queue;
  final int index;

  const _DownloadedSongTile({
    required this.song,
    required this.queue,
    required this.index,
  });

  Future<void> _confirmRemove(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove download?'),
        content: Text(
          '"${song.title}" will be removed from your downloads. '
          'You can still stream it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm == true && context.mounted) {
      context.read<LibraryProvider>().removeSongFromCache(song.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SongTile(
      song: song,
      queue: queue,
      index: index,
      onRemoveFromCache: () => _confirmRemove(context),
    );
  }
}
