import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/song.dart';
import '../models/album.dart';
import '../models/artist.dart';
import '../models/playlist.dart';
import '../services/database_service.dart';
import '../services/cache_service.dart';
import '../services/audio_service.dart';

/// Possible values for auto-delete setting.
/// null = never, otherwise days threshold.
const _kAutoDeleteKey      = 'auto_delete_days';
const _kAutoPlayAutoKey    = 'auto_play_on_auto_connect';

class LibraryProvider extends ChangeNotifier {
  final DatabaseService _db;
  final CacheService _cache;
  final AudioPlayerService _audioService;
  StreamSubscription? _songCachedSub;
  int? _autoDeleteDays; // null = never
  bool _autoPlayOnAutoConnect = false;

  List<Song> _likedSongs = [];
  List<Album> _likedAlbums = [];
  List<Artist> _likedArtists = [];
  List<Playlist> _playlists = [];
  List<Song> _cachedSongs = [];

  int? get autoDeleteDays          => _autoDeleteDays;
  bool get autoPlayOnAutoConnect   => _autoPlayOnAutoConnect;

  LibraryProvider(this._db, this._cache, this._audioService) {
    _refresh();
    _songCachedSub = _audioService.songCachedStream.listen((_) => _refresh());
    _loadPrefsAndCleanup();
  }

  Future<void> _loadPrefsAndCleanup() async {
    final prefs = await SharedPreferences.getInstance();
    _autoDeleteDays = prefs.getInt(_kAutoDeleteKey);
    _autoPlayOnAutoConnect = prefs.getBool(_kAutoPlayAutoKey) ?? false;
    notifyListeners();
    // Push autoplay setting to native so it's ready before Auto connects
    if (_autoPlayOnAutoConnect) {
      await _audioService.setAutoAutoplay(true);
    }
    if (_autoDeleteDays != null) {
      await _db.deleteUnplayedSongs(_autoDeleteDays!);
      _refresh();
    }
  }

