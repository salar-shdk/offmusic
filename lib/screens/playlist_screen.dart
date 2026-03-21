import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../widgets/song_tile.dart';

class PlaylistScreen extends StatelessWidget {
  final String playlistId;

  const PlaylistScreen({super.key, required this.playlistId});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final playlist = library.playlists.firstWhere(
      (p) => p.id == playlistId,
      orElse: () => throw StateError('Playlist not found'),
    );
    final songs = library.getPlaylistSongs(playlistId);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(playlist.name),
        actions: [
          if (songs.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.shuffle_rounded),
              tooltip: 'Shuffle',
              onPressed: () {
                final shuffled = List<Song>.from(songs)..shuffle();
                context
                    .read<PlayerProvider>()
                    .playSong(shuffled.first, queue: shuffled, index: 0, playlistMode: true);
              },
            ),
            IconButton(
              icon: const Icon(Icons.play_arrow_rounded),
              tooltip: 'Play',
              onPressed: () => context
                  .read<PlayerProvider>()
                  .playSong(songs.first, queue: songs, index: 0, playlistMode: true),
            ),
          ],
        ],
      ),
      body: songs.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.queue_music_rounded,
                      size: 64, color: Colors.white.withOpacity(0.1)),
                  const SizedBox(height: 16),
                  Text(
                    'This playlist is empty',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Search for music and add it here',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 80),
              itemCount: songs.length,
              itemBuilder: (context, i) => Dismissible(
                key: Key(songs[i].id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 16),
                  color: Colors.red.withOpacity(0.2),
                  child: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                ),
                onDismissed: (_) =>
                    library.removeSongFromPlaylist(playlistId, songs[i].id),
                child: SongTile(
                  song: songs[i],
                  queue: songs,
                  index: i,
                  playlistMode: true,
                ),
              ),
            ),
    );
  }
}
