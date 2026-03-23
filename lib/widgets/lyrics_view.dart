import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/player_provider.dart';

class LyricsView extends StatefulWidget {
  const LyricsView({super.key});

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  final _scrollController = ScrollController();
  int _lastIndex = -1;
  GlobalKey? _currentLineKey;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToCurrentLine(int index) {
    if (index == _lastIndex) return;
    _lastIndex = index;
    // Use post-frame callback so the key's context is mounted and sized.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _currentLineKey?.currentContext;
      if (ctx == null || !_scrollController.hasClients) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5, // center the active line vertically
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final lyrics = player.lyrics;
    final theme = Theme.of(context);

    if (player.lyricsLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (lyrics == null || lyrics.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lyrics_outlined,
                size: 64, color: Colors.white.withOpacity(0.2)),
            const SizedBox(height: 16),
            Text(
              'No lyrics available',
              style: theme.textTheme.titleMedium?.copyWith(
                color: Colors.white38,
              ),
            ),
          ],
        ),
      );
    }

    if (!lyrics.isSynced) {
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Text(
          lyrics.plainText ?? '',
          style: theme.textTheme.bodyLarge?.copyWith(
            height: 1.8,
            color: Colors.white70,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

    final currentIndex = lyrics.currentLineIndex(player.position);
    _scrollToCurrentLine(currentIndex);

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
      itemCount: lyrics.lines.length,
      itemBuilder: (context, i) {
        final line = lyrics.lines[i];
        final isCurrent = i == currentIndex;
        final isPast = i < currentIndex;
        if (isCurrent) _currentLineKey = GlobalKey();
        return GestureDetector(
          key: isCurrent ? _currentLineKey : null,
          onTap: () => player.seek(line.timestamp),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              line.text,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontSize: isCurrent ? 20 : 16,
                fontWeight:
                    isCurrent ? FontWeight.bold : FontWeight.w400,
                color: isCurrent
                    ? Colors.white
                    : isPast
                        ? Colors.white30
                        : Colors.white54,
                height: 1.4,
              ),
            ),
          ),
        );
      },
    );
  }
}
