# offmusic

A free, open-source music streaming app for Android built with Flutter. Stream any song, build your library, and listen offline — no account required.

## Features

- **Stream anything** — search for songs, albums, and artists powered by YouTube Music
- **Home & Quick Picks** — personalized recommendations based on your listening history
- **Smart queue** — plays a song and automatically fills the queue with similar music; extends the queue as you approach the end
- **Offline / Downloads** — cache songs for playback without an internet connection
- **Library** — like songs, albums, and artists; create and manage playlists
- **Lyrics** — synced lyrics displayed on the Now Playing screen
- **Backup & Restore** — export your entire library to a JSON file and import it on any device
- **Auto-cleanup** — optionally delete cached audio that hasn't been played in N days
- **Background playback** — media notification with controls; resumes seamlessly when you reopen the app

## Screenshots

_Coming soon_

## Tech Stack

| Layer | Technology |
|---|---|
| UI | Flutter (Dart) |
| State management | Provider |
| Audio (Android) | ExoPlayer via custom Kotlin `OffmusicPlayer` |
| Music data | YouTube Music InnerTube API |
| Lyrics | `lrclib.net` |
| Local DB | SQLite via `sqflite` |
| Image loading | `cached_network_image` |
| HTTP | `dio` |

## Building

**Requirements**

- Flutter 3.x
- Android SDK (API 24+)
- A running Android emulator or physical device

**Steps**

```bash
git clone https://github.com/salar-shdk/offmusic.git
cd offmusic
flutter pub get
flutter run
```

To build a release APK:

```bash
flutter build apk --release
```

## Architecture

```
lib/
├── models/          # Song, Album, Artist, Playlist
├── services/        # YouTubeService, AudioPlayerService, CacheService, DatabaseService, LyricsService
├── providers/       # PlayerProvider, LibraryProvider, HomeProvider, SearchProvider
├── screens/         # HomeScreen, SearchScreen, LibraryScreen, AlbumScreen, ArtistScreen, SettingsScreen
├── widgets/         # MiniPlayer, SongTile, AlbumCard, ArtistCard, NowPlayingScreen
└── theme/           # AppTheme

android/app/src/main/kotlin/
└── com/offmusic/offmusic/
    ├── OffmusicPlayer.kt    # ExoPlayer wrapper
    ├── OffmusicService.kt   # Foreground service for background playback
    └── PlayerBridge.kt      # Flutter ↔ Kotlin method channel bridge
```

## Privacy

offmusic does not collect or transmit any personal data. All library data is stored locally on your device. Music is streamed directly from YouTube's servers.

## License

MIT — see [LICENSE](LICENSE)

---

Developed by [Amirsalar Darvishpour](https://github.com/salar-shdk)

[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20me%20a%20coffee-☕-yellow)](https://buymeacoffee.com/salar_shdk)
