import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/song.dart';

class HomeService {
  final _client = http.Client();

  static const _baseUrl = 'https://music.youtube.com/youtubei/v1';
  static const _apiKey = 'AIzaSyC9XL3ZjWddXya6X74dJoCTL-KLET5f07I';
  static const _clientVersion = '1.20240101.01.00';

  static const _headers = {
    'Content-Type': 'application/json',
    'User-Agent': 'Mozilla/5.0',
    'X-YouTube-Client-Name': '67',
    'X-YouTube-Client-Version': _clientVersion,
    'Origin': 'https://music.youtube.com',
    'Referer': 'https://music.youtube.com/',
  };

  static const _ctx = {
    'context': {
      'client': {
        'clientName': 'WEB_REMIX',
        'clientVersion': _clientVersion,
        'hl': 'en',
        'gl': 'US',
      },
    },
  };

  // ── Related songs (used for Quick Picks + auto-queue) ────────────────────────

  /// Fetches songs related to [videoId] via YouTube Music's "next" endpoint.
  Future<List<Song>> getRelatedSongs(String videoId) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl/next?key=$_apiKey'),
            headers: _headers,
            body: jsonEncode({..._ctx, 'videoId': videoId, 'isAudioOnly': true}),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final contents = _dig(data, [
            'contents',
            'singleColumnMusicWatchNextResultsRenderer',
            'tabbedRenderer',
            'watchNextTabbedResultsRenderer',
            'tabs',
            0,
            'tabRenderer',
            'content',
            'musicQueueRenderer',
            'content',
            'playlistPanelRenderer',
            'contents',
          ]) as List?;

