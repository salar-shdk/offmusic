import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/song.dart';
import '../models/album.dart';
import '../models/artist.dart';
import '../services/youtube_service.dart';

enum SearchTab { songs, albums, artists }
enum SearchMode { youtubeMusic, youtube }

class SearchProvider extends ChangeNotifier {
  final YouTubeService _youtube;

  // YouTube Music results
  List<Song> _songs = [];
  List<Album> _albums = [];
  List<Artist> _artists = [];
  String? _songsContinuation;

  // YouTube results
  List<Song> _ytVideos = [];

  bool _isLoading = false;
  bool _isLoadingMore = false;
  String _lastQuery = '';
  String? _error;
  SearchTab _activeTab = SearchTab.songs;
  SearchMode _searchMode = SearchMode.youtubeMusic;

  // Debounce + cancellation
  Timer? _debounce;
  int _searchGeneration = 0;

  SearchProvider(this._youtube);

  List<Song> get songs => _songs;
  List<Album> get albums => _albums;
  List<Artist> get artists => _artists;
  List<Song> get ytVideos => _ytVideos;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMoreSongs => _songsContinuation != null;
  String get lastQuery => _lastQuery;
  String? get error => _error;
  SearchTab get activeTab => _activeTab;
  SearchMode get searchMode => _searchMode;
  bool get hasResults => _searchMode == SearchMode.youtube
      ? _ytVideos.isNotEmpty
      : _songs.isNotEmpty || _albums.isNotEmpty || _artists.isNotEmpty;

  void setActiveTab(SearchTab tab) {
    _activeTab = tab;
    notifyListeners();
  }

  void setSearchMode(SearchMode mode) {
    if (_searchMode == mode) return;
    _searchMode = mode;
    // Re-run the current query in the new mode
    if (_lastQuery.isNotEmpty) {
      search(_lastQuery);
    } else {
      notifyListeners();
    }
  }

  /// Called on every keystroke. Debounces 400 ms then fires the actual search.
  void search(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      clear();
      return;
    }
    _debounce?.cancel();
    if (!_isLoading) {
      _isLoading = true;
      _error = null;
      notifyListeners();
    }
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (_searchMode == SearchMode.youtube) {
        _runYouTubeSearch(trimmed);
      } else {
        _runSearch(trimmed);
      }
    });
  }

  Future<void> _runSearch(String query) async {
    final generation = ++_searchGeneration;
    _lastQuery = query;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final results = await _youtube.search(query);
      if (generation != _searchGeneration) return;
      _songs = results.songs;
      _albums = results.albums;
      _artists = results.artists;
      _songsContinuation = results.songsContinuation;
      _ytVideos = [];
    } catch (e) {
      if (generation != _searchGeneration) return;
      _error = 'Search failed. Check your connection.';
    } finally {
      if (generation == _searchGeneration) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _runYouTubeSearch(String query) async {
    final generation = ++_searchGeneration;
    _lastQuery = query;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final videos = await _youtube.searchYouTube(query);
      if (generation != _searchGeneration) return;
      _ytVideos = videos;
      _songs = [];
      _albums = [];
      _artists = [];
      _songsContinuation = null;
    } catch (e) {
      if (generation != _searchGeneration) return;
      _error = 'Search failed. Check your connection.';
    } finally {
      if (generation == _searchGeneration) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMoreSongs() async {
    final continuation = _songsContinuation;
    if (continuation == null || _isLoadingMore || _isLoading) return;
    _isLoadingMore = true;
    notifyListeners();
    try {
      final (moreSongs, nextContinuation) =
          await _youtube.loadMoreSongs(continuation);
      _songs = [..._songs, ...moreSongs];
      _songsContinuation = nextContinuation;
    } catch (_) {
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  void clear() {
    _debounce?.cancel();
    _searchGeneration++;
    _songs = [];
    _albums = [];
    _artists = [];
    _ytVideos = [];
    _lastQuery = '';
    _error = null;
    _isLoading = false;
    _isLoadingMore = false;
    _songsContinuation = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
