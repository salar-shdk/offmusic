import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../models/artist.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../providers/library_provider.dart';
import '../services/youtube_service.dart';
import '../widgets/song_tile.dart';

class ArtistScreen extends StatefulWidget {
  final Artist artist;

  const ArtistScreen({super.key, required this.artist});

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  List<Song> _songs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSongs();
  }

  Future<void> _loadSongs() async {
    final yt = context.read<YouTubeService>();
    List<Song> songs = [];
    if (widget.artist.id.isNotEmpty) {
      songs = await yt.getArtistSongs(widget.artist.id);
    }
    if (songs.isEmpty) {
      songs = await yt.searchSongs(widget.artist.name);
    }
    if (mounted) setState(() {
      _songs = songs;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final artist = widget.artist;
    final isLiked = library.isArtistLiked(artist.id);
    final theme = Theme.of(context);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            title: Text(
              artist.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      ClipOval(
                        child: CachedNetworkImage(
                          imageUrl: artist.thumbnailUrl,
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                          errorWidget: (context, _, __) => Container(
                            width: 100,
                            height: 100,
                            color: Colors.white10,
                            child: const Icon(Icons.person_rounded,
                                size: 48, color: Colors.white24),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (artist.description != null &&
                                artist.description!.isNotEmpty)
                              Text(
                                artist.description!,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium,
                              ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () =>
                                      library.toggleArtistLike(artist),
                                  icon: Icon(
                                    isLiked
                                        ? Icons.person_remove_rounded
                                        : Icons.person_add_rounded,
                                    size: 18,
                                  ),
                                  label:
                                      Text(isLiked ? 'Following' : 'Follow'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: isLiked
                                        ? theme.colorScheme.primary
                                        : Colors.white70,
                                    side: BorderSide(
                                      color: isLiked
                                          ? theme.colorScheme.primary
                                          : Colors.white30,
                                    ),
                                  ),
                                ),
                                if (_songs.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  FilledButton(
                                    onPressed: () => context
                                        .read<PlayerProvider>()
                                        .playSong(_songs.first,
                                            queue: _songs, index: 0),
                                    style: FilledButton.styleFrom(
                                      minimumSize: const Size(40, 40),
                                      padding: const EdgeInsets.all(0),
                                      shape: const CircleBorder(),
                                    ),
                                    child: const Icon(Icons.play_arrow_rounded),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
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
