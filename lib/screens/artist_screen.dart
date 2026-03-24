import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../models/artist.dart';
import '../models/album.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../providers/library_provider.dart';
import '../services/youtube_service.dart';
import '../widgets/song_tile.dart';
import '../widgets/album_card.dart';
import 'album_screen.dart';

class ArtistScreen extends StatefulWidget {
  final Artist artist;

  const ArtistScreen({super.key, required this.artist});

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  List<Song>  _songs  = [];
  List<Album> _albums = [];
  bool _loading = true;

  // How many items to preview before "See more"
  static const _songPreview  = 5;
  static const _albumPreview = 4;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final yt     = context.read<YouTubeService>();
    final artist = widget.artist;

    var songs  = <Song>[];
    var albums = <Album>[];

    if (artist.id.isNotEmpty) {
      final page = await yt.getArtistPage(artist.id, artist.name);
      songs  = page.songs;
      albums = page.albums;
    }

    if (songs.isEmpty)  songs  = await yt.searchSongs(artist.name);
    if (albums.isEmpty) albums = await yt.searchAlbums(artist.name);

    if (mounted) {
      setState(() {
        _songs   = songs;
        _albums  = albums;
        _loading = false;
      });
    }
  }

  void _openAllSongs() => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _FullListScreen(
            title: 'Songs',
            songs: _songs,
          ),
        ),
      );

  void _openAllAlbums() => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _FullListScreen(
            title: 'Albums',
            albums: _albums,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final artist  = widget.artist;
    final isLiked = library.isArtistLiked(artist.id);
    final theme   = Theme.of(context);

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

          // ── Artist header ──────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: artist.thumbnailUrl,
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, err) => Container(
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
                              label: Text(isLiked ? 'Following' : 'Follow'),
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
                                  padding: EdgeInsets.zero,
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
          ),

          if (_loading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            // ── Albums section ─────────────────────────────────────────
            if (_albums.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _SectionHeader(
                  title: 'Albums',
                  showSeeMore: _albums.length > _albumPreview,
                  onSeeMore: _openAllAlbums,
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 190,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _albums.length.clamp(0, _albumPreview),
                    separatorBuilder: (context, i) =>
                        const SizedBox(width: 12),
                    itemBuilder: (context, i) {
                      final album = _albums[i];
                      return AlbumCard(
                        album: album,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AlbumScreen(album: album),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],

            // ── Songs section ──────────────────────────────────────────
            if (_songs.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _SectionHeader(
                  title: 'Songs',
                  showSeeMore: _songs.length >= _songPreview,
                  onSeeMore: _openAllSongs,
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => SongTile(
                    song: _songs[i],
                    queue: _songs,
                    index: i,
                  ),
                  childCount: _songs.length.clamp(0, _songPreview),
                ),
              ),
            ],

            if (_songs.isEmpty && _albums.isEmpty)
              const SliverFillRemaining(
                child: Center(child: Text('No content found')),
              ),
          ],

          const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
        ],
      ),
    );
  }
}

// ── Section header with optional "See more" ────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final bool showSeeMore;
  final VoidCallback onSeeMore;

  const _SectionHeader({
    required this.title,
    required this.showSeeMore,
    required this.onSeeMore,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          if (showSeeMore)
            TextButton(
              onPressed: onSeeMore,
              child: const Text('See more'),
            ),
        ],
      ),
    );
  }
}

// ── Full list screen (all songs or all albums) ─────────────────────────────

class _FullListScreen extends StatelessWidget {
  final String title;
  final List<Song>  songs;
  final List<Album> albums;

  const _FullListScreen({
    required this.title,
    this.songs  = const [],
    this.albums = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ),
      body: songs.isNotEmpty
          ? ListView.builder(
              padding: const EdgeInsets.only(bottom: 80),
              itemCount: songs.length,
              itemBuilder: (context, i) => SongTile(
                song: songs[i],
                queue: songs,
                index: i,
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 0.75,
              ),
              itemCount: albums.length,
              itemBuilder: (context, i) {
                final album = albums[i];
                return AlbumCard(
                  album: album,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AlbumScreen(album: album),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
