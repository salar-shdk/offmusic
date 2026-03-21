import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../models/song.dart';
import 'database_service.dart';

class CacheService {
  final DatabaseService _db;
  static const _cacheDir = 'audio_cache';

  CacheService(this._db);

  Future<Directory> _getCacheDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${appDir.path}/$_cacheDir');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  Future<String> _audioFilePath(String songId) async {
    final dir = await _getCacheDirectory();
    return '${dir.path}/$songId.mp3';
  }

  /// Returns the expected cache file path without checking if it exists.
  Future<String> getAudioFilePath(String songId) => _audioFilePath(songId);

  /// Returns the local path if cached, null otherwise.
  Future<String?> getCachedAudioPath(String songId) async {
    final song = _db.getSong(songId);
    if (song?.cachedAudioPath != null) {
      final file = File(song!.cachedAudioPath!);
      if (await file.exists()) return song.cachedAudioPath;
      // File was deleted externally
      await _db.updateSongCache(songId, '');
    }
    return null;
  }

  /// Download and cache audio from a stream URL. Returns the local path.
  Future<String?> cacheAudio(Song song, String streamUrl) async {
    try {
      final path = await _audioFilePath(song.id);
      final file = File(path);
      if (await file.exists()) {
        await _db.updateSongCache(song.id, path);
        return path;
      }
      final response = await http.get(Uri.parse(streamUrl));
      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        await _db.updateSongCache(song.id, path);
        return path;
      }
    } catch (e) {
      // Cache failed, will use stream URL
    }
    return null;
  }

  Future<int> getCacheSizeBytes() async {
    final dir = await _getCacheDirectory();
    int total = 0;
    await for (final entity in dir.list()) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }

  Future<void> clearCache() async {
    final dir = await _getCacheDirectory();
    await dir.delete(recursive: true);
    await dir.create();
    // Reset all cache paths
    for (final song in _db.getCachedSongs()) {
      song.cachedAudioPath = null;
      song.cachedAt = null;
      await song.save();
    }
  }

  String formatSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }
}
