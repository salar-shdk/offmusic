import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import '../providers/home_provider.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../widgets/section_header.dart';
import 'category_screen.dart';
import 'now_playing_screen.dart';
import 'playlist_screen.dart';
import 'search_screen.dart';

// ── Mood / genre categories ───────────────────────────────────────────────────

class _Mood {
  final String title;
  final String query;
  final Color color;
  final IconData icon;
  const _Mood(this.title, this.query, this.color, this.icon);
}

const _kMoods = [
  _Mood('Pop', 'top pop hits', Color(0xFFE91E63), Icons.star_rounded),
  _Mood('Hip-Hop', 'hip hop rap hits', Color(0xFF9C27B0), Icons.mic_rounded),
  _Mood('R&B', 'r&b soul music', Color(0xFF3F51B5), Icons.favorite_rounded),
  _Mood('Rock', 'rock music hits', Color(0xFFE53935), Icons.electric_bolt_rounded),
  _Mood('Electronic', 'electronic edm dance', Color(0xFF00BCD4), Icons.graphic_eq_rounded),
  _Mood('Chill', 'chill lofi relaxing music', Color(0xFF4CAF50), Icons.spa_rounded),
  _Mood('Jazz', 'jazz music classics', Color(0xFFFF9800), Icons.piano_rounded),
  _Mood('K-Pop', 'kpop hits', Color(0xFFFF4081), Icons.auto_awesome_rounded),
  _Mood('Latin', 'latin reggaeton hits', Color(0xFFFF6F00), Icons.celebration_rounded),
  _Mood('Classical', 'classical orchestra music', Color(0xFF795548), Icons.music_note_rounded),
];

// ── Screen ────────────────────────────────────────────────────────────────────

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final home = context.watch<HomeProvider>();
    final library = context.watch<LibraryProvider>();
    final player = context.read<PlayerProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: home.refresh,
        child: CustomScrollView(
          slivers: [
            // ── App bar ──────────────────────────────────────────────────────
            SliverAppBar(
              floating: true,
              title: RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: 'off',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                    TextSpan(
                      text: 'music',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.search_rounded),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SearchScreen()),
                  ),
                ),
              ],
            ),

            // ── Section 1: Quick Picks ───────────────────────────────────────
            const SliverToBoxAdapter(
              child: SectionHeader(title: 'Quick Picks'),
            ),
            if (home.recommendedLoading)
              const SliverToBoxAdapter(
                child: SizedBox(
                  height: 200,
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (home.recommendedSongs.isEmpty)
              const SliverToBoxAdapter(
                child: SizedBox(
                  height: 80,
                  child: Center(
                    child: Text(
                      'Play some music to get recommendations',
                      style: TextStyle(color: Colors.white38),
                    ),
                  ),
                ),
              )
            else
              SliverToBoxAdapter(
                child: _QuickPicksGrid(songs: home.recommendedSongs),
              ),

            // ── Section 2: Your Playlists ────────────────────────────────────
            if (library.playlists.isNotEmpty) ...[
              const SliverToBoxAdapter(
                child: SectionHeader(title: 'Your Playlists'),
              ),
              SliverToBoxAdapter(
                child: _PlaylistsRow(
                  playlists: library.playlists,
                  getPlaylistSongs: library.getPlaylistSongs,
                  onPlay: (songs) {
                    player.playSong(songs.first, queue: songs, index: 0, playlistMode: true);
                    openNowPlaying(context);
                  },
                  onShuffle: (songs) {
                    final shuffled = List<Song>.from(songs)..shuffle();
                    player.playSong(shuffled.first, queue: shuffled, index: 0, playlistMode: true);
                    openNowPlaying(context);
                  },
                ),
              ),
            ],

            // ── Section 3: Browse by Category ────────────────────────────────
            const SliverToBoxAdapter(
              child: SectionHeader(title: 'Browse by Category'),
            ),
            SliverToBoxAdapter(
              child: _MoodsRow(
                moods: _kMoods,
                onTap: (mood) => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CategoryScreen(
                      title: mood.title,
                      query: mood.query,
                    ),
                  ),
                ),
              ),
            ),

            const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
          ],
        ),
      ),
    );
  }
}

// ── Quick Picks — horizontal 2-row swipeable grid ────────────────────────────

class _QuickPicksGrid extends StatelessWidget {
  final List<Song> songs;
  const _QuickPicksGrid({required this.songs});

