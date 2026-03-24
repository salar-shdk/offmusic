import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/search_provider.dart';
import '../models/artist.dart';
import '../widgets/song_tile.dart';
import '../widgets/album_card.dart';
import '../widgets/artist_card.dart';
import 'album_screen.dart';
import 'artist_screen.dart';

class SearchScreen extends StatefulWidget {
  final FocusNode? externalFocusNode;

  const SearchScreen({super.key, this.externalFocusNode});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  late FocusNode _focusNode;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.externalFocusNode ?? FocusNode();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        context.read<SearchProvider>().setActiveTab(
              SearchTab.values[_tabController.index],
            );
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    if (widget.externalFocusNode == null) _focusNode.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _onSearch(String query) {
    context.read<SearchProvider>().search(query);
  }

  @override
  Widget build(BuildContext context) {
    final search = context.watch<SearchProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          focusNode: _focusNode,
          autofocus: true,
          onChanged: _onSearch,
          onSubmitted: _onSearch,
          decoration: InputDecoration(
            hintText: 'Search songs, albums, artists...',
            hintStyle: theme.textTheme.bodyLarge?.copyWith(color: Colors.white38),
            border: InputBorder.none,
            suffixIcon: _controller.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    onPressed: () {
                      _controller.clear();
                      context.read<SearchProvider>().clear();
                    },
                  )
                : null,
          ),
          style: theme.textTheme.bodyLarge,
        ),
        bottom: search.hasResults
            ? TabBar(
                controller: _tabController,
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.music_note_rounded, size: 16),
                        const SizedBox(width: 4),
                        Text('Songs (${search.songs.length})'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.album_rounded, size: 16),
                        const SizedBox(width: 4),
                        Text('Albums (${search.albums.length})'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.person_rounded, size: 16),
                        const SizedBox(width: 4),
                        Text('Artists (${search.artists.length})'),
                      ],
                    ),
                  ),
                ],
                indicatorColor: theme.colorScheme.primary,
                labelColor: theme.colorScheme.primary,
                unselectedLabelColor: Colors.white54,
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              )
            : null,
      ),
      body: _buildBody(search, theme),
    );
  }

  Widget _buildBody(SearchProvider search, ThemeData theme) {
    if (search.isLoading) {
      return Center(
        child: CircularProgressIndicator(color: theme.colorScheme.primary),
      );
    }

    if (search.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.white24),
            const SizedBox(height: 16),
            Text(search.error!, style: theme.textTheme.bodyMedium),
          ],
        ),
      );
    }

    if (!search.hasResults && search.lastQuery.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded, size: 48, color: Colors.white24),
            const SizedBox(height: 16),
            Text('No results for "${search.lastQuery}"',
                style: theme.textTheme.bodyMedium),
          ],
        ),
      );
    }

    if (!search.hasResults) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_rounded,
                size: 64, color: Colors.white.withOpacity(0.1)),
            const SizedBox(height: 16),
            Text('Search for music', style: theme.textTheme.bodyMedium),
          ],
        ),
      );
    }

    return TabBarView(
      controller: _tabController,
      children: [
        _SongsTab(songs: search.songs),
        _AlbumsTab(albums: search.albums),
        _ArtistsTab(artists: search.artists),
      ],
    );
  }
}

class _SongsTab extends StatefulWidget {
  final List songs;

  const _SongsTab({required this.songs});

  @override
  State<_SongsTab> createState() => _SongsTabState();
}

class _SongsTabState extends State<_SongsTab> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 300) {
      context.read<SearchProvider>().loadMoreSongs();
    }
  }

  @override
  Widget build(BuildContext context) {
    final search = context.watch<SearchProvider>();
    final songs = widget.songs;

    if (songs.isEmpty) {
      return const Center(child: Text('No songs found'));
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: songs.length + (search.isLoadingMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == songs.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return SongTile(
          song: songs[i],
          queue: List.from(songs),
          index: i,
        );
      },
    );
  }

}

class _AlbumsTab extends StatelessWidget {
  final List albums;

  const _AlbumsTab({required this.albums});

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty) {
      return const Center(child: Text('No albums found'));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.75,
      ),
      itemCount: albums.length,
      itemBuilder: (context, i) {
        final album = albums[i];
        return AlbumCard(
          album: album,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AlbumScreen(album: album),
            ),
          ),
        );
      },
    );
  }
}

class _ArtistsTab extends StatelessWidget {
  final List<Artist> artists;

  const _ArtistsTab({required this.artists});

  @override
  Widget build(BuildContext context) {
    if (artists.isEmpty) {
      return const Center(child: Text('No artists found'));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 24,
        crossAxisSpacing: 16,
        childAspectRatio: 0.7,
      ),
      itemCount: artists.length,
      itemBuilder: (context, i) {
        final artist = artists[i];
        return ArtistCard(
          artist: artist,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ArtistScreen(artist: artist)),
          ),
        );
      },
    );
  }
}
