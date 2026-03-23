import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/song.dart';
import '../models/lyrics.dart';
import '../services/audio_service.dart';
import '../services/lyrics_service.dart';
import '../services/database_service.dart';

class PlayerProvider extends ChangeNotifier {
  final AudioPlayerService _audioService;
  final LyricsService _lyricsService;
  final DatabaseService _db;

  PlayerState _playerState = const PlayerState();
  Lyrics? _lyrics;
  bool _lyricsLoading = false;
  bool _showLyrics = false;

  PlayerProvider(this._audioService, this._lyricsService, this._db) {
    _audioService.stateStream.listen((state) {
      final prevSongId = _playerState.currentSong?.id;
      _playerState = state;
      if (state.currentSong?.id != prevSongId && state.currentSong != null) {
        _loadLyrics(state.currentSong!);
      }
      notifyListeners();
    });
  }

  final Set<String> _cachingIds = {};

  PlayerState get playerState => _playerState;
  Lyrics? get lyrics => _lyrics;
  bool get lyricsLoading => _lyricsLoading;
  bool get showLyrics => _showLyrics;
  bool isCaching(String songId) => _cachingIds.contains(songId);

  Song? get currentSong => _playerState.currentSong;
  bool get isPlaying => _playerState.isPlaying;
  bool get isLoading => _playerState.isLoading;
  bool get playlistMode => _playerState.playlistMode;
  Duration get position => _playerState.position;
  Duration get duration => _playerState.duration;
  List<Song> get queue => _playerState.queue;
  RepeatMode get repeatMode => _playerState.repeatMode;
  bool get shuffle => _playerState.shuffle;
  String? get error => _playerState.error;

  double get progress {
    if (_playerState.duration.inMilliseconds == 0) return 0;
    return _playerState.position.inMilliseconds /
        _playerState.duration.inMilliseconds;
  }

  Future<void> playSong(Song song, {List<Song>? queue, int? index, bool playlistMode = false}) async {
    await _audioService.playSong(song, queue: queue, index: index, playlistMode: playlistMode);
  }

  Future<void> togglePlay() => _audioService.togglePlay();
  Future<void> skipNext() => _audioService.skipNext();
  Future<void> skipPrevious() => _audioService.skipPrevious();
  Future<void> seek(Duration position) => _audioService.seek(position);
  void cycleRepeat() => _audioService.cycleRepeat();
  void toggleShuffle() => _audioService.toggleShuffle();
  Future<void> addToQueue(Song song) => _audioService.addToQueue(song);

  /// Downloads [song] to local cache without playing it. Returns success.
  Future<bool> cacheSong(Song song) async {
    if (song.isAvailableOffline || _cachingIds.contains(song.id)) return true;
    _cachingIds.add(song.id);
    notifyListeners();
    final ok = await _audioService.cacheSong(song);
    _cachingIds.remove(song.id);
    notifyListeners();
    return ok;
  }

  void toggleShowLyrics() {
    _showLyrics = !_showLyrics;
    notifyListeners();
  }

  Future<void> _loadLyrics(Song song) async {
    _lyrics = null;
    _lyricsLoading = true;
    notifyListeners();
    // Clear Auto lyrics immediately so stale lyrics from the previous song
    // don't linger on the Android Auto player screen.
    unawaited(_audioService.setAutoLyrics([]));
    _lyrics = await _lyricsService.getLyrics(song.id, song.title, song.artist);
    _lyricsLoading = false;
    notifyListeners();
    // Only push synced lyrics — Auto subtitle needs timestamps to scroll correctly.
    if (_lyrics != null && _lyrics!.isSynced && !_lyrics!.isEmpty) {
      unawaited(_audioService.setAutoLyrics(_lyrics!.lines));
    }
  }

  bool get isSongLiked => currentSong != null &&
      (_db.getSong(currentSong!.id)?.isLiked ?? false);

  Future<void> toggleCurrentSongLike() async {
    if (currentSong == null) return;
    await _db.toggleSongLike(currentSong!.id);
    notifyListeners();
  }
}
