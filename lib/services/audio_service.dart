import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/song.dart';
import 'cache_service.dart';
import 'database_service.dart';

enum RepeatMode { none, all, one }

class PlayerState {
  final Song? currentSong;
  final List<Song> queue;
  final int queueIndex;
  final bool isPlaying;
  final bool isLoading;
  final Duration position;
  final Duration duration;
  final RepeatMode repeatMode;
  final bool shuffle;
  final String? error;
  /// True when the queue comes from a fixed playlist — suppresses auto-extension.
  final bool playlistMode;

  const PlayerState({
    this.currentSong,
    this.queue = const [],
    this.queueIndex = 0,
    this.isPlaying = false,
    this.isLoading = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.repeatMode = RepeatMode.none,
    this.shuffle = false,
    this.error,
    this.playlistMode = false,
  });

  PlayerState copyWith({
    Song? currentSong,
    List<Song>? queue,
    int? queueIndex,
    bool? isPlaying,
    bool? isLoading,
    Duration? position,
    Duration? duration,
    RepeatMode? repeatMode,
    bool? shuffle,
    String? error,
    bool clearError = false,
    bool? playlistMode,
  }) {
    return PlayerState(
      currentSong: currentSong ?? this.currentSong,
      queue: queue ?? this.queue,
      queueIndex: queueIndex ?? this.queueIndex,
      isPlaying: isPlaying ?? this.isPlaying,
      isLoading: isLoading ?? this.isLoading,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      repeatMode: repeatMode ?? this.repeatMode,
      shuffle: shuffle ?? this.shuffle,
      error: clearError ? null : (error ?? this.error),
      playlistMode: playlistMode ?? this.playlistMode,
    );
  }
}

/// Drives the native Android ExoPlayer (PlayerBridge / OffmusicPlayer)
/// via MethodChannel + EventChannel. The ExoPlayer is configured identically
/// to Kreate: OkHttpDataSource + ResolvingDataSource + NewPipeExtractor n-param.
class AudioPlayerService {
  static const _method = MethodChannel('com.offmusic.offmusic/player');
  static const _events = EventChannel('com.offmusic.offmusic/player_events');

  final DatabaseService _db;
  final CacheService _cache;

  final _stateController = StreamController<PlayerState>.broadcast();
  final _songCachedController = StreamController<String>.broadcast();
  PlayerState _state = const PlayerState();
  StreamSubscription? _eventSub;
  Timer? _positionTimer;
  // Incremented each time a new song is requested. Stale loads check this
  // and bail out if superseded, preventing two songs playing at once.
  int _activeLoadId = 0;

  Stream<PlayerState> get stateStream => _stateController.stream;
  /// Emits a song ID each time a song is successfully cached to disk.
  Stream<String> get songCachedStream => _songCachedController.stream;
  PlayerState get state => _state;

  AudioPlayerService(this._db, this._cache) {
    _eventSub = _events.receiveBroadcastStream().listen(
      _onNativeEvent,
      onError: (e) {
        debugPrint('[Audio] event channel error: $e');
        _updateState(_state.copyWith(error: e.toString(), isLoading: false));
      },
    );
  }

  void _onNativeEvent(dynamic raw) {
    if (raw is! Map) return;
    final map = Map<String, dynamic>.from(raw);

    // Commands routed from notification buttons (next/prev)
    final command = map['command'] as String?;
    if (command == 'skipNext') { unawaited(skipNext()); return; }
    if (command == 'skipPrev') { unawaited(skipPrevious()); return; }

    final error = map['error'] as String?;
    if (error != null) {
      debugPrint('[Audio] native error: $error');
      _stopPositionTimer();
      _updateState(_state.copyWith(isLoading: false, isPlaying: false, error: error));
      return;
    }

    final isPlaying = map['isPlaying'] as bool? ?? _state.isPlaying;
    final position = Duration(milliseconds: (map['position'] as num?)?.toInt() ?? 0);
    final duration = Duration(milliseconds: (map['duration'] as num?)?.toInt() ?? 0);

    // If Flutter has no current song but Android reports one playing (e.g. the
    // app was reopened while music was playing in the background), restore the
    // current song from the native state so the UI reflects what's playing.
    final nativeVideoId = map['videoId'] as String?;
    Song? restoredSong;
    if (_state.currentSong == null &&
        nativeVideoId != null &&
        nativeVideoId.isNotEmpty) {
      restoredSong = _db.getSong(nativeVideoId);
      if (restoredSong == null) {
        // Build a minimal Song from the metadata in the event so the mini
        // player and now-playing screen can at least show title/artist.
        restoredSong = Song(
          id: nativeVideoId,
          title: map['title'] as String? ?? nativeVideoId,
          artist: map['artist'] as String? ?? '',
          artistId: '',
          album: '',
          albumId: '',
          thumbnailUrl: map['thumbnailUrl'] as String? ?? '',
          durationSeconds: duration.inSeconds,
        );
      }
      debugPrint('[Audio] restored current song from native state: $nativeVideoId');
    }

    _updateState(_state.copyWith(
      currentSong: restoredSong ?? _state.currentSong,
      queue: restoredSong != null && _state.queue.isEmpty
          ? [restoredSong]
          : null,
      isPlaying: isPlaying,
      isLoading: map['isLoading'] as bool? ?? _state.isLoading,
      position: position,
      duration: duration,
      clearError: true,
    ));

    if (isPlaying && _positionTimer == null) {
      _startPositionTimer();
    } else if (!isPlaying) {
      _stopPositionTimer();
    }
  }

