<p align="center">
  <img width="300" height="300" alt="off_music_icon" src="https://github.com/user-attachments/assets/fb71d5b6-71ac-4e72-9950-ab05ef5f6465" />
</p>
<h1 align="center">offmusic</h1>

<p align="center">
  <a href="https://buymeacoffee.com/salar_shdk">
    <img src="https://img.shields.io/badge/Buy%20me%20a%20coffee-☕-yellow" alt="Buy Me a Coffee">
  </a>
  <img src="https://img.shields.io/badge/version-1.0.0-blue" alt="Version">
</p>


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
<img src="https://github.com/user-attachments/assets/e7282e03-e907-4b67-b0fe-2d367be12a6a" alt="photo_1" width="228" height="640">
<img src="https://github.com/user-attachments/assets/78302a04-6711-4369-a3fa-64af6765614a" alt="photo_2" width="228" height="640">
<img src="https://github.com/user-attachments/assets/a8255f57-76af-45e5-b76d-284957a80188" alt="photo_3" width="228" height="640">
<img src="https://github.com/user-attachments/assets/c93599e5-9833-49db-a709-91de92b1256e" alt="photo_4" width="228" height="640">
<img src="https://github.com/user-attachments/assets/ae4e4811-acd5-49d0-a50d-ca5c863dcb03" alt="photo_5" width="228" height="640">
<img src="https://github.com/user-attachments/assets/8467f1cf-c7e0-49a0-97a6-bad2682282a7" alt="photo_6" width="228" height="640">
<img src="https://github.com/user-attachments/assets/e1fd22dc-ccc0-412a-bb5d-a29a9a40e363" alt="photo_7" width="228" height="640">
<img src="https://github.com/user-attachments/assets/b91e5eb7-2516-425c-b3f2-4aaed2a2719d" alt="photo_8" width="228" height="640">

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
