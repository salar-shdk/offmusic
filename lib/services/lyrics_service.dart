import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/lyrics.dart';

class LyricsService {
  static const _baseUrl = 'https://lrclib.net/api';

  Future<File> _cacheFile(String songId) async {
    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${dir.path}/lyrics_cache');
    if (!await cacheDir.exists()) await cacheDir.create(recursive: true);
    return File('${cacheDir.path}/$songId.json');
  }

  Future<Lyrics?> _loadCached(String songId) async {
    try {
      final file = await _cacheFile(songId);
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final isSynced = json['isSynced'] as bool? ?? false;
      final plainText = json['plainText'] as String?;
      final rawLines = json['lines'] as List? ?? [];
      final lines = rawLines.map((l) {
        return LyricLine(
          timestamp: Duration(milliseconds: (l['ms'] as num).toInt()),
          text: l['text'] as String,
        );
      }).toList();
      return Lyrics(songId: songId, lines: lines, isSynced: isSynced, plainText: plainText);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCache(Lyrics lyrics) async {
    try {
      final file = await _cacheFile(lyrics.songId);
      final json = {
        'isSynced': lyrics.isSynced,
        'plainText': lyrics.plainText,
        'lines': lyrics.lines.map((l) => {
          'ms': l.timestamp.inMilliseconds,
          'text': l.text,
        }).toList(),
      };
      await file.writeAsString(jsonEncode(json));
    } catch (e) {
      debugPrint('[Lyrics] cache write failed: $e');
    }
  }

  Future<Lyrics?> getLyrics(String songId, String title, String artist) async {
    final cached = await _loadCached(songId);
    if (cached != null && !cached.isEmpty) return cached;

    final fetched = await _fetchFromNetwork(songId, title, artist);
    if (fetched != null && !fetched.isEmpty) {
      await _saveCache(fetched);
    }
    return fetched;
  }

  Future<Lyrics?> _fetchFromNetwork(
      String songId, String title, String artist) async {
    try {
      final uri = Uri.parse('$_baseUrl/search').replace(queryParameters: {
        'track_name': title,
        'artist_name': artist,
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return _tryFallback(songId, title, artist);

      final results = jsonDecode(response.body) as List;
      if (results.isEmpty) return _tryFallback(songId, title, artist);

      for (final r in results) {
        final lrc = r['syncedLyrics'] as String?;
        if (lrc != null && lrc.isNotEmpty) {
          final parsed = Lyrics.parseLrc(songId, lrc);
          if (!parsed.isEmpty) return parsed;
        }
      }

      final plain = results.first['plainLyrics'] as String?;
      if (plain != null && plain.isNotEmpty) {
        final lines = plain
            .split('\n')
            .where((l) => l.trim().isNotEmpty)
            .map((l) => LyricLine(timestamp: Duration.zero, text: l))
            .toList();
        return Lyrics(songId: songId, lines: lines, isSynced: false, plainText: plain);
      }
    } catch (_) {}
    return null;
  }

  Future<Lyrics?> _tryFallback(
      String songId, String title, String artist) async {
    try {
      final uri = Uri.parse('$_baseUrl/search').replace(queryParameters: {
        'q': '$artist $title',
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final results = jsonDecode(response.body) as List;
      if (results.isEmpty) return null;

      final lrc = results.first['syncedLyrics'] as String?;
      if (lrc != null && lrc.isNotEmpty) {
        return Lyrics.parseLrc(songId, lrc);
      }
      final plain = results.first['plainLyrics'] as String?;
      if (plain != null && plain.isNotEmpty) {
        final lines = plain
            .split('\n')
            .where((l) => l.trim().isNotEmpty)
            .map((l) => LyricLine(timestamp: Duration.zero, text: l))
            .toList();
        return Lyrics(songId: songId, lines: lines, isSynced: false, plainText: plain);
      }
    } catch (_) {}
    return null;
  }
}
