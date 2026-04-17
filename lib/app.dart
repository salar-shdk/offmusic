import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'screens/now_playing_screen.dart';
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
          create: (_) => HomeProvider(HomeService(), _db, _audioService, _youtube),
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
  static const _linkChannel = MethodChannel('com.offmusic.offmusic/links');

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
    _initLinkHandling();
  }

  void _initLinkHandling() {
    // Handle links arriving while the app is already running
    _linkChannel.setMethodCallHandler((call) async {
      if (call.method == 'onLink') _handleLink(call.arguments as String?);
    });
    // Handle cold-start link (app opened via a shared link)
    _linkChannel.invokeMethod<String>('getInitialLink').then((url) {
      if (url != null) _handleLink(url);
    });
  }

  Future<void> _handleLink(String? url) async {
    if (url == null || !mounted) return;
    final videoId = _extractVideoId(url);
    if (videoId == null) return;

    final youtube = context.read<YouTubeService>();
    final player = context.read<PlayerProvider>();

    final song = await youtube.getVideoDetails(videoId);
    if (song == null || !mounted) return;

    await player.playSong(song);
    if (mounted) openNowPlaying(context);
  }

  /// Extracts the video ID from a YouTube Music URL or shared text containing one.
  /// Supports: https://music.youtube.com/watch?v=VIDEO_ID
  String? _extractVideoId(String text) {
    try {
      // Find the YTM URL within any shared text (e.g. "Check this out https://...")
      final match = RegExp(r'music\.youtube\.com/watch\?[^\s]+').firstMatch(text);
      if (match == null) return null;
      final uri = Uri.parse('https://${match.group(0)}');
      return uri.queryParameters['v'];
    } catch (_) {
      return null;
    }
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
