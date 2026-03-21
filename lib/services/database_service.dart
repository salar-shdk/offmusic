import 'dart:io';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/song.dart';
import '../models/album.dart';
import '../models/artist.dart';
import '../models/playlist.dart';

class DatabaseService {
  static const _songsBox = 'songs';
  static const _albumsBox = 'albums';
  static const _artistsBox = 'artists';
  static const _playlistsBox = 'playlists';

  static const _playCountsBox = 'play_counts';
  static const _lastPlayedBox = 'last_played';

  static Future<void> init() async {
    await Hive.initFlutter();
    Hive.registerAdapter(SongAdapter());
    Hive.registerAdapter(AlbumAdapter());
    Hive.registerAdapter(ArtistAdapter());
    Hive.registerAdapter(PlaylistAdapter());
    await Future.wait([
      Hive.openBox<Song>(_songsBox),
      Hive.openBox<Album>(_albumsBox),
      Hive.openBox<Artist>(_artistsBox),
      Hive.openBox<Playlist>(_playlistsBox),
      Hive.openBox<int>(_playCountsBox),
      Hive.openBox<int>(_lastPlayedBox),
    ]);
  }

  // Songs
  Box<Song> get _songs => Hive.box<Song>(_songsBox);

  Song? getSong(String id) => _songs.get(id);

  List<Song> getAllSongs() => _songs.values.toList();

  List<Song> getLikedSongs() =>
      _songs.values.where((s) => s.isLiked).toList();

  List<Song> getCachedSongs() =>
      _songs.values.where((s) => s.isAvailableOffline).toList();

  Future<void> saveSong(Song song) => _songs.put(song.id, song);

  Future<void> toggleSongLike(String id) async {
    final song = _songs.get(id);
    if (song != null) {
      song.isLiked = !song.isLiked;
      await song.save();
    }
  }

  // Last played timestamps (epoch ms)
  Box<int> get _lastPlayed => Hive.box<int>(_lastPlayedBox);

  Future<void> updateLastPlayed(String songId) =>
      _lastPlayed.put(songId, DateTime.now().millisecondsSinceEpoch);

  /// Deletes cached audio for songs not played in the last [days] days,
  /// skipping songs that belong to any playlist.
  /// Returns the number of songs cleaned up.
  Future<int> deleteUnplayedSongs(int days) async {
    final cutoff = DateTime.now()
        .subtract(Duration(days: days))
        .millisecondsSinceEpoch;
    // Build set of song IDs that are in any playlist.
    final playlistSongIds = _playlists.values
        .expand((pl) => pl.songIds)
        .toSet();
    int count = 0;
    for (final song in _songs.values.where((s) => s.isAvailableOffline)) {
      if (playlistSongIds.contains(song.id)) continue; // keep playlist songs
      final lastMs = _lastPlayed.get(song.id);
      // Never played OR played before cutoff
      if (lastMs == null || lastMs < cutoff) {
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
        count++;
      }
    }
    return count;
  }

  // Play counts
  Box<int> get _playCounts => Hive.box<int>(_playCountsBox);

  Future<void> incrementPlayCount(String songId) async {
    final current = _playCounts.get(songId) ?? 0;
    await _playCounts.put(songId, current + 1);
  }

