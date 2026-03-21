import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/library_provider.dart';
import '../widgets/song_tile.dart';
import '../widgets/section_header.dart';
import 'all_songs_screen.dart';
import 'playlist_screen.dart';
import 'album_screen.dart';
import 'artist_screen.dart';

const _kPreviewCount = 5;

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            title: Text('Library', style: theme.textTheme.headlineMedium),
            actions: [
              IconButton(
                icon: const Icon(Icons.add_rounded),
                onPressed: () => _showCreatePlaylistDialog(context, library),
              ),
            ],
          ),

          // Playlists section
          const SliverToBoxAdapter(
            child: SectionHeader(title: 'Playlists'),
          ),
          if (library.playlists.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: GestureDetector(
                  onTap: () => _showCreatePlaylistDialog(context, library),
                  child: Container(
                    height: 60,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_rounded,
                            color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text('Create a playlist',
                            style: TextStyle(color: theme.colorScheme.primary)),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final pl = library.playlists[i];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 4),
                    leading: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.playlist_play_rounded,
                          color: theme.colorScheme.primary),
                    ),
                    title: Text(pl.name,
                        style: theme.textTheme.titleMedium),
                    subtitle: Text(
                      '${pl.songCount} songs',
                      style: theme.textTheme.bodyMedium,
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) async {
                        if (value == 'delete') {
                          await library.deletePlaylist(pl.id);
                        } else if (value == 'rename') {
                          _showRenamePlaylistDialog(context, library, pl.id, pl.name);
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'rename', child: Text('Rename')),
                        const PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PlaylistScreen(playlistId: pl.id),
                      ),
                    ),
                  );
                },
                childCount: library.playlists.length,
              ),
            ),

          // Liked Songs (preview: up to 5)
          if (library.likedSongs.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: SectionHeader(
                title: 'Liked Songs',
                actionLabel: 'See all',
                onAction: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AllSongsScreen(
                      title: 'Liked Songs',
                      isDownloads: false,
                    ),
                  ),
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => SongTile(
                  song: library.likedSongs[i],
                  queue: library.likedSongs,
                  index: i,
                ),
                childCount: library.likedSongs.length.clamp(0, _kPreviewCount),
              ),
            ),
            if (library.likedSongs.length > _kPreviewCount)
              SliverToBoxAdapter(
                child: _SeeAllTile(
                  count: library.likedSongs.length,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AllSongsScreen(
                        title: 'Liked Songs',
                        isDownloads: false,
                      ),
                    ),
                  ),
                ),
              ),
          ],

          // Liked Albums
          if (library.likedAlbums.isNotEmpty) ...[
            const SliverToBoxAdapter(
              child: SectionHeader(title: 'Saved Albums'),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final album = library.likedAlbums[i];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 4),
                    leading: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.album_rounded, color: Colors.white38),
                    ),
                    title: Text(album.title, style: theme.textTheme.titleMedium),
                    subtitle: Text(album.artist, style: theme.textTheme.bodyMedium),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AlbumScreen(album: album),
                      ),
                    ),
                  );
                },
                childCount: library.likedAlbums.length,
              ),
            ),
          ],

          // Liked Artists
          if (library.likedArtists.isNotEmpty) ...[
            const SliverToBoxAdapter(
              child: SectionHeader(title: 'Following Artists'),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final artist = library.likedArtists[i];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 4),
                    leading: Container(
                      width: 50,
                      height: 50,
                      decoration: const BoxDecoration(
                        color: Colors.white10,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.person_rounded, color: Colors.white38),
                    ),
                    title: Text(artist.name, style: theme.textTheme.titleMedium),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ArtistScreen(artist: artist),
                      ),
                    ),
                  );
                },
                childCount: library.likedArtists.length,
              ),
            ),
          ],

          // Downloaded songs (preview: up to 5)
          if (library.cachedSongs.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: SectionHeader(
                title: 'Downloaded',
                actionLabel: library.cachedSongs.length > _kPreviewCount
                    ? 'See all'
                    : null,
                onAction: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AllSongsScreen(
                      title: 'Downloads',
                      isDownloads: true,
                    ),
                  ),
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => SongTile(
                  song: library.cachedSongs[i],
                  queue: library.cachedSongs,
                  index: i,
                ),
                childCount:
                    library.cachedSongs.length.clamp(0, _kPreviewCount),
              ),
            ),
            if (library.cachedSongs.length > _kPreviewCount)
              SliverToBoxAdapter(
                child: _SeeAllTile(
                  count: library.cachedSongs.length,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AllSongsScreen(
                        title: 'Downloads',
                        isDownloads: true,
                      ),
                    ),
                  ),
                ),
              ),
          ],

          const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
        ],
      ),
    );
  }

  void _showCreatePlaylistDialog(
      BuildContext context, LibraryProvider library) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Playlist name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (controller.text.trim().isNotEmpty) {
                await library.createPlaylist(controller.text.trim());
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showRenamePlaylistDialog(
      BuildContext context, LibraryProvider library, String id, String current) {
    final controller = TextEditingController(text: current);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (controller.text.trim().isNotEmpty) {
                await library.renamePlaylist(id, controller.text.trim());
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _SeeAllTile extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _SeeAllTile({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Text(
              'See all $count songs',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_forward_rounded,
                size: 14,
                color: Theme.of(context).colorScheme.primary),
          ],
        ),
      ),
    );
  }
}
