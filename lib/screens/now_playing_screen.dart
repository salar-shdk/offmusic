import 'package:flutter/material.dart' hide RepeatMode;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:palette_generator/palette_generator.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../providers/library_provider.dart';
import '../services/audio_service.dart' show RepeatMode;
import '../theme/app_theme.dart';
import '../widgets/lyrics_view.dart';

/// Opens the Now Playing screen with a slide-up transition.
void openNowPlaying(BuildContext context) {
  Navigator.push(
    context,
    PageRouteBuilder(
      pageBuilder: (_, __, ___) => const NowPlayingScreen(),
      transitionsBuilder: (_, anim, __, child) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
      transitionDuration: const Duration(milliseconds: 350),
    ),
  );
}

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen>
    with SingleTickerProviderStateMixin {
  Color _dominantColor = const Color(0xFF1E1E1E);
  String? _lastThumbnailUrl;
  late AnimationController _artworkController;
  bool _isDragging = false;
  double _dragValue = 0;

  @override
  void initState() {
    super.initState();
    _artworkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _artworkController.dispose();
    super.dispose();
  }

  Future<void> _updateColor(String? url) async {
    if (url == null || url == _lastThumbnailUrl || url.isEmpty) return;
    _lastThumbnailUrl = url;
    try {
      final gen = await PaletteGenerator.fromImageProvider(
        CachedNetworkImageProvider(url),
        maximumColorCount: 8,
      );
      final color = gen.vibrantColor?.color ??
          gen.dominantColor?.color ??
          const Color(0xFF1E1E1E);
      if (mounted) setState(() => _dominantColor = color);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final library = context.watch<LibraryProvider>();
    final song = player.currentSong;

    if (song != null) _updateColor(song.thumbnailUrl);

    final showLyrics = player.showLyrics;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: AppTheme.playerGradient(_dominantColor),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _TopBar(
                onLyricsToggle: player.toggleShowLyrics,
                showLyrics: showLyrics,
                song: song,
              ),
              if (player.error != null)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    player.error!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              Expanded(
                child: showLyrics
                    ? const LyricsView()
                    : _ArtworkSection(
                        song: song,
                        isPlaying: player.isPlaying,
                        controller: _artworkController,
                      ),
              ),
              if (!showLyrics) ...[
                _SongInfo(
                  song: song,
                  isLiked: song != null && library.isSongLiked(song.id),
                  onLike: song != null
                      ? () => library.toggleSongLike(song)
                      : null,
                ),
                const SizedBox(height: 8),
              ],
              _ProgressBar(
                position: player.position,
                duration: player.duration,
                isDragging: _isDragging,
                dragValue: _dragValue,
                onChanged: (v) => setState(() {
                  _isDragging = true;
                  _dragValue = v;
                }),
                onChangeEnd: (v) {
                  setState(() => _isDragging = false);
                  final ms =
                      (v * player.duration.inMilliseconds).round();
                  player.seek(Duration(milliseconds: ms));
                },
              ),
              _Controls(player: player),
              const SizedBox(height: 8),
              _QueueButton(player: player),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final VoidCallback onLyricsToggle;
  final bool showLyrics;
  final Song? song;

  const _TopBar({
    required this.onLyricsToggle,
    required this.showLyrics,
    required this.song,
  });

  void _showAddToPlaylist(BuildContext context) {
    final library = context.read<LibraryProvider>();
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Add to playlist',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            if (library.playlists.isEmpty)
              const ListTile(title: Text('No playlists — create one in Library'))
            else
              ...library.playlists.map((pl) => ListTile(
                    leading: const Icon(Icons.playlist_play_rounded),
                    title: Text(pl.name),
                    onTap: () {
                      if (song != null) library.addSongToPlaylist(pl.id, song!);
                      Navigator.pop(ctx);
                    },
                  )),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
            onPressed: () => Navigator.pop(context),
            color: Colors.white,
          ),
          const Expanded(
            child: Text(
              'Now Playing',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (song != null)
            IconButton(
              icon: const Icon(Icons.playlist_add_rounded, size: 22),
              onPressed: () => _showAddToPlaylist(context),
              color: Colors.white54,
            ),
          IconButton(
            icon: Icon(
              showLyrics ? Icons.music_note_rounded : Icons.lyrics_rounded,
              size: 22,
            ),
            onPressed: onLyricsToggle,
            color: showLyrics ? Colors.white : Colors.white54,
          ),
        ],
      ),
    );
  }
}

class _ArtworkSection extends StatelessWidget {
  final Song? song;
  final bool isPlaying;
  final AnimationController controller;

  const _ArtworkSection({
    required this.song,
    required this.isPlaying,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: AnimatedScale(
        scale: isPlaying ? 1.0 : 0.85,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutBack,
        child: AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: song?.thumbnailUrl.isNotEmpty == true
                ? CachedNetworkImage(
                    imageUrl: song!.thumbnailUrl,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _placeholder(),
                  )
                : _placeholder(),
          ),
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: Colors.white10,
        child: const Icon(Icons.music_note_rounded,
            size: 64, color: Colors.white24),
      );
}

class _SongInfo extends StatelessWidget {
  final Song? song;
  final bool isLiked;
  final VoidCallback? onLike;

