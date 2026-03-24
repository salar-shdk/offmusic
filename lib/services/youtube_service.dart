import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/song.dart';
import '../models/album.dart';
import '../models/artist.dart';

/// MethodChannel matching StreamUrlChannel.NAME on the Android side.
const _kStreamChannel = MethodChannel('com.offmusic.offmusic/stream');

class SearchResults {
  final List<Song> songs;
  final List<Album> albums;
  final List<Artist> artists;
  final String? songsContinuation;

  const SearchResults({
    required this.songs,
    required this.albums,
    required this.artists,
    this.songsContinuation,
  });
}

class YouTubeService {
  final _yt = YoutubeExplode();
  final _httpClient = http.Client();

  // Session cookies fetched on first request (Kreate's Store.kt approach)
  final Map<String, String> _cookies = {};
  bool _cookiesInitialized = false;

  // ── Client configs (matching Kreate / NewPipeExtractor) ─────────────────────

  // ANDROID client — primary, used by Kreate via NewPipeExtractor
  static const _kAndroidClientName = 'ANDROID';
  static const _kAndroidClientVersion = '21.03.36';
  static const _kAndroidClientNameId = '3';

  // IOS client — Kreate's first fallback
  static const _kIosClientName = 'IOS';
  static const _kIosClientVersion = '21.03.2';
  static const _kIosClientNameId = '5';
  static const _kIosDeviceModel = 'iPhone16,2';
  static const _kIosOsVersion = '18.7.2.22H124';

  // ANDROID_MUSIC client — hits music.youtube.com
  static const _kAndroidMusicClientName = 'ANDROID_MUSIC';
  static const _kAndroidMusicClientVersion = '6.33.52';
  static const _kAndroidMusicClientNameId = '21';

  // ── Endpoints ────────────────────────────────────────────────────────────────

  // googleapis endpoint — Kreate's primary player endpoint (no key needed)
  static const _kPlayerUrl =
      'https://youtubei.googleapis.com/youtubei/v1/player?prettyPrint=false';

  // music.youtube.com endpoint — ANDROID_MUSIC fallback
  static const _kMusicPlayerUrl =
      'https://music.youtube.com/youtubei/v1/player'
      '?key=AIzaSyAOghZGza2MQSZkY_zfZ370N-PUdXEo8AI';

  // YouTube Music search endpoint
  static const _kMusicSearchUrl =
      'https://music.youtube.com/youtubei/v1/search'
      '?key=AIzaSyC9XL3ZjWddXya6X74dJoCTL-KLET5f07I';

  // YouTube Music browse endpoint (for album/artist pages)
  static const _kMusicBrowseUrl =
      'https://music.youtube.com/youtubei/v1/browse'
      '?key=AIzaSyC9XL3ZjWddXya6X74dJoCTL-KLET5f07I';
  static const _kMusicClientVersion = '1.20240101.01.00';
  static const _kSongsFilterParam   = 'EgWKAQIIAWoKEAQQAxAJEAUQCg==';
  static const _kAlbumsFilterParam  = 'EgWKAQIYAWoKEAQQAxAJEAUQCg==';
  static const _kArtistsFilterParam = 'EgWKAQIgAWoKEAQQAxAJEAUQCg==';

  // ── Session bootstrapping (Kreate's Store.kt) ────────────────────────────────

  /// Fetches initial YouTube cookies so subsequent requests are treated as
  /// a normal browser/app session. Kreate does the same via Store.kt.
  Future<void> _ensureCookies() async {
    if (_cookiesInitialized) return;
    _cookiesInitialized = true;
    try {
      final response = await _httpClient.get(
        Uri.parse(
          'https://www.youtube.com/watch?v=dQw4w9WgXcQ'
          '&bpctr=9999999999&has_verified=1',
        ),
        headers: {
          'Cookie': 'PREF=hl=en&tz=UTC; SOCS=CAI',
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
              'AppleWebKit/537.36 (KHTML, like Gecko) '
              'Chrome/115.0.0.0 Safari/537.36',
          'Sec-Fetch-Mode': 'navigate',
        },
      ).timeout(const Duration(seconds: 8));

      final setCookie = response.headers['set-cookie'] ?? '';
      for (final part in setCookie.split(RegExp(r',(?=[^ ])'))) {
        final kv = part.split(';').first.trim();
        final idx = kv.indexOf('=');
        if (idx > 0) {
          _cookies[kv.substring(0, idx).trim()] =
              kv.substring(idx + 1).trim();
        }
      }
    } catch (_) {}
  }

