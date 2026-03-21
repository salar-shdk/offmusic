import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../services/home_service.dart';
import '../widgets/song_tile.dart';
import 'now_playing_screen.dart';

class CategoryScreen extends StatefulWidget {
  final String title;
  final String query;

  const CategoryScreen({super.key, required this.title, required this.query});

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  final _songs = <Song>[];
  String? _continuation;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;

  late final ScrollController _scroll;
  late final HomeService _service;

  @override
  void initState() {
    super.initState();
    _service = HomeService();
    _scroll = ScrollController()..addListener(_onScroll);
    _loadFirst();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _service.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200 &&
        !_loadingMore &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _loadFirst() async {
    setState(() => _loading = true);
    final result = await _service.getCategorySongs(widget.query);
    if (mounted) {
      setState(() {
        _songs.addAll(result.songs);
        _continuation = result.continuation;
        _hasMore = result.continuation != null;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_continuation == null) return;
    setState(() => _loadingMore = true);
    final result = await _service.getCategorySongsContinuation(_continuation!);
    if (mounted) {
      setState(() {
        _songs.addAll(result.songs);
        _continuation = result.continuation;
        _hasMore = result.continuation != null;
        _loadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (_songs.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.shuffle_rounded),
              tooltip: 'Shuffle all',
              onPressed: () {
                final shuffled = List<Song>.from(_songs)..shuffle();
                context.read<PlayerProvider>().playSong(
                      shuffled.first,
                      queue: shuffled,
                      index: 0,
                    );
                openNowPlaying(context);
              },
            ),
          if (_songs.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.play_arrow_rounded),
              tooltip: 'Play all',
              onPressed: () {
                context.read<PlayerProvider>().playSong(
                      _songs.first,
                      queue: List.from(_songs),
                      index: 0,
                    );
                openNowPlaying(context);
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _songs.isEmpty
              ? Center(
                  child: Text(
                    'No songs found',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: Colors.white38),
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.only(bottom: 100),
                  itemCount: _songs.length + (_loadingMore ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i == _songs.length) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    return SongTile(
                      song: _songs[i],
                      queue: List.from(_songs),
                      index: i,
                    );
                  },
                ),
    );
  }
}