  @override
  Widget build(BuildContext context) {
    const tileW = 160.0;
    const tileH = 76.0;
    const gap = 8.0;
    // 2 rows + 1 inner gap + top/bottom padding
    const totalHeight = 2 * tileH + gap + gap * 2;

    // Group songs into columns of 2
    final columns = <List<Song>>[];
    for (var i = 0; i < songs.length; i += 2) {
      columns.add([
        songs[i],
        if (i + 1 < songs.length) songs[i + 1],
      ]);
    }

    return SizedBox(
      height: totalHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: gap),
        itemCount: columns.length,
        separatorBuilder: (_, __) => const SizedBox(width: gap),
        itemBuilder: (context, colIdx) {
          final col = columns[colIdx];
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _QuickPickTile(song: col[0], width: tileW, height: tileH),
              if (col.length > 1) ...[
                const SizedBox(height: gap),
                _QuickPickTile(song: col[1], width: tileW, height: tileH),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _QuickPickTile extends StatelessWidget {
  final Song song;
  final double width;
  final double height;
  const _QuickPickTile({
    required this.song,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // startRadio plays the song AND fills the queue with related songs.
        context.read<HomeProvider>().startRadio(song);
        openNowPlaying(context);
      },
      child: SizedBox(
        width: width,
        height: height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: song.thumbnailUrl,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  color: Colors.white10,
                  child: const Icon(Icons.music_note_rounded,
                      size: 20, color: Colors.white24),
                ),
              ),
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Colors.black87],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
              Positioned(
                left: 6,
                right: 6,
                bottom: 4,
                child: Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Playlists row ─────────────────────────────────────────────────────────────

class _PlaylistsRow extends StatelessWidget {
  final List<Playlist> playlists;
  final List<Song> Function(String) getPlaylistSongs;
  final void Function(List<Song>) onPlay;
  final void Function(List<Song>) onShuffle;

  const _PlaylistsRow({
    required this.playlists,
    required this.getPlaylistSongs,
    required this.onPlay,
    required this.onShuffle,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 196,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: playlists.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final pl = playlists[i];
          final songs = getPlaylistSongs(pl.id);
          return _PlaylistCard(
            playlist: pl,
            songs: songs,
            onPlay: songs.isEmpty ? null : () => onPlay(songs),
            onShuffle: songs.isEmpty ? null : () => onShuffle(songs),
          );
        },
      ),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  final Playlist playlist;
  final List<Song> songs;
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;

  const _PlaylistCard({
    required this.playlist,
    required this.songs,
    this.onPlay,
    this.onShuffle,
  });

  @override
  Widget build(BuildContext context) {
    const w = 140.0;
    final theme = Theme.of(context);
    final thumb = playlist.customThumbnailUrl ??
        (songs.isNotEmpty ? songs.first.thumbnailUrl : null);

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlaylistScreen(playlistId: playlist.id),
        ),
      ),
      child: SizedBox(
        width: w,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: thumb != null
                      ? CachedNetworkImage(
                          imageUrl: thumb,
                          width: w,
                          height: w,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => _thumbPlaceholder(w),
                        )
                      : _thumbPlaceholder(w),
                ),
                // Play / Shuffle buttons overlay
                if (onPlay != null)
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _OverlayIconButton(
                          icon: Icons.shuffle_rounded,
                          onTap: onShuffle!,
                        ),
                        const SizedBox(width: 4),
                        _OverlayIconButton(
                          icon: Icons.play_arrow_rounded,
                          onTap: onPlay!,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              playlist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
            Text(
              '${playlist.songCount} songs',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumbPlaceholder(double w) => Container(
        width: w,
        height: w,
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.queue_music_rounded,
            size: 48, color: Colors.white24),
      );
}

class _OverlayIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _OverlayIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(icon, size: 16, color: Colors.white),
      ),
    );
  }
}

// ── Moods row ─────────────────────────────────────────────────────────────────

class _MoodsRow extends StatelessWidget {
  final List<_Mood> moods;
  final void Function(_Mood) onTap;
  const _MoodsRow({required this.moods, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: moods.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) => _MoodCard(
          mood: moods[i],
          onTap: () => onTap(moods[i]),
        ),
      ),
    );
  }
}

class _MoodCard extends StatelessWidget {
  final _Mood mood;
  final VoidCallback onTap;
  const _MoodCard({required this.mood, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [mood.color, mood.color.withValues(alpha: 0.6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(mood.icon, color: Colors.white, size: 28),
            const SizedBox(height: 6),
            Text(
              mood.title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