  Future<void> setAutoPlayOnAutoConnect(bool value) async {
    _autoPlayOnAutoConnect = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoPlayAutoKey, value);
    await _audioService.setAutoAutoplay(value);
    notifyListeners();
  }

  Future<void> setAutoDeleteDays(int? days) async {
    _autoDeleteDays = days;
    final prefs = await SharedPreferences.getInstance();
    if (days == null) {
      await prefs.remove(_kAutoDeleteKey);
    } else {
      await prefs.setInt(_kAutoDeleteKey, days);
      await _db.deleteUnplayedSongs(days);
      _refresh();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _songCachedSub?.cancel();
    super.dispose();
  }

  List<Song> get likedSongs => _likedSongs;
  List<Album> get likedAlbums => _likedAlbums;
  List<Artist> get likedArtists => _likedArtists;
  List<Playlist> get playlists => _playlists;
  List<Song> get cachedSongs => _cachedSongs;

  void _refresh() {
    _likedSongs = _db.getLikedSongs();
    _likedAlbums = _db.getLikedAlbums();
    _likedArtists = _db.getLikedArtists();
    _playlists = _db.getAllPlaylists();
    _cachedSongs = _db.getCachedSongs();
    notifyListeners();
    _pushAutoData();
  }

  void _pushAutoData() {
    unawaited(_audioService.setAutoLikedSongs(_likedSongs));
    final playlistData = _playlists.map((pl) {
      final songs = pl.songIds
          .map((id) => _db.getSong(id))
          .whereType<Song>()
          .toList();
      return <String, dynamic>{
        'id': pl.id,
        'name': pl.name,
        'songs': songs.take(100).map((s) => {
          'id': s.id,
          'title': s.title,
          'artist': s.artist,
          'thumbnailUrl': s.thumbnailUrl,
        }).toList(),
      };
    }).toList();
    unawaited(_audioService.setAutoPlaylists(playlistData));
  }

  bool isSongLiked(String id) => _db.getSong(id)?.isLiked ?? false;
  bool isAlbumLiked(String id) => _db.getAlbum(id)?.isLiked ?? false;
  bool isArtistLiked(String id) => _db.getArtist(id)?.isLiked ?? false;

  Future<void> toggleSongLike(Song song) async {
    await _db.saveSong(song);
    await _db.toggleSongLike(song.id);
    _refresh();
  }

  Future<void> toggleAlbumLike(Album album) async {
    await _db.saveAlbum(album);
    await _db.toggleAlbumLike(album.id);
    _refresh();
  }

  Future<void> toggleArtistLike(Artist artist) async {
    await _db.saveArtist(artist);
    await _db.toggleArtistLike(artist.id);
    _refresh();
  }

  Future<Playlist> createPlaylist(String name, {String? description}) async {
    const uuid = Uuid();
    final playlist = Playlist(
      id: uuid.v4(),
      name: name,
      description: description,
      songIds: [],
      createdAt: DateTime.now(),
    );
    await _db.savePlaylist(playlist);
    _refresh();
    return playlist;
  }

  Future<void> deletePlaylist(String id) async {
    await _db.deletePlaylist(id);
    _refresh();
  }

  Future<void> renamePlaylist(String id, String name) async {
    final pl = _db.getPlaylist(id);
    if (pl != null) {
      pl.name = name;
      await pl.save();
      _refresh();
    }
  }

  Future<void> addSongToPlaylist(String playlistId, Song song) async {
    await _db.saveSong(song);
    await _db.addSongToPlaylist(playlistId, song.id);
    _refresh();
  }

  Future<void> removeSongFromPlaylist(String playlistId, String songId) async {
    await _db.removeSongFromPlaylist(playlistId, songId);
    _refresh();
  }

  List<Song> getPlaylistSongs(String playlistId) {
    final pl = _db.getPlaylist(playlistId);
    if (pl == null) return [];
    return pl.songIds
        .map((id) => _db.getSong(id))
        .whereType<Song>()
        .toList();
  }

  Future<void> removeSongFromCache(String songId) async {
    final song = _db.getSong(songId);
    if (song == null || !song.isAvailableOffline) return;
    final path = song.cachedAudioPath;
    song.cachedAudioPath = null;
    song.cachedAt = null;
    await song.save();
    if (path != null) {
      try {
        final f = File(path);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    _refresh();
  }

  Future<String> getCacheSizeFormatted() async {
    final bytes = await _cache.getCacheSizeBytes();
    return _cache.formatSize(bytes);
  }

  Future<void> clearCache() async {
    await _cache.clearCache();
    _refresh();
  }

  /// Serialises liked songs/albums/artists + playlists to JSON.
  /// Returns the [File] that was written so the caller can share it.
  Future<File> exportLibrary() async {
    final data = _db.exportData();
    final json = const JsonEncoder.withIndent('  ').convert(data);
    final dir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/offmusic_backup_$ts.json');
    await file.writeAsString(json);
    return file;
  }

  /// Reads a JSON file at [path] and merges its data into the DB.
  /// Automatically routes playlist share files (type == 'playlist') to
  /// [importPlaylist] so both formats work from the same import button.
  Future<void> importLibrary(String path) async {
    final raw = await File(path).readAsString();
    final data = jsonDecode(raw) as Map<String, dynamic>;
    if (data['type'] == 'playlist') {
      await _db.importPlaylist(data);
    } else {
      await _db.importData(data);
    }
    _refresh();
  }

  /// Exports a single playlist to a shareable JSON file.
  Future<File> exportPlaylist(String playlistId) async {
    final data = _db.exportPlaylist(playlistId);
    final json = const JsonEncoder.withIndent('  ').convert(data);
    final dir = await getTemporaryDirectory();
    final playlist = _db.getPlaylist(playlistId);
    final safeName = (playlist?.name ?? 'playlist')
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .trim()
        .replaceAll(' ', '_');
    final file = File('${dir.path}/offmusic_playlist_$safeName.json');
    await file.writeAsString(json);
    return file;
  }
}