  void _startPositionTimer() {
    _positionTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!_state.isPlaying) {
        _stopPositionTimer();
        return;
      }
      final next = _state.position + const Duration(milliseconds: 500);
      if (next <= _state.duration) {
        _updateState(_state.copyWith(position: next));
      }
    });
  }

  void _stopPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = null;
  }

  void _updateState(PlayerState s) {
    _state = s;
    _stateController.add(s);
  }

  Future<void> playSong(Song song, {List<Song>? queue, int? index, bool playlistMode = false}) async {
    final newQueue = queue ?? [song];
    final newIndex = index ?? 0;

    _updateState(_state.copyWith(
      currentSong: song,
      queue: newQueue,
      queueIndex: newIndex,
      isLoading: true,
      clearError: true,
      playlistMode: playlistMode,
    ));

    await _db.saveSong(song);
    await _db.incrementPlayCount(song.id);
    unawaited(_db.updateLastPlayed(song.id));
    await _loadAndPlay(song);
  }

  Future<void> _loadAndPlay(Song song) async {
    final id = ++_activeLoadId;
    try {
      debugPrint('[Audio] native play: ${song.id} (load#$id)');
      final cachedPath = await _cache.getCachedAudioPath(song.id);
      // If another song was requested while we were awaiting, bail out.
      if (id != _activeLoadId) {
        debugPrint('[Audio] load#$id superseded, aborting');
        return;
      }
      final meta = {
        'videoId': song.id,
        'title': song.title,
        'artist': song.artist,
        'thumbnailUrl': song.thumbnailUrl,
      };
      if (cachedPath != null) {
        debugPrint('[Audio] playing from cache: $cachedPath');
        await _method.invokeMethod('play', {...meta, 'filePath': cachedPath});
      } else {
        await _method.invokeMethod('play', meta);
        // Only cache in background if this load is still the active one.
        if (id == _activeLoadId) _cacheInBackground(song);
      }
      // isLoading → false will come via event channel once buffering starts
    } catch (e) {
      debugPrint('[Audio] play error: $e');
      if (id == _activeLoadId) {
        _updateState(_state.copyWith(isLoading: false, error: e.toString()));
      }
    }
  }

  void _cacheInBackground(Song song) {
    cacheSong(song);
  }

  /// Downloads [song] to local storage without playing it.
  /// Returns true on success, false on failure.
  Future<bool> cacheSong(Song song) async {
    if (song.isAvailableOffline) return true;
    try {
      final destPath = await _cache.getAudioFilePath(song.id);
      await _method.invokeMethod('downloadAudio', {
        'videoId': song.id,
        'destPath': destPath,
      });
      await _db.updateSongCache(song.id, destPath);
      _songCachedController.add(song.id);
      debugPrint('[Audio] cached: ${song.id}');
      return true;
    } catch (e) {
      debugPrint('[Audio] cache failed for ${song.id}: $e');
      return false;
    }
  }

  Future<void> togglePlay() async {
    try {
      if (_state.isPlaying) {
        await _method.invokeMethod('pause');
      } else {
        await _method.invokeMethod('resume');
      }
    } catch (e) {
      debugPrint('[Audio] togglePlay error: $e');
    }
  }

  Future<void> seek(Duration position) async {
    try {
      await _method.invokeMethod('seek', {'positionMs': position.inMilliseconds});
    } catch (e) {
      debugPrint('[Audio] seek error: $e');
    }
  }

  Future<void> skipNext() async {
    final queue = _state.queue;
    if (queue.isEmpty) return;
    int nextIndex = _state.shuffle
        ? (DateTime.now().millisecondsSinceEpoch % queue.length)
        : (_state.queueIndex + 1) % queue.length;
    final next = queue[nextIndex];
    _updateState(_state.copyWith(queueIndex: nextIndex, currentSong: next));
    await _loadAndPlay(next);
  }

  Future<void> skipPrevious() async {
    if (_state.position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }
    final queue = _state.queue;
    if (queue.isEmpty) return;
    int prevIndex = (_state.queueIndex - 1 + queue.length) % queue.length;
    final prev = queue[prevIndex];
    _updateState(_state.copyWith(queueIndex: prevIndex, currentSong: prev));
    await _loadAndPlay(prev);
  }

  void cycleRepeat() {
    final next = RepeatMode.values[
        (_state.repeatMode.index + 1) % RepeatMode.values.length];
    _updateState(_state.copyWith(repeatMode: next));
  }

  void toggleShuffle() => _updateState(_state.copyWith(shuffle: !_state.shuffle));

  Future<void> addToQueue(Song song) async {
    final queue = List<Song>.from(_state.queue)..add(song);
    _updateState(_state.copyWith(queue: queue));
    await _db.saveSong(song);
  }

  /// Replaces the queue in-place without changing the current song or position.
  void updateQueue(List<Song> newQueue) {
    _updateState(_state.copyWith(queue: newQueue));
  }

  Future<void> dispose() async {
    _stopPositionTimer();
    await _eventSub?.cancel();
    await _stateController.close();
    await _songCachedController.close();
  }
}
