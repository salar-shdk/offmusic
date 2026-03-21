import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/song.dart';
import '../models/album.dart';
import '../models/artist.dart';
import '../services/youtube_service.dart';

enum SearchTab { songs, albums, artists }

class SearchProvider extends ChangeNotifier {
  final YouTubeService _youtube;

  List<Song> _songs = [];
  List<Album> _albums = [];
  List<Artist> _artists = [];
  bool _isLoading = false;
  String _lastQuery = '';
  String? _error;
  SearchTab _activeTab = SearchTab.songs;

  // Debounce + cancellation
  Timer? _debounce;
  int _searchGeneration = 0; // incremented on each new search to discard stale results

  SearchProvider(this._youtube);

  List<Song> get songs => _songs;
  List<Album> get albums => _albums;
  List<Artist> get artists => _artists;
  bool get isLoading => _isLoading;
  String get lastQuery => _lastQuery;
  String? get error => _error;
  SearchTab get activeTab => _activeTab;
  bool get hasResults =>
      _songs.isNotEmpty || _albums.isNotEmpty || _artists.isNotEmpty;

  void setActiveTab(SearchTab tab) {
    _activeTab = tab;
    notifyListeners();
  }

  /// Called on every keystroke. Debounces 400 ms then fires the actual search.
  void search(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      clear();
      return;
    }
    // Cancel any pending debounce
    _debounce?.cancel();
    // Show loading immediately so the UI feels responsive
    if (!_isLoading) {
      _isLoading = true;
      _error = null;
      notifyListeners();
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _runSearch(trimmed));
  }

  Future<void> _runSearch(String query) async {
    // Each search gets a unique generation; we ignore results from older generations.
    final generation = ++_searchGeneration;
    _lastQuery = query;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final results = await _youtube.search(query);
      // Discard if a newer search has already started
      if (generation != _searchGeneration) return;
      _songs = results.songs;
      _albums = results.albums;
      _artists = results.artists;
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

  void clear() {
    _debounce?.cancel();
    _searchGeneration++;
    _songs = [];
    _albums = [];
    _artists = [];
    _lastQuery = '';
    _error = null;
    _isLoading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
