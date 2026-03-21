import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../providers/library_provider.dart';
import '../screens/now_playing_screen.dart';

class SongTile extends StatelessWidget {
  final Song song;
  final List<Song>? queue;
  final int? index;
  final VoidCallback? onMoreTap;
  final VoidCallback? onRemoveFromCache;
  final bool showArtwork;
  final bool playlistMode;

  const SongTile({
    super.key,
    required this.song,
    this.queue,
    this.index,
    this.onMoreTap,
    this.onRemoveFromCache,
    this.showArtwork = true,
    this.playlistMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final library = context.watch<LibraryProvider>();
    final isCurrentSong = player.currentSong?.id == song.id;
    final isLiked = library.isSongLiked(song.id);
    final theme = Theme.of(context);

    return InkWell(
      onTap: () {
        context.read<PlayerProvider>().playSong(
              song,
              queue: queue,
              index: index,
              playlistMode: playlistMode,
            );
        openNowPlaying(context);
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            if (showArtwork) ...[
              _Artwork(url: song.thumbnailUrl, isPlaying: isCurrentSong),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: isCurrentSong
                          ? theme.colorScheme.primary
                          : theme.textTheme.titleMedium?.color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      Text(
                        song.duration,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => library.toggleSongLike(song),
              child: Icon(
                isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                size: 20,
                color: isLiked ? theme.colorScheme.primary : Colors.white38,
              ),
            ),
            const SizedBox(width: 8),
            if (onRemoveFromCache != null)
              GestureDetector(
                onTap: onRemoveFromCache,
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: Colors.redAccent,
                  ),
                ),
              )
            else
              _DownloadButton(song: song),
            if (onMoreTap != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onMoreTap,
                child: const Icon(
                  Icons.more_vert_rounded,
                  size: 20,
                  color: Colors.white38,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DownloadButton extends StatelessWidget {
  final Song song;
  const _DownloadButton({required this.song});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final theme = Theme.of(context);
    final isCaching = player.isCaching(song.id);

    if (isCaching) {
      return SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: theme.colorScheme.primary,
        ),
      );
    }

    if (song.isAvailableOffline) {
      return Icon(Icons.download_done_rounded,
          size: 20, color: theme.colorScheme.primary);
    }

    return GestureDetector(
      onTap: () => context.read<PlayerProvider>().cacheSong(song),
      child: const Icon(Icons.download_rounded, size: 20, color: Colors.white38),
    );
  }
}

class _Artwork extends StatelessWidget {
  final String url;
  final bool isPlaying;

  const _Artwork({required this.url, required this.isPlaying});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: CachedNetworkImage(
            imageUrl: url,
            width: 50,
            height: 50,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => Container(
              width: 50,
              height: 50,
              color: Colors.white10,
              child: const Icon(Icons.music_note_rounded, size: 24, color: Colors.white24),
            ),
          ),
        ),
        if (isPlaying)
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Container(
              width: 50,
              height: 50,
              color: Colors.black45,
              child: Icon(
                Icons.bar_chart_rounded,
                size: 24,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
      ],
    );
  }
}
