import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../models/album.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../providers/library_provider.dart';
import '../services/youtube_service.dart';
import '../widgets/song_tile.dart';

class AlbumScreen extends StatefulWidget {
  final Album album;

  const AlbumScreen({super.key, required this.album});

  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> {
  List<Song> _songs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSongs();
  }

  Future<void> _loadSongs() async {
    final yt = context.read<YouTubeService>();
    final songs = await yt.getPlaylistSongs(widget.album.id);
    if (mounted) setState(() {
      _songs = songs;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final album = widget.album;
    final isLiked = library.isAlbumLiked(album.id);
    final theme = Theme.of(context);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                album.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: album.thumbnailUrl,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      color: Colors.white10,
                      child: const Icon(Icons.album_rounded,
                          size: 80, color: Colors.white24),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.8),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(album.artist,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.primary,
                          )),
                      if (album.year > 0)
                        Text('${album.year}',
                            style: theme.textTheme.bodyMedium),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      isLiked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                      color: isLiked ? theme.colorScheme.primary : Colors.white54,
                    ),
                    onPressed: () => library.toggleAlbumLike(album),
                  ),
                  if (_songs.isNotEmpty)
                    FilledButton.icon(
                      onPressed: () => context
                          .read<PlayerProvider>()
                          .playSong(_songs.first, queue: _songs, index: 0),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Play all'),
                    ),
                ],
              ),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_songs.isEmpty)
            const SliverFillRemaining(
              child: Center(child: Text('No songs found')),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => SongTile(
                  song: _songs[i],
                  queue: _songs,
                  index: i,
                ),
                childCount: _songs.length,
              ),
            ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
        ],
      ),
    );
  }
}