  const _SongInfo({required this.song, required this.isLiked, this.onLike});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song?.title ?? 'Nothing playing',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  song?.artist ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 15),
                ),
              ],
            ),
          ),
          if (onLike != null)
            GestureDetector(
              onTap: onLike,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  key: ValueKey(isLiked),
                  color: isLiked ? theme.colorScheme.primary : Colors.white54,
                  size: 28,
                ),
              ),
            ),
          if (song != null) ...[
            const SizedBox(width: 12),
            _NowPlayingDownloadButton(song: song!),
          ],
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final Duration position;
  final Duration duration;
  final bool isDragging;
  final double dragValue;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _ProgressBar({
    required this.position,
    required this.duration,
    required this.isDragging,
    required this.dragValue,
    required this.onChanged,
    required this.onChangeEnd,
  });

  String _format(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final total = duration.inMilliseconds;
    final current = position.inMilliseconds;
    final progress =
        total > 0 ? (isDragging ? dragValue : current / total) : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: progress.clamp(0.0, 1.0),
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _format(isDragging
                      ? Duration(
                          milliseconds: (dragValue * total).round())
                      : position),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                Text(
                  _format(duration),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  final PlayerProvider player;

  const _Controls({required this.player});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repeatMode = player.repeatMode;
    final shuffle = player.shuffle;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _ControlBtn(
            icon: shuffle ? Icons.shuffle_on_rounded : Icons.shuffle_rounded,
            color: shuffle ? theme.colorScheme.primary : Colors.white54,
            onTap: player.toggleShuffle,
            size: 22,
          ),
          _ControlBtn(
            icon: Icons.skip_previous_rounded,
            onTap: player.skipPrevious,
            size: 36,
          ),
          _PlayPauseButton(player: player),
          _ControlBtn(
            icon: Icons.skip_next_rounded,
            onTap: player.skipNext,
            size: 36,
          ),
          _ControlBtn(
            icon: repeatMode == RepeatMode.one
                ? Icons.repeat_one_rounded
                : Icons.repeat_rounded,
            color: repeatMode != RepeatMode.none
                ? theme.colorScheme.primary
                : Colors.white54,
            onTap: player.cycleRepeat,
            size: 22,
          ),
        ],
      ),
    );
  }
}

class _ControlBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color color;
  final double size;

  const _ControlBtn({
    required this.icon,
    this.onTap,
    this.color = Colors.white,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, color: color, size: size),
      ),
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  final PlayerProvider player;

  const _PlayPauseButton({required this.player});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: player.togglePlay,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: player.isLoading
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: theme.colorScheme.primary,
                ),
              )
            : Icon(
                player.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                size: 36,
                color: Colors.black,
              ),
      ),
    );
  }
}

class _QueueButton extends StatelessWidget {
  final PlayerProvider player;

  const _QueueButton({required this.player});

  void _openQueue(BuildContext context) {
    final queue = player.queue;
    final currentIdx = player.playerState.queueIndex;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (_, scrollController) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Queue',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${queue.length} songs',
                    style: const TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.only(bottom: 20),
                itemCount: queue.length,
                itemBuilder: (context, i) {
                  final song = queue[i];
                  final isCurrent = i == currentIdx;
                  return ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Stack(
                        children: [
                          CachedNetworkImage(
                            imageUrl: song.thumbnailUrl,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(
                              width: 44,
                              height: 44,
                              color: Colors.white10,
                              child: const Icon(Icons.music_note_rounded,
                                  size: 20, color: Colors.white24),
                            ),
                          ),
                          if (isCurrent)
                            Container(
                              width: 44,
                              height: 44,
                              color: Colors.black54,
                              child: const Icon(Icons.bar_chart_rounded,
                                  size: 20, color: Colors.white),
                            ),
                        ],
                      ),
                    ),
                    title: Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isCurrent
                            ? Theme.of(context).colorScheme.primary
                            : Colors.white,
                        fontWeight: isCurrent
                            ? FontWeight.w600
                            : FontWeight.normal,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12),
                    ),
                    onTap: () {
                      player.playSong(song, queue: queue, index: i);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (player.queue.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Align(
        alignment: Alignment.centerLeft,
        child: GestureDetector(
          onTap: () => _openQueue(context),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.queue_music_rounded,
                    size: 20, color: Colors.white54),
                const SizedBox(width: 6),
                Text(
                  'Queue · ${player.queue.length}',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NowPlayingDownloadButton extends StatelessWidget {
  final Song song;
  const _NowPlayingDownloadButton({required this.song});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final theme = Theme.of(context);
    final isCaching = player.isCaching(song.id);

    if (isCaching) {
      return SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: theme.colorScheme.primary,
        ),
      );
    }

    if (song.isAvailableOffline) {
      return Icon(Icons.download_done_rounded,
          size: 22, color: theme.colorScheme.primary);
    }

    return GestureDetector(
      onTap: () => context.read<PlayerProvider>().cacheSong(song),
      child: const Icon(Icons.download_rounded, size: 22, color: Colors.white54),
    );
  }
}
