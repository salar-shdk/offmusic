import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/youtube_service.dart';
import 'services/audio_service.dart';
import 'services/cache_service.dart';
import 'services/database_service.dart';
import 'services/home_service.dart';
import 'services/lyrics_service.dart';
import 'providers/home_provider.dart';
import 'providers/player_provider.dart';
import 'providers/library_provider.dart';
import 'providers/search_provider.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';
import 'screens/search_screen.dart';
import 'screens/library_screen.dart';
import 'screens/settings_screen.dart';
import 'widgets/mini_player.dart';

class OffMusicApp extends StatefulWidget {
  const OffMusicApp({super.key});

  @override
  State<OffMusicApp> createState() => _OffMusicAppState();
}

class _OffMusicAppState extends State<OffMusicApp> {
  late final DatabaseService _db;
  late final CacheService _cache;
  late final YouTubeService _youtube;
  late final AudioPlayerService _audioService;
  late final LyricsService _lyrics;

  @override
  void initState() {
    super.initState();
    _db = DatabaseService();
    _cache = CacheService(_db);
    _youtube = YouTubeService();
    _audioService = AudioPlayerService(_db, _cache);
    _lyrics = LyricsService();
  }

  @override
  void dispose() {
    _audioService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<DatabaseService>.value(value: _db),
        Provider<YouTubeService>.value(value: _youtube),
        Provider<CacheService>.value(value: _cache),
        ChangeNotifierProvider(
          create: (_) => PlayerProvider(_audioService, _lyrics, _db),
        ),
        ChangeNotifierProvider(
          create: (_) => LibraryProvider(_db, _cache, _audioService),
        ),
        ChangeNotifierProvider(
          create: (_) => SearchProvider(_youtube),
        ),
        ChangeNotifierProvider(
          create: (_) => HomeProvider(HomeService(), _db, _audioService),
        ),
      ],
      child: MaterialApp(
        title: 'offmusic',
        theme: AppTheme.dark,
        debugShowCheckedModeBanner: false,
        home: const _RootScaffold(),
      ),
    );
  }
}

class _RootScaffold extends StatefulWidget {
  const _RootScaffold();

  @override
  State<_RootScaffold> createState() => _RootScaffoldState();
}

class _RootScaffoldState extends State<_RootScaffold> {
  int _selectedIndex = 0;
  final _searchFocusNode = FocusNode();

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      const HomeScreen(),
      SearchScreen(externalFocusNode: _searchFocusNode),
      const LibraryScreen(),
      const SettingsScreen(),
    ];
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onNavTap(int i) {
    setState(() => _selectedIndex = i);
    if (i == 1) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _searchFocusNode.requestFocus(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: _screens,
            ),
          ),
          const MiniPlayer(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onNavTap,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search_rounded),
            label: 'Search',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_music_outlined),
            selectedIcon: Icon(Icons.library_music_rounded),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