      if (contents == null) return [];
      return contents
          .map(_parsePanelItem)
          .whereType<Song>()
          .toList();
    } catch (e) {
      debugPrint('[Home] getRelatedSongs error: $e');
      return [];
    }
  }

  Song? _parsePanelItem(dynamic raw) {
    final map = raw as Map<String, dynamic>?;
    // Handle both direct and wrapped panel video renderers
    final item = map?['playlistPanelVideoRenderer'] as Map<String, dynamic>?
        ?? (map?['playlistPanelVideoWrapperRenderer']
                ?['primaryRenderer']?['playlistPanelVideoRenderer']
            as Map<String, dynamic>?);

    if (item == null) return null;
    final videoId =
        item['navigationEndpoint']?['watchEndpoint']?['videoId'] as String?;
    final title =
        ((item['title']?['runs']) as List?)?.firstOrNull?['text'] as String?;
    final artist = ((item['shortBylineText']?['runs']) as List?)
        ?.firstOrNull?['text'] as String?;
    final thumbs = (item['thumbnail']?['thumbnails']) as List?;
    final thumb = _upgradeThumb(thumbs?.isNotEmpty == true
        ? thumbs!.last['url'] as String?
        : null);
    final durationText = ((item['lengthText']?['runs']) as List?)
        ?.firstOrNull?['text'] as String?;

    if (videoId == null || title == null) return null;
    return Song(
      id: videoId,
      title: title,
      artist: artist ?? '',
      artistId: '',
      album: '',
      albumId: '',
      thumbnailUrl: thumb,
      durationSeconds: _parseDuration(durationText),
    );
  }

  // ── Category search ──────────────────────────────────────────────────────────

  /// Searches YouTube Music for songs matching [query].
  /// Returns the song list and an optional continuation token for the next page.
  Future<({List<Song> songs, String? continuation})> getCategorySongs(String query) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl/search?key=$_apiKey'),
            headers: _headers,
            body: jsonEncode({
              ..._ctx,
              'query': query,
              'params': 'EgWKAQIIAWoKEAQQAxAJEAUQCg==', // songs filter
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) return (songs: <Song>[], continuation: null);

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final sectionList = _dig(data, [
        'contents', 'tabbedSearchResultsRenderer', 'tabs', 0,
        'tabRenderer', 'content', 'sectionListRenderer',
      ]) as Map?;

      final tabs = sectionList?['contents'] as List?;
      if (tabs == null) return (songs: <Song>[], continuation: null);

      final songs = <Song>[];
      String? continuation;

      for (final section in tabs) {
        final shelf = (section as Map<String, dynamic>)['musicShelfRenderer'] as Map?;
        if (shelf == null) continue;
        for (final item in (shelf['contents'] as List? ?? [])) {
          final song = _parseListItem(
              (item as Map<String, dynamic>)['musicResponsiveListItemRenderer']
                  as Map<String, dynamic>?);
          if (song != null) songs.add(song);
        }
        // Extract continuation token from this shelf
        continuation ??= (_dig(shelf, ['continuations', 0,
            'nextContinuationData', 'continuation'])) as String?;
      }

      // Also check at sectionList level
      continuation ??= (_dig(sectionList, ['continuations', 0,
          'nextContinuationData', 'continuation'])) as String?;

      return (songs: songs, continuation: continuation);
    } catch (e) {
      debugPrint('[Home] getCategorySongs error: $e');
      return (songs: <Song>[], continuation: null);
    }
  }

  /// Fetches the next page of category search results using a continuation token.
  Future<({List<Song> songs, String? continuation})> getCategorySongsContinuation(
      String token) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl/search?continuation=$token&ctoken=$token&key=$_apiKey'),
            headers: _headers,
            body: jsonEncode(_ctx),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) return (songs: <Song>[], continuation: null);

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final shelf = _dig(data, [
        'continuationContents', 'musicShelfContinuation',
      ]) as Map?;

      if (shelf == null) return (songs: <Song>[], continuation: null);

      final songs = <Song>[];
      for (final item in (shelf['contents'] as List? ?? [])) {
        final song = _parseListItem(
            (item as Map<String, dynamic>)['musicResponsiveListItemRenderer']
                as Map<String, dynamic>?);
        if (song != null) songs.add(song);
      }

      final nextToken = (_dig(shelf, ['continuations', 0,
          'nextContinuationData', 'continuation'])) as String?;

      return (songs: songs, continuation: nextToken);
    } catch (e) {
      debugPrint('[Home] getCategorySongsContinuation error: $e');
      return (songs: <Song>[], continuation: null);
    }
  }

  Song? _parseListItem(Map<String, dynamic>? item) {
    if (item == null) return null;
    // VideoId - try overlay path first, then title run
    final String? videoId =
        (_dig(item, ['overlay', 'musicItemThumbnailOverlayRenderer', 'content',
              'musicPlayButtonRenderer', 'playNavigationEndpoint', 'watchEndpoint',
              'videoId'])) as String? ??
        (_dig(item, ['flexColumns', 0, 'musicResponsiveListItemFlexColumnRenderer',
              'text', 'runs', 0, 'navigationEndpoint', 'watchEndpoint', 'videoId']))
            as String?;

    if (videoId == null) return null;

    final cols = item['flexColumns'] as List?;
    final title = (_dig(cols, [0, 'musicResponsiveListItemFlexColumnRenderer',
          'text', 'runs', 0, 'text'])) as String?;
    final artist = (_dig(cols, [1, 'musicResponsiveListItemFlexColumnRenderer',
          'text', 'runs', 0, 'text'])) as String?;
    final thumbs = (_dig(item, ['thumbnail', 'musicThumbnailRenderer',
          'thumbnail', 'thumbnails'])) as List?;
    final thumb = _upgradeThumb(thumbs?.isNotEmpty == true
        ? thumbs!.last['url'] as String?
        : null);

    if (title == null) return null;
    return Song(
      id: videoId,
      title: title,
      artist: artist ?? '',
      artistId: '',
      album: '',
      albumId: '',
      thumbnailUrl: thumb,
      durationSeconds: 0,
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  /// Upgrades a YouTube thumbnail URL to a higher-resolution variant.
  static String _upgradeThumb(String? url) {
    if (url == null || url.isEmpty) return '';
    if (url.contains('lh3.googleusercontent.com')) {
      return url.replaceAllMapped(
        RegExp(r'=w\d+-h\d+'),
        (_) => '=w500-h500',
      );
    }
    if (url.contains('i.ytimg.com')) {
      return url
          .replaceAll('mqdefault.jpg', 'hqdefault.jpg')
          .replaceAll('sddefault.jpg', 'hqdefault.jpg');
    }
    return url;
  }

  /// Safely traverses a nested structure via a list of keys/indices.
  dynamic _dig(dynamic obj, List<dynamic> keys) {
    dynamic cur = obj;
    for (final key in keys) {
      if (cur == null) return null;
      if (key is int) {
        if (cur is List && cur.length > key) {
          cur = cur[key];
        } else {
          return null;
        }
      } else {
        if (cur is Map) {
          cur = cur[key];
        } else {
          return null;
        }
      }
    }
    return cur;
  }

  int _parseDuration(String? text) {
    if (text == null) return 0;
    final parts = text.split(':');
    if (parts.length == 2) {
      return (int.tryParse(parts[0]) ?? 0) * 60 +
          (int.tryParse(parts[1]) ?? 0);
    }
    if (parts.length == 3) {
      return (int.tryParse(parts[0]) ?? 0) * 3600 +
          (int.tryParse(parts[1]) ?? 0) * 60 +
          (int.tryParse(parts[2]) ?? 0);
    }
    return 0;
  }

  void dispose() => _client.close();
}
