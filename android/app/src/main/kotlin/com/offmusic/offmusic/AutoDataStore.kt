package com.offmusic.offmusic

/**
 * In-process singleton holding browse-tree data pushed from Flutter via
 * PlayerBridge. Both PlayerBridge (writer) and OffmusicService (reader)
 * share this without any IPC overhead.
 */
object AutoDataStore {

    data class AutoSong(
        val id: String,
        val title: String,
        val artist: String,
        val thumbnailUrl: String,
    )

    data class AutoPlaylist(
        val id: String,
        val name: String,
        val songs: List<AutoSong>,
    )

    data class AutoCategory(
        val id: String,
        val name: String,
        val songs: List<AutoSong>,
    )

    data class LyricLine(
        val timestampMs: Long,
        val text: String,
    )

    @Volatile var quickPicks:           List<AutoSong>     = emptyList()
    @Volatile var likedSongs:           List<AutoSong>     = emptyList()
    @Volatile var playlists:            List<AutoPlaylist> = emptyList()
    @Volatile var categories:           List<AutoCategory> = emptyList()
    @Volatile var lyricsWithTimestamps: List<LyricLine>    = emptyList()
    @Volatile var showAutoLyrics:       Boolean            = false
}