  String _buildCookieHeader() {
    if (_cookies.isEmpty) return 'PREF=hl=en&tz=UTC; SOCS=CAI';
    return _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  // ── CPN generation ────────────────────────────────────────────────────────────

  /// Generates a content playback nonce (cpn) — required by Kreate's player.
  static String _generateCpn() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
    final rng = Random.secure();
    return List.generate(16, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  // ── Search ────────────────────────────────────────────────────────────────────

  Future<SearchResults> search(String query) async {
    final songsFuture = _searchMusicSongsWithContinuation(query);
    final albumsFuture = _searchAlbumsViaMusicApi(query);
    final artistsFuture = _searchMusicArtists(query);
    final songs = await songsFuture;
    final albums = await albumsFuture;
    final artists = await artistsFuture;
    return SearchResults(
      songs: songs.$1,
      albums: albums,
      artists: artists,
      songsContinuation: songs.$2,
    );
  }

  Future<List<Song>> searchSongs(String query) => _searchMusicSongs(query);

  /// Loads the next page of song results using a continuation token from a
  /// previous search. Returns the new songs and the next continuation token
  /// (null if there are no more pages).
  Future<(List<Song>, String?)> loadMoreSongs(String continuation) async {
    try {
      final response = await _httpClient
          .post(
            Uri.parse(_kMusicSearchUrl),
            headers: const {
              'Content-Type': 'application/json',
              'User-Agent': 'Mozilla/5.0',
              'X-YouTube-Client-Name': '67',
              'X-YouTube-Client-Version': _kMusicClientVersion,
              'Origin': 'https://music.youtube.com',
              'Referer': 'https://music.youtube.com/',
            },
            body: jsonEncode({
              'context': {
                'client': {
                  'clientName': 'WEB_REMIX',
                  'clientVersion': _kMusicClientVersion,
                  'hl': 'en',
                  'gl': 'US',
                },
              },
              'continuation': continuation,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return (<Song>[], null);
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      final contents = _dig(data, [
        'continuationContents', 'musicShelfContinuation', 'contents',
      ]) as List?;
      if (contents == null) return (<Song>[], null);

      final songs = <Song>[];
      for (final item in contents) {
        final song = _parseMusicSong(item);
        if (song != null) songs.add(song);
      }

      final nextToken = _dig(data, [
        'continuationContents', 'musicShelfContinuation',
        'continuations', 0, 'nextContinuationData', 'continuation',
      ]) as String?;

      return (songs, nextToken);
    } catch (_) {
      return (<Song>[], null);
    }
  }

  /// Returns a list of songs similar to [seed] using the search endpoint.
  /// Searches by artist first, falls back to title if artist is empty.
  /// This uses the same reliable search API as song search.
  Future<List<Song>> getSimilarSongs(Song seed) async {
    final queries = <String>[
      if (seed.artist.isNotEmpty) seed.artist,
      if (seed.title.isNotEmpty) seed.title,
    ];
    for (final query in queries) {
      try {
        final data = await _musicSearch(query, _kSongsFilterParam);
        if (data == null) continue;
        final songs = <Song>[];
        for (final item in _musicShelfItems(data)) {
          final song = _parseMusicSong(item);
          if (song != null && song.id != seed.id) songs.add(song);
        }
        if (songs.isNotEmpty) return songs;
      } catch (_) {}
    }
    return [];
  }

  /// Searches YouTube Music for songs using the InnerTube WEB_REMIX client.
  Future<List<Song>> _searchMusicSongs(String query) async {
    try {
      final data = await _musicSearch(query, _kSongsFilterParam);
      if (data == null) return [];
      final songs = <Song>[];
      for (final item in _musicShelfItems(data)) {
        final song = _parseMusicSong(item);
        if (song != null) songs.add(song);
      }
      return songs;
    } catch (_) {
      return [];
    }
  }

  /// Same as [_searchMusicSongs] but also returns the continuation token for
  /// fetching the next page of results.
  Future<(List<Song>, String?)> _searchMusicSongsWithContinuation(
      String query) async {
    try {
      final data = await _musicSearch(query, _kSongsFilterParam);
      if (data == null) return (<Song>[], null);
      final songs = <Song>[];
      for (final item in _musicShelfItems(data)) {
        final song = _parseMusicSong(item);
        if (song != null) songs.add(song);
      }
      final continuation = _extractSearchContinuation(data);
      return (songs, continuation);
    } catch (_) {
      return (<Song>[], null);
    }
  }

  /// Extracts the continuation token from the first musicShelfRenderer in a
  /// search response. Returns null if there are no more pages.
  String? _extractSearchContinuation(Map<String, dynamic> data) {
    final tabs = (data['contents'] as Map?)
        ?['tabbedSearchResultsRenderer']?['tabs'] as List?;
    final sections = tabs?.firstOrNull?['tabRenderer']?['content']
        ?['sectionListRenderer']?['contents'] as List?;
    if (sections == null) return null;
    for (final section in sections) {
      final shelf = section['musicShelfRenderer'] as Map?;
      if (shelf != null) {
        return _dig(shelf, [
          'continuations', 0, 'nextContinuationData', 'continuation',
        ]) as String?;
      }
    }
    return null;
  }

  /// Searches YouTube Music for artists using the InnerTube WEB_REMIX client.
  Future<List<Artist>> _searchMusicArtists(String query) async {
    try {
      final data = await _musicSearch(query, _kArtistsFilterParam);
      if (data == null) return [];
      final artists = <Artist>[];
      for (final item in _musicShelfItems(data)) {
        final artist = _parseMusicArtist(item);
        if (artist != null) artists.add(artist);
      }
      return artists;
    } catch (_) {
      return [];
    }
  }

  /// Sends a YouTube Music InnerTube search request and returns the decoded JSON.
  Future<Map<String, dynamic>?> _musicSearch(
      String query, String filterParam) async {
    final response = await _httpClient
        .post(
          Uri.parse(_kMusicSearchUrl),
          headers: const {
            'Content-Type': 'application/json',
            'User-Agent': 'Mozilla/5.0',
            'X-YouTube-Client-Name': '67',
            'X-YouTube-Client-Version': _kMusicClientVersion,
            'Origin': 'https://music.youtube.com',
            'Referer': 'https://music.youtube.com/',
          },
          body: jsonEncode({
            'context': {
              'client': {
                'clientName': 'WEB_REMIX',
                'clientVersion': _kMusicClientVersion,
                'hl': 'en',
                'gl': 'US',
              },
            },
            'query': query,
            'params': filterParam,
          }),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return null;
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Extracts the list of raw items from the first musicShelfRenderer in results.
  List<dynamic> _musicShelfItems(Map<String, dynamic> data) {
    final tabs = (data['contents'] as Map?)
        ?['tabbedSearchResultsRenderer']?['tabs'] as List?;
    final sections = tabs?.firstOrNull?['tabRenderer']?['content']
        ?['sectionListRenderer']?['contents'] as List?;
    if (sections == null) return [];
    for (final section in sections) {
      final shelf = section['musicShelfRenderer'] as Map?;
      if (shelf != null) {
        return shelf['contents'] as List? ?? [];
      }
    }
    return [];
  }

  Song? _parseMusicSong(dynamic raw) {
    final item = (raw as Map?)
        ?['musicResponsiveListItemRenderer'] as Map<String, dynamic>?;
    if (item == null) return null;

    // Video ID — try overlay path first, then title run navigationEndpoint.
    final videoId = (_dig(item, [
          'overlay', 'musicItemThumbnailOverlayRenderer', 'content',
          'musicPlayButtonRenderer', 'playNavigationEndpoint',
          'watchEndpoint', 'videoId',
        ]) ??
        _dig(item, [
          'flexColumns', 0, 'musicResponsiveListItemFlexColumnRenderer',
          'text', 'runs', 0, 'navigationEndpoint', 'watchEndpoint', 'videoId',
        ])) as String?;
    if (videoId == null) return null;

    final cols = item['flexColumns'] as List?;
    final title = _dig(cols, [
      0, 'musicResponsiveListItemFlexColumnRenderer', 'text', 'runs', 0, 'text',
    ]) as String?;

    String? artist;
    String? playCount;
    int durationSeconds = 0;
    final durationRe = RegExp(r'^\d+:\d{2}(?::\d{2})?$');
    // Matches "1.2M plays", "45K views", "1,234 plays", etc.
    final playsRe = RegExp(r'(?:plays|views)', caseSensitive: false);
    // Abbreviated standalone number that may precede a "plays" run: "1.2B", "45K"
    final shortNumRe = RegExp(r'^\d[\d.,]*\s*[KkMmBbTt]?$');

    // Duration is typically in fixedColumns[0] on the WEB_REMIX client.
    final fixedCols = item['fixedColumns'] as List?;
    final fixedDurText = (_dig(fixedCols, [
      0, 'musicResponsiveListItemFixedColumnRenderer', 'text', 'runs', 0, 'text',
    ]) as String?)?.trim() ?? '';
    if (durationRe.hasMatch(fixedDurText)) {
      final parts = fixedDurText.split(':');
      durationSeconds = parts.length == 3
          ? (int.tryParse(parts[0]) ?? 0) * 3600 +
            (int.tryParse(parts[1]) ?? 0) * 60 +
            (int.tryParse(parts[2]) ?? 0)
          : (int.tryParse(parts[0]) ?? 0) * 60 +
            (int.tryParse(parts[1]) ?? 0);
    }

    // Scan all subtitle flex columns (1+) for artist and play count.
    // Play count may be a single run ("1.2B plays") or two consecutive runs
    // ("1.2B" then "plays"), so track pendingNum across runs.
    String? pendingNum;
    for (int c = 1; c < (cols?.length ?? 0); c++) {
      final runs = (_dig(cols, [
        c, 'musicResponsiveListItemFlexColumnRenderer', 'text', 'runs',
      ]) as List?) ?? [];
      for (final run in runs) {
        final text = ((run as Map)['text'] as String? ?? '').trim();
        if (text.isEmpty || text == '•') {
          pendingNum = null;
          continue;
        }
        if (durationSeconds == 0 && durationRe.hasMatch(text)) {
          // Fallback: duration in flex column
          final parts = text.split(':');
          durationSeconds = parts.length == 3
              ? (int.tryParse(parts[0]) ?? 0) * 3600 +
                (int.tryParse(parts[1]) ?? 0) * 60 +
                (int.tryParse(parts[2]) ?? 0)
              : (int.tryParse(parts[0]) ?? 0) * 60 +
                (int.tryParse(parts[1]) ?? 0);
          pendingNum = null;
        } else if (playsRe.hasMatch(text)) {
          // "1.2B plays" as one run, OR "plays"/"views" after a number run
          playCount = pendingNum != null ? '$pendingNum $text'.trim() : text;
          pendingNum = null;
        } else if (shortNumRe.hasMatch(text)) {
          // Could be abbreviated play count number right before "plays" run
          pendingNum = text;
        } else {
          if (artist == null && run['navigationEndpoint'] != null) {
            artist = text;
          } else {
            artist ??= text;
          }
          pendingNum = null;
        }
      }
      pendingNum = null;
    }

    final thumbs = _dig(item, [
      'thumbnail', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails',
    ]) as List?;
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
      durationSeconds: durationSeconds,
      playCount: playCount,
    );
  }

  Artist? _parseMusicArtist(dynamic raw) {
    final item = (raw as Map?)
        ?['musicResponsiveListItemRenderer'] as Map<String, dynamic>?;
    if (item == null) return null;

    final browseId = _dig(item, [
      'navigationEndpoint', 'browseEndpoint', 'browseId',
    ]) as String?;
    final cols = item['flexColumns'] as List?;
    final name = _dig(cols, [
      0, 'musicResponsiveListItemFlexColumnRenderer', 'text', 'runs', 0, 'text',
    ]) as String?;
    if (name == null) return null;

    final thumbs = _dig(item, [
      'thumbnail', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails',
    ]) as List?;
    final thumb = _upgradeThumb(thumbs?.isNotEmpty == true
        ? thumbs!.last['url'] as String?
        : null);

    return Artist(
      id: browseId ?? name,
      name: name,
      thumbnailUrl: thumb,
    );
  }

  /// Upgrades a YouTube thumbnail URL to a higher-resolution variant.
  ///
  /// lh3.googleusercontent.com URLs embed the size in the suffix, e.g.
  /// `=w226-h226-l90-rj`. Replacing it with `=w500-h500-l90-rj` fetches a
  /// larger image from the same CDN at no extra cost.
  ///
  /// i.ytimg.com URLs use named quality levels — `hqdefault` is safe and
  /// widely available at 480×360; `maxresdefault` is higher (1280×720) but
  /// not guaranteed for every video.
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
        cur = (cur is List && cur.length > key) ? cur[key] : null;
      } else {
        cur = (cur is Map) ? cur[key] : null;
      }
    }
    return cur;
  }

  /// YouTube Music album search via InnerTube (WEB_REMIX client).
  /// Albums come back as musicResponsiveListItemRenderer (same renderer as
  /// songs/artists), with the browse ID in navigationEndpoint.browseEndpoint.
  Future<List<Album>> _searchAlbumsViaMusicApi(String query) async {
    try {
      final data = await _musicSearch(query, _kAlbumsFilterParam);
      if (data == null) return [];
      final albums = <Album>[];
      for (final item in _musicShelfItems(data)) {
        final album = _parseMusicAlbum(item);
        if (album != null) albums.add(album);
      }
      return albums;
    } catch (e) {
      debugPrint('[YT] album search error: $e');
      return [];
    }
  }

  Album? _parseMusicAlbum(dynamic raw) {
    final item = (raw as Map?)
        ?['musicResponsiveListItemRenderer'] as Map<String, dynamic>?;
    if (item == null) return null;

    // Browse ID for the album page.
    final browseId = _dig(item, [
      'navigationEndpoint', 'browseEndpoint', 'browseId',
    ]) as String?;
    if (browseId == null) return null;

    final cols = item['flexColumns'] as List?;
    final title = _dig(cols, [
      0, 'musicResponsiveListItemFlexColumnRenderer', 'text', 'runs', 0, 'text',
    ]) as String?;
    if (title == null) return null;

    // col[1] runs: ["Album", " • ", "Artist Name", " • ", "Year"]
    // The artist run has a navigationEndpoint; year is a parseable 4-digit int.
    final subtitleRuns = (_dig(cols, [
      1, 'musicResponsiveListItemFlexColumnRenderer', 'text', 'runs',
    ]) as List?) ?? [];

    String artist = '';
    int year = DateTime.now().year;
    for (final run in subtitleRuns) {
      final text = (run['text'] as String? ?? '').trim();
      // Artist run has a navigation endpoint.
      if (artist.isEmpty && run['navigationEndpoint'] != null && text.isNotEmpty) {
        artist = text;
        continue;
      }
      // Year is a 4-digit number in the valid range.
      final parsed = int.tryParse(text);
      if (parsed != null && parsed > 1900 && parsed <= DateTime.now().year) {
        year = parsed;
      }
    }

    final thumbs = _dig(item, [
      'thumbnail', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails',
    ]) as List?;
    final thumbUrl = _upgradeThumb(thumbs?.isNotEmpty == true
        ? (thumbs!.last['url'] as String?)
        : null);

    return Album(
      id: browseId,
      title: title,
      artist: artist,
      artistId: '',
      thumbnailUrl: thumbUrl,
      year: year,
      songIds: [],
    );
  }

  // ── Album songs (InnerTube browse) ───────────────────────────────────────────

  /// Fetches the song list for an album using the InnerTube browse endpoint.
  /// [browseId] is an `MPREb_...` browse ID returned by album search.
  /// Returns (songs, albumThumbnailUrl). Song thumbnails fall back to the
  /// album header art when individual items don't carry their own thumbnail.
  Future<(List<Song>, String)> getAlbumSongs(String browseId,
      {String fallbackThumb = ''}) async {
    try {
      final response = await _httpClient
          .post(
            Uri.parse(_kMusicBrowseUrl),
            headers: const {
              'Content-Type': 'application/json',
              'User-Agent': 'Mozilla/5.0',
              'X-YouTube-Client-Name': '67',
              'X-YouTube-Client-Version': _kMusicClientVersion,
              'Origin': 'https://music.youtube.com',
              'Referer': 'https://music.youtube.com/',
            },
            body: jsonEncode({
              'context': {
                'client': {
                  'clientName': 'WEB_REMIX',
                  'clientVersion': _kMusicClientVersion,
                  'hl': 'en',
                  'gl': 'US',
                },
              },
              'browseId': browseId,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return (<Song>[], '');
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      // Extract album thumbnail from header to use as fallback for each song.
      // Try musicDetailHeaderRenderer first, then musicImmersiveHeaderRenderer.
      String albumThumb = '';
      for (final headerKey in [
        'musicDetailHeaderRenderer',
        'musicImmersiveHeaderRenderer',
      ]) {
        final thumbs = (_dig(data, [
              'header',
              headerKey,
              'thumbnail',
              'croppedSquareThumbnailRenderer',
              'thumbnail',
              'thumbnails',
            ]) ??
            _dig(data, [
              'header',
              headerKey,
              'thumbnail',
              'musicThumbnailRenderer',
              'thumbnail',
              'thumbnails',
            ])) as List?;
        if (thumbs != null && thumbs.isNotEmpty) {
          albumThumb = _upgradeThumb(thumbs.last['url'] as String?);
          break;
        }
      }
      if (albumThumb.isEmpty) albumThumb = fallbackThumb;

      // Path: contents.twoColumnBrowseResultsRenderer.secondaryContents
      //       .sectionListRenderer.contents[].musicShelfRenderer.contents[]
      final secondary = _dig(data, [
        'contents',
        'twoColumnBrowseResultsRenderer',
        'secondaryContents',
        'sectionListRenderer',
        'contents',
      ]) as List?;
      if (secondary == null) return (<Song>[], albumThumb);

      final songs = <Song>[];
      for (final section in secondary) {
        final items =
            (section['musicShelfRenderer']?['contents'] as List?) ?? [];
        for (final raw in items) {
          final song = _parseAlbumSong(raw, albumThumb);
          if (song != null) songs.add(song);
        }
      }
      return (songs, albumThumb);
    } catch (e) {
      debugPrint('[YT] getAlbumSongs error: $e');
      return (<Song>[], '');
    }
  }

  Song? _parseAlbumSong(dynamic raw, [String albumThumb = '']) {
    final item = (raw as Map?)
        ?['musicResponsiveListItemRenderer'] as Map<String, dynamic>?;
    if (item == null) return null;

    // videoId is in the overlay play button path.
    final videoId = _dig(item, [
      'overlay',
      'musicItemThumbnailOverlayRenderer',
      'content',
      'musicPlayButtonRenderer',
      'playNavigationEndpoint',
      'watchEndpoint',
      'videoId',
    ]) as String?;
    if (videoId == null) return null;

    final cols = item['flexColumns'] as List?;
    final title = _dig(cols, [
      0,
      'musicResponsiveListItemFlexColumnRenderer',
      'text',
      'runs',
      0,
      'text',
    ]) as String?;
    if (title == null) return null;

    // artist is in flexColumns[1] runs
    final artist = _dig(cols, [
      1,
      'musicResponsiveListItemFlexColumnRenderer',
      'text',
      'runs',
      0,
      'text',
    ]) as String? ?? '';

    // Duration from fixedColumns[0] e.g. "4:59"
    final durationStr = _dig(item, [
      'fixedColumns',
      0,
      'musicResponsiveListItemFixedColumnRenderer',
      'text',
      'runs',
      0,
      'text',
    ]) as String? ?? '';
    int durationSeconds = 0;
    final parts = durationStr.split(':');
    if (parts.length == 2) {
      durationSeconds =
          (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
    }

    final thumbs = _dig(item, [
      'thumbnail',
      'musicThumbnailRenderer',
      'thumbnail',
      'thumbnails',
    ]) as List?;
    final songThumb = _upgradeThumb(thumbs != null && thumbs.isNotEmpty
        ? (thumbs.last['url'] as String?)
        : null);
    final thumb = songThumb.isNotEmpty ? songThumb : albumThumb;

    return Song(
      id: videoId,
      title: title,
      artist: artist,
      artistId: '',
      album: '',
      albumId: '',
      thumbnailUrl: thumb,
      durationSeconds: durationSeconds,
    );
  }

  // ── Stream URL (Kreate's multi-client approach) ───────────────────────────────

  /// Returns a direct audio stream URL.
  /// Tries in order:
  ///   1. ANDROID client → youtubei.googleapis.com  (Kreate primary)
  ///   2. IOS client → youtubei.googleapis.com       (Kreate fallback)
  ///   3. ANDROID_MUSIC client → music.youtube.com   (music-specific fallback)
  ///   4. youtube_explode_dart                        (last resort)
  Future<String?> getStreamUrl(String videoId) async {
    debugPrint('[YT] getStreamUrl($videoId)');

    // 1. Native MethodChannel → NewPipeExtractor (same as Kreate)
    //    Handles n-param deobfuscation via YoutubeJavaScriptPlayerManager.
    //    This is the primary path and mirrors exactly what Kreate does.
    debugPrint('[YT] trying native NewPipeExtractor channel');
    try {
      final url = await _kStreamChannel.invokeMethod<String>(
        'getStreamUrl',
        {'videoId': videoId},
      ).timeout(const Duration(seconds: 30));
      if (url != null && url.isNotEmpty) {
        debugPrint('[YT] native channel succeeded');
        return url;
      }
    } catch (e) {
      debugPrint('[YT] native channel error: $e');
    }

    // 2. youtube_explode_dart — pure-Dart n-param deobfuscation fallback
    debugPrint('[YT] trying youtube_explode_dart');
    try {
      final manifest = await _yt.videos.streamsClient
          .getManifest(videoId)
          .timeout(const Duration(seconds: 20));
      final audioOnly = manifest.audioOnly;
      if (audioOnly.isNotEmpty) {
        final streams = audioOnly.toList();
        final mp4 = streams
            .where((s) => s.codec.mimeType.contains('mp4'))
            .toList();
        final candidates = mp4.isNotEmpty ? mp4 : streams;
        candidates.sort((a, b) =>
            b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond));
        final chosen = candidates.first;
        debugPrint(
          '[YT] youtube_explode_dart succeeded: '
          'mime=${chosen.codec.mimeType} bitrate=${chosen.bitrate}',
        );
        return chosen.url.toString();
      }
    } catch (e) {
      debugPrint('[YT] youtube_explode_dart error: $e');
    }

    // 3–5. InnerTube clients — last resort (no n-param deobfuscation)
    await _ensureCookies();

    debugPrint('[YT] trying ANDROID InnerTube client');
    final androidUrl = await _tryAndroidClient(videoId);
    if (androidUrl != null) {
      debugPrint('[YT] ANDROID client succeeded');
      return androidUrl;
    }

    debugPrint('[YT] trying IOS InnerTube client');
    final iosUrl = await _tryIosClient(videoId);
    if (iosUrl != null) {
      debugPrint('[YT] IOS client succeeded');
      return iosUrl;
    }

    debugPrint('[YT] trying ANDROID_MUSIC InnerTube client');
    final musicUrl = await _tryAndroidMusicClient(videoId);
    if (musicUrl != null) {
      debugPrint('[YT] ANDROID_MUSIC client succeeded');
      return musicUrl;
    }

    debugPrint('[YT] all clients failed for $videoId');
    return null;
  }

  /// ANDROID client — matches Kreate's primary path via NewPipeExtractor.
  Future<String?> _tryAndroidClient(String videoId) async {
    try {
      debugPrint('[YT] ANDROID: sending request');
      final cpn = _generateCpn();
      final response = await _httpClient
          .post(
            Uri.parse(_kPlayerUrl),
            headers: {
              'Content-Type': 'application/json',
              'Cookie': _buildCookieHeader(),
              'User-Agent':
                  'com.google.android.youtube/$_kAndroidClientVersion '
                  '(Linux; U; Android 11; en_US) gzip',
              'X-YouTube-Client-Name': _kAndroidClientNameId,
              'X-YouTube-Client-Version': _kAndroidClientVersion,
            },
            body: jsonEncode({
              'videoId': videoId,
              'cpn': cpn,
              'contentCheckOk': true,
              'racyCheckOk': true,
              'context': {
                'client': {
                  'clientName': _kAndroidClientName,
                  'clientVersion': _kAndroidClientVersion,
                  'platform': 'MOBILE',
                  'clientScreen': 'WATCH',
                  'osName': 'Android',
                  'osVersion': '11',
                  'androidSdkVersion': 30,
                  'hl': 'en',
                  'gl': 'US',
                  'utcOffsetMinutes': 0,
                },
                'request': {
                  'internalExperimentFlags': [],
                  'useSsl': true,
                },
                'user': {'lockedSafetyMode': false},
              },
            }),
          )
          .timeout(const Duration(seconds: 12));

      return _extractAudioUrl(response);
    } catch (e) {
      debugPrint('[YT] ANDROID client error: $e');
      return null;
    }
  }

  /// IOS client — Kreate's IOS fallback path.
  Future<String?> _tryIosClient(String videoId) async {
    try {
      final cpn = _generateCpn();
      final response = await _httpClient
          .post(
            Uri.parse(_kPlayerUrl),
            headers: {
              'Content-Type': 'application/json',
              'Cookie': _buildCookieHeader(),
              'User-Agent':
                  'com.google.ios.youtube/$_kIosClientVersion'
                  '($_kIosDeviceModel; U; CPU iOS 18_7_2 like Mac OS X; en_US)',
              'X-YouTube-Client-Name': _kIosClientNameId,
              'X-YouTube-Client-Version': _kIosClientVersion,
            },
            body: jsonEncode({
              'videoId': videoId,
              'cpn': cpn,
              'contentCheckOk': true,
              'racyCheckOk': true,
              'context': {
                'client': {
                  'clientName': _kIosClientName,
                  'clientVersion': _kIosClientVersion,
                  'platform': 'MOBILE',
                  'clientScreen': 'WATCH',
                  'deviceMake': 'Apple',
                  'deviceModel': _kIosDeviceModel,
                  'osName': 'iOS',
                  'osVersion': _kIosOsVersion,
                  'hl': 'en',
                  'gl': 'US',
                  'utcOffsetMinutes': 0,
                },
                'request': {
                  'internalExperimentFlags': [],
                  'useSsl': true,
                },
                'user': {'lockedSafetyMode': false},
              },
            }),
          )
          .timeout(const Duration(seconds: 12));

      return _extractAudioUrl(response);
    } catch (e) {
      debugPrint('[YT] IOS client error: $e');
      return null;
    }
  }

  /// ANDROID_MUSIC client — hits music.youtube.com player endpoint.
  Future<String?> _tryAndroidMusicClient(String videoId) async {
    try {
      final cpn = _generateCpn();
      final response = await _httpClient
          .post(
            Uri.parse(_kMusicPlayerUrl),
            headers: {
              'Content-Type': 'application/json',
              'Cookie': _buildCookieHeader(),
              'User-Agent':
                  'com.google.android.apps.youtube.music/$_kAndroidMusicClientVersion '
                  '(Linux; U; Android 11; en_US) gzip',
              'X-YouTube-Client-Name': _kAndroidMusicClientNameId,
              'X-YouTube-Client-Version': _kAndroidMusicClientVersion,
              'X-Goog-Api-Key':
                  'AIzaSyAOghZGza2MQSZkY_zfZ370N-PUdXEo8AI',
              'X-Goog-FieldMask':
                  'playabilityStatus.status,'
                  'streamingData.adaptiveFormats,'
                  'videoDetails.videoId',
            },
            body: jsonEncode({
              'videoId': videoId,
              'cpn': cpn,
              'contentCheckOk': true,
              'racyCheckOk': true,
              'context': {
                'client': {
                  'clientName': _kAndroidMusicClientName,
                  'clientVersion': _kAndroidMusicClientVersion,
                  'androidSdkVersion': 30,
                  'hl': 'en',
                  'gl': 'US',
                  'utcOffsetMinutes': 0,
                },
                'request': {
                  'internalExperimentFlags': [],
                  'useSsl': true,
                },
                'user': {'lockedSafetyMode': false},
              },
            }),
          )
          .timeout(const Duration(seconds: 12));

      return _extractAudioUrl(response);
    } catch (e) {
      debugPrint('[YT] ANDROID_MUSIC client error: $e');
      return null;
    }
  }

  /// Parses a player API response and returns the best audio URL.
  /// Prefers audio/mp4 (AAC) over audio/webm (Opus) for Android compatibility.
  /// Only returns direct `url` fields — does NOT handle signatureCipher.
  String? _extractAudioUrl(http.Response response) {
    if (response.statusCode != 200) {
      debugPrint('[YT] player HTTP ${response.statusCode}');
      return null;
    }

    final Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[YT] JSON parse error: $e');
      return null;
    }

    final status =
        (data['playabilityStatus'] as Map<String, dynamic>?)?['status'];
    if (status != 'OK') {
      final reason = (data['playabilityStatus'] as Map<String, dynamic>?)
          ?['reason'];
      debugPrint('[YT] playabilityStatus=$status reason=$reason');
      return null;
    }

    final allFormats =
        (data['streamingData']?['adaptiveFormats'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .where((f) {
              final mime = f['mimeType'] as String? ?? '';
              final url = f['url'] as String?;
              return mime.startsWith('audio/') && url != null && url.isNotEmpty;
            })
            .toList();

    if (allFormats == null || allFormats.isEmpty) {
      debugPrint('[YT] no direct-URL audio formats found');
      return null;
    }

    // Prefer audio/mp4 (AAC) — universally supported on Android.
    // Fall back to audio/webm (Opus) if no mp4 formats exist.
    final mp4 = allFormats
        .where((f) => (f['mimeType'] as String).startsWith('audio/mp4'))
        .toList();
    final candidates = mp4.isNotEmpty ? mp4 : allFormats;

    // Within the chosen group, pick highest bitrate.
    candidates.sort((a, b) => ((b['bitrate'] as num?) ?? 0)
        .compareTo((a['bitrate'] as num?) ?? 0));

    final chosen = candidates.first;
    debugPrint(
      '[YT] selected format mime=${chosen['mimeType']} '
      'itag=${chosen['itag']} bitrate=${chosen['bitrate']}',
    );
    return chosen['url'] as String;
  }

  // ── Video/playlist helpers ────────────────────────────────────────────────────

  Future<Song?> getVideoDetails(String videoId) async {
    try {
      final video = await _yt.videos.get(videoId);
      return _videoToSong(video);
    } catch (_) {
      return null;
    }
  }

  Future<List<Song>> getPlaylistSongs(String playlistId) async {
    final songs = <Song>[];
    try {
      await for (final video in _yt.playlists.getVideos(playlistId)) {
        songs.add(_videoToSong(video));
        if (songs.length >= 50) break;
      }
    } catch (_) {}
    return songs;
  }

  static const _kMusicBrowseHeaders = {
    'Content-Type': 'application/json',
    'User-Agent': 'Mozilla/5.0',
    'X-YouTube-Client-Name': '67',
    'X-YouTube-Client-Version': _kMusicClientVersion,
    'Origin': 'https://music.youtube.com',
    'Referer': 'https://music.youtube.com/',
  };

  Map<String, dynamic> _musicBrowseBody(String browseId, {String? params}) => {
        'context': {
          'client': {
            'clientName': 'WEB_REMIX',
            'clientVersion': _kMusicClientVersion,
            'hl': 'en',
            'gl': 'US',
          },
        },
        'browseId': browseId,
        if (params != null) 'params': params,
      };

  /// Fetches an artist's complete songs and albums from the YouTube Music API.
  /// Uses the main artist browse page for top songs + carousel items, then
  /// follows every carousel's "See all" browse endpoint to get the full release
  /// list (albums, singles, EPs). Songs are supplemented via artist search.
  Future<({List<Song> songs, List<Album> albums})> getArtistPage(
      String browseId, String artistName) async {
    try {
      final response = await _httpClient
          .post(
            Uri.parse(_kMusicBrowseUrl),
            headers: _kMusicBrowseHeaders,
            body: jsonEncode(_musicBrowseBody(browseId)),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        return (songs: <Song>[], albums: <Album>[]);
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      final sections = _dig(data, [
        'contents', 'singleColumnBrowseResultsRenderer', 'tabs', 0,
        'tabRenderer', 'content', 'sectionListRenderer', 'contents',
      ]) as List?;

      if (sections == null) return (songs: <Song>[], albums: <Album>[]);

      final songs  = <Song>[];
      final albums = <Album>[];
      // "See all" endpoints: {browseId, params} pairs to fetch full lists
      final seeAllEndpoints = <Map<String, String>>[];

      for (final section in sections) {
        final map = section as Map;

        // Songs — musicShelfRenderer (typically top 5)
        final shelf = map['musicShelfRenderer'] as Map?;
        if (shelf != null) {
          for (final item in (shelf['contents'] as List? ?? [])) {
            final song = _parseMusicSong(item);
            if (song != null) songs.add(song);
          }
        }

        // Albums / Singles — musicCarouselShelfRenderer
        final carousel = map['musicCarouselShelfRenderer'] as Map?;
        if (carousel != null) {
          // Collect what's already visible in the carousel
          for (final item in (carousel['contents'] as List? ?? [])) {
            final album = _parseTwoRowAlbum(item, artistName: artistName);
            if (album != null) albums.add(album);
          }
          // Extract "See all" browse endpoint from the carousel header
          final ep = _dig(carousel, [
            'header', 'musicCarouselShelfBasicHeaderRenderer',
            'moreContentButton', 'buttonRenderer',
            'navigationEndpoint', 'browseEndpoint',
          ]) as Map?;
          final epBrowseId = ep?['browseId'] as String?;
          final epParams   = ep?['params'] as String?;
          if (epBrowseId != null && epParams != null) {
            seeAllEndpoints.add({'browseId': epBrowseId, 'params': epParams});
          }
        }
      }

      // Fetch complete release lists via "See all" endpoints (in parallel)
      if (seeAllEndpoints.isNotEmpty) {
        final futures = seeAllEndpoints.map(
          (ep) => _fetchArtistReleases(
              ep['browseId']!, ep['params']!, artistName),
        );
        for (final more in await Future.wait(futures)) {
          albums.addAll(more);
        }
      }

      // Supplement songs via artist-name search (gets far more than the 5
      // top songs shown on the browse page)
      final searchedSongs = await _searchMusicSongs(artistName);
      final seenSongIds = songs.map((s) => s.id).toSet();
      for (final s in searchedSongs) {
        if (seenSongIds.add(s.id)) songs.add(s);
      }

      // Deduplicate albums
      final seenAlbumIds = <String>{};
      final uniqueAlbums =
          albums.where((a) => seenAlbumIds.add(a.id)).toList();

      return (songs: songs, albums: uniqueAlbums);
    } catch (_) {
      return (songs: <Song>[], albums: <Album>[]);
    }
  }

  /// Fetches a complete release list from a "See all" artist browse endpoint.
  /// The response uses a gridRenderer containing musicTwoRowItemRenderer items.
  Future<List<Album>> _fetchArtistReleases(
      String browseId, String params, String artistName) async {
    try {
      final response = await _httpClient
          .post(
            Uri.parse(_kMusicBrowseUrl),
            headers: _kMusicBrowseHeaders,
            body: jsonEncode(_musicBrowseBody(browseId, params: params)),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      // "See all" pages use a gridRenderer for the items
      final items = (_dig(data, [
            'contents', 'singleColumnBrowseResultsRenderer', 'tabs', 0,
            'tabRenderer', 'content', 'sectionListRenderer', 'contents', 0,
            'gridRenderer', 'items',
          ]) ??
          _dig(data, [
            'contents', 'singleColumnBrowseResultsRenderer', 'tabs', 0,
            'tabRenderer', 'content', 'sectionListRenderer', 'contents', 0,
            'musicShelfRenderer', 'contents',
          ])) as List? ?? [];

      final albums = <Album>[];
      for (final item in items) {
        final album = _parseTwoRowAlbum(item, artistName: artistName);
        if (album != null) albums.add(album);
      }
      return albums;
    } catch (_) {
      return [];
    }
  }

  /// Parses a musicTwoRowItemRenderer (used in artist carousels) into an Album.
  Album? _parseTwoRowAlbum(dynamic raw, {String artistName = ''}) {
    final item = (raw as Map?)
        ?['musicTwoRowItemRenderer'] as Map<String, dynamic>?;
    if (item == null) return null;

    final browseId = _dig(item,
        ['navigationEndpoint', 'browseEndpoint', 'browseId']) as String?;
    if (browseId == null) return null;

    // Only accept albums/EPs/singles — skip artist/playlist items in carousels
    final pageType = _dig(item, [
      'navigationEndpoint', 'browseEndpoint',
      'browseEndpointContextSupportedConfigs',
      'browseEndpointContextMusicConfig', 'pageType',
    ]) as String?;
    if (pageType != null && !pageType.contains('ALBUM')) return null;

    final title = _dig(item, ['title', 'runs', 0, 'text']) as String?;
    if (title == null) return null;

    final subtitleRuns =
        (_dig(item, ['subtitle', 'runs']) as List?) ?? [];
    int year = DateTime.now().year;
    for (final run in subtitleRuns) {
      final text = ((run as Map)['text'] as String? ?? '').trim();
      final parsed = int.tryParse(text);
      if (parsed != null && parsed > 1900 && parsed <= DateTime.now().year) {
        year = parsed;
        break;
      }
    }

    final thumbs = _dig(item, [
      'thumbnailRenderer', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails',
    ]) as List?;
    final thumb = _upgradeThumb(
        thumbs?.isNotEmpty == true ? thumbs!.last['url'] as String? : null);

    return Album(
      id: browseId,
      title: title,
      artist: artistName,
      artistId: '',
      thumbnailUrl: thumb,
      year: year,
      songIds: [],
    );
  }

  Future<List<Album>> searchAlbums(String query) =>
      _searchAlbumsViaMusicApi(query);

  Future<List<Song>> getArtistSongs(String channelId) async {
    final songs = <Song>[];
    try {
      await for (final video in _yt.channels.getUploads(channelId)) {
        songs.add(_videoToSong(video));
        if (songs.length >= 30) break;
      }
    } catch (_) {}
    return songs;
  }

  Song _videoToSong(Video video) {
    return Song(
      id: video.id.value,
      title: video.title,
      artist: video.author,
      artistId: video.channelId.value,
      album: '',
      albumId: '',
      thumbnailUrl: _upgradeThumb(video.thumbnails.highResUrl),
      durationSeconds: video.duration?.inSeconds ?? 0,
    );
  }

  void dispose() {
    _yt.close();
    _httpClient.close();
  }
}
