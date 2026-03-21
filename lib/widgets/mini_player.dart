import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../providers/player_provider.dart';
import '../screens/now_playing_screen.dart' show openNowPlaying;

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final song = player.currentSong;
    if (song == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => openNowPlaying(context),
      child: Container(
        height: 64,
        margin: const EdgeInsets.only(left: 8, right: 8, top: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: song.thumbnailUrl,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          width: 40,
                          height: 40,
                          color: Colors.white10,
                          child: const Icon(Icons.music_note_rounded,
                              size: 20, color: Colors.white24),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium,
                          ),
                          Text(
                            song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => context.read<PlayerProvider>().skipPrevious(),
                      icon: const Icon(Icons.skip_previous_rounded),
                      iconSize: 24,
                      color: Colors.white70,
                      padding: EdgeInsets.zero,
                    ),
                    _PlayPauseButton(
                      isPlaying: player.isPlaying,
                      isLoading: player.isLoading,
                    ),
                    IconButton(
                      onPressed: () => context.read<PlayerProvider>().skipNext(),
                      icon: const Icon(Icons.skip_next_rounded),
                      iconSize: 24,
                      color: Colors.white70,
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
            ),
            // Progress bar
            LinearProgressIndicator(
              value: player.progress,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
              minHeight: 2,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  final bool isPlaying;
  final bool isLoading;

  const _PlayPauseButton({required this.isPlaying, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: isLoading
          ? Padding(
              padding: const EdgeInsets.all(8),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.primary,
              ),
            )
          : IconButton(
              onPressed: () => context.read<PlayerProvider>().togglePlay(),
              icon: Icon(
                isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
              ),
              iconSize: 28,
              color: Colors.white,
              padding: EdgeInsets.zero,
            ),
    );
  }
}