  /// Returns song IDs sorted by play count descending.
  List<String> getMostPlayedSongIds({int limit = 5}) {
    final entries = _playCounts.keys
        .map((k) => MapEntry(k as String, _playCounts.get(k) ?? 0))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).map((e) => e.key).toList();
  }

  Future<void> updateSongCache(String id, String path) async {
    final song = _songs.get(id);
    if (song != null) {
      song.cachedAudioPath = path;
      song.cachedAt = DateTime.now();
      await song.save();
    }
  }

  // Albums
  Box<Album> get _albums => Hive.box<Album>(_albumsBox);

  Album? getAlbum(String id) => _albums.get(id);

  List<Album> getLikedAlbums() =>
      _albums.values.where((a) => a.isLiked).toList();

  Future<void> saveAlbum(Album album) => _albums.put(album.id, album);

  Future<void> toggleAlbumLike(String id) async {
    final album = _albums.get(id);
    if (album != null) {
      album.isLiked = !album.isLiked;
      await album.save();
    }
  }

  // Artists
  Box<Artist> get _artists => Hive.box<Artist>(_artistsBox);

  Artist? getArtist(String id) => _artists.get(id);

  List<Artist> getLikedArtists() =>
      _artists.values.where((a) => a.isLiked).toList();

  Future<void> saveArtist(Artist artist) => _artists.put(artist.id, artist);

  Future<void> toggleArtistLike(String id) async {
    final artist = _artists.get(id);
    if (artist != null) {
      artist.isLiked = !artist.isLiked;
      await artist.save();
    }
  }

  // Playlists
  Box<Playlist> get _playlists => Hive.box<Playlist>(_playlistsBox);

  List<Playlist> getAllPlaylists() => _playlists.values.toList();

  Playlist? getPlaylist(String id) => _playlists.get(id);

  Future<void> savePlaylist(Playlist playlist) =>
      _playlists.put(playlist.id, playlist);

  Future<void> deletePlaylist(String id) => _playlists.delete(id);

  Future<void> addSongToPlaylist(String playlistId, String songId) async {
    final pl = _playlists.get(playlistId);
    if (pl != null && !pl.songIds.contains(songId)) {
      pl.songIds.add(songId);
      await pl.save();
    }
  }

  Future<void> removeSongFromPlaylist(String playlistId, String songId) async {
    final pl = _playlists.get(playlistId);
    if (pl != null) {
      pl.songIds.remove(songId);
      await pl.save();
    }
  }

  // ── Import / Export ──────────────────────────────────────────────────────

  Map<String, dynamic> exportData() {
    return {
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'likedSongs': getLikedSongs().map((s) => {
            'id': s.id,
            'title': s.title,
            'artist': s.artist,
            'artistId': s.artistId,
            'album': s.album,
            'albumId': s.albumId,
            'thumbnailUrl': s.thumbnailUrl,
            'durationSeconds': s.durationSeconds,
          }).toList(),
      'likedAlbums': getLikedAlbums().map((a) => {
            'id': a.id,
            'title': a.title,
            'artist': a.artist,
            'artistId': a.artistId,
            'thumbnailUrl': a.thumbnailUrl,
            'year': a.year,
            'songIds': a.songIds,
          }).toList(),
      'likedArtists': getLikedArtists().map((a) => {
            'id': a.id,
            'name': a.name,
            'thumbnailUrl': a.thumbnailUrl,
            'description': a.description,
          }).toList(),
      'playlists': getAllPlaylists().map((pl) => {
            'id': pl.id,
            'name': pl.name,
            'description': pl.description,
            'createdAt': pl.createdAt.toIso8601String(),
            'songIds': pl.songIds,
            'songs': pl.songIds
                .map(getSong)
                .whereType<Song>()
                .map((s) => {
                      'id': s.id,
                      'title': s.title,
                      'artist': s.artist,
                      'artistId': s.artistId,
                      'album': s.album,
                      'albumId': s.albumId,
                      'thumbnailUrl': s.thumbnailUrl,
                      'durationSeconds': s.durationSeconds,
                    })
                .toList(),
          }).toList(),
    };
  }

  Future<void> importData(Map<String, dynamic> data) async {
    Song songFromMap(Map<String, dynamic> m, {bool isLiked = false}) => Song(
          id: m['id'] as String,
          title: m['title'] as String,
          artist: m['artist'] as String,
          artistId: m['artistId'] as String,
          album: m['album'] as String,
          albumId: m['albumId'] as String,
          thumbnailUrl: m['thumbnailUrl'] as String,
          durationSeconds: m['durationSeconds'] as int,
          isLiked: isLiked,
        );

    for (final raw in (data['likedSongs'] as List? ?? [])) {
      final m = raw as Map<String, dynamic>;
      final existing = getSong(m['id'] as String);
      if (existing == null) {
        await saveSong(songFromMap(m, isLiked: true));
      } else if (!existing.isLiked) {
        existing.isLiked = true;
        await existing.save();
      }
    }

    for (final raw in (data['likedAlbums'] as List? ?? [])) {
      final m = raw as Map<String, dynamic>;
      final id = m['id'] as String;
      final existing = getAlbum(id);
      if (existing == null) {
        await saveAlbum(Album(
          id: id,
          title: m['title'] as String,
          artist: m['artist'] as String,
          artistId: m['artistId'] as String,
          thumbnailUrl: m['thumbnailUrl'] as String,
          year: m['year'] as int,
          songIds: List<String>.from(m['songIds'] as List),
          isLiked: true,
        ));
      } else if (!existing.isLiked) {
        existing.isLiked = true;
        await existing.save();
      }
    }

    for (final raw in (data['likedArtists'] as List? ?? [])) {
      final m = raw as Map<String, dynamic>;
      final id = m['id'] as String;
      final existing = getArtist(id);
      if (existing == null) {
        await saveArtist(Artist(
          id: id,
          name: m['name'] as String,
          thumbnailUrl: m['thumbnailUrl'] as String,
          description: m['description'] as String?,
          isLiked: true,
        ));
      } else if (!existing.isLiked) {
        existing.isLiked = true;
        await existing.save();
      }
    }

    for (final raw in (data['playlists'] as List? ?? [])) {
      final m = raw as Map<String, dynamic>;
      final id = m['id'] as String;
      // Save any songs embedded in the playlist that don't exist yet.
      for (final songRaw in (m['songs'] as List? ?? [])) {
        final sm = songRaw as Map<String, dynamic>;
        if (getSong(sm['id'] as String) == null) {
          await saveSong(songFromMap(sm));
        }
      }
      if (getPlaylist(id) == null) {
        await savePlaylist(Playlist(
          id: id,
          name: m['name'] as String,
          description: m['description'] as String?,
          songIds: List<String>.from(m['songIds'] as List),
          createdAt: DateTime.parse(m['createdAt'] as String),
        ));
      }
    }
  }
}
