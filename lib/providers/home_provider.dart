import 'package:flutter/foundation.dart';
import '../models/song.dart';
import '../services/audio_service.dart';
import '../services/database_service.dart';
import '../services/home_service.dart';

class HomeProvider extends ChangeNotifier {
  final HomeService _homeService;
  final DatabaseService _db;
  final AudioPlayerService _audioService;

  List<Song> _recommendedSongs = [];
  bool _recommendedLoading = false;
  bool _filling = false;
  // Only set after a SUCCESSFUL fill to allow retries on failure.
  String? _lastFilledSongId;

  HomeProvider(this._homeService, this._db, this._audioService) {
    _loadRecommended();
    _audioService.stateStream.listen(_onPlayerState);
  }

  List<Song> get recommendedSongs => _recommendedSongs;
  bool get recommendedLoading => _recommendedLoading;

  // ── Recommendations ───────────────────────────────────────────────────────

  Future<void> _loadRecommended() async {
    _recommendedLoading = true;
    notifyListeners();

    const fallbacks = ['dQw4w9WgXcQ', 'kXYiU_JCYtU', '09R8_2nJtjg'];
    final topIds = _db.getMostPlayedSongIds(limit: 3);
    final seeds = topIds.isNotEmpty ? topIds : fallbacks;

    // Fetch related songs for every seed in parallel.
    final results = await Future.wait(
      seeds.map((id) => _homeService.getRelatedSongs(id)),
    );

    final seen = <String>{};
    final merged = <Song>[];
    for (final list in results) {
      for (final song in list) {
        if (seen.add(song.id)) merged.add(song);
      }
    }

    // Supplement with popular search results if we got fewer than 20 songs.
    if (merged.length < 20) {
      try {
        final popular =
            await _homeService.getCategorySongs('top hits popular music 2024');
        for (final song in popular.songs) {
          if (seen.add(song.id)) merged.add(song);
        }
      } catch (_) {}
    }

    _recommendedSongs = merged;
    _recommendedLoading = false;
    notifyListeners();
  }

  // ── Quick Picks: explicit radio start ─────────────────────────────────────

  /// Plays [song] immediately and fills the queue with related songs.
  /// Fetches related songs concurrently with playback so the queue is ready ASAP.
  Future<void> startRadio(Song song) async {
    // Reserve this song ID upfront so _onPlayerState doesn't race us.
    _lastFilledSongId = song.id;

    // Start fetching related songs concurrently with playback init.
    final relatedFuture = _fetchRelated(song);
    await _audioService.playSong(song, playlistMode: false);

    final related = await relatedFuture;
    if (related.isEmpty) {
      _lastFilledSongId = null; // allow retry via _onPlayerState
      return;
    }

    final current = _audioService.state.currentSong;
    if (current?.id != song.id) return; // user switched song

    _audioService.updateQueue([song, ...related.where((s) => s.id != song.id)]);
    debugPrint('[Home] startRadio: queue filled with ${related.length} songs');
  }

  // ── Auto-fill for songs played from search / library ─────────────────────

  void _onPlayerState(PlayerState state) {
    if (state.playlistMode) return;
    if (state.currentSong == null) return;

    final songId = state.currentSong!.id;
    final queueLen = state.queue.length;
    final idx = state.queueIndex;

    // Fill when queue has only 1 song and we haven't already filled for it.
    if (queueLen <= 1 && songId != _lastFilledSongId && !_filling) {
      _doFill(state.currentSong!);
      return;
    }

    // Auto-extend when within 2 songs of the end.
    if (!_filling && queueLen > 1 && idx >= queueLen - 2) {
      _extendQueue(state.currentSong!);
    }
  }

  Future<void> _doFill(Song seed) async {
    if (_filling) return;
    _filling = true;
    try {
      final songs = await _fetchRelated(seed);
      if (songs.isEmpty) return; // don't mark as filled — allow retry later

      final current = _audioService.state.currentSong;
      if (current == null || current.id != seed.id) return; // song changed
      if (_audioService.state.playlistMode) return;

      final newQueue = [current, ...songs.where((s) => s.id != current.id)];
      _audioService.updateQueue(newQueue);
      _lastFilledSongId = seed.id; // mark ONLY on success
      debugPrint('[Home] filled queue: ${newQueue.length} songs for ${seed.id}');
    } catch (e) {
      debugPrint('[Home] fill error: $e');
    } finally {
      _filling = false;
    }
  }

  Future<void> _extendQueue(Song seed) async {
    if (_filling) return;
    _filling = true;
    try {
      final songs = await _fetchRelated(seed);
      if (songs.isEmpty) return;
      if (_audioService.state.playlistMode) return;

      final existing = _audioService.state.queue;
      final existingIds = existing.map((s) => s.id).toSet();
      final toAdd =
          songs.where((s) => !existingIds.contains(s.id)).take(10).toList();
      if (toAdd.isEmpty) return;

      _audioService.updateQueue([...existing, ...toAdd]);
      debugPrint('[Home] extended queue by ${toAdd.length}');
    } catch (e) {
      debugPrint('[Home] extend error: $e');
    } finally {
      _filling = false;
    }
  }

  /// Fetches related songs; falls back to shuffled cached songs when offline.
  Future<List<Song>> _fetchRelated(Song seed) async {
    try {
      final songs = await _homeService.getRelatedSongs(seed.id);
      if (songs.isNotEmpty) return songs;
    } catch (_) {}

    debugPrint('[Home] offline fallback queue for ${seed.id}');
    final cached = _db.getCachedSongs()
        .where((s) => s.id != seed.id)
        .toList()
      ..shuffle();
    return cached;
  }

  // ── Category playback ─────────────────────────────────────────────────────

  Future<void> playCategory(String query) async {
    final result = await _homeService.getCategorySongs(query);
    if (result.songs.isNotEmpty) {
      await _audioService.playSong(result.songs.first,
          queue: result.songs, playlistMode: false);
    }
  }

  Future<void> refresh() => _loadRecommended();

  @override
  void dispose() {
    _homeService.dispose();
    super.dispose();
  }
}
