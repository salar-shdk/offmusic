@file:androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)

package com.offmusic.offmusic

import android.app.PendingIntent
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.core.net.toUri
import androidx.media3.common.Player
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.session.CommandButton
import androidx.media3.session.DefaultMediaNotificationProvider
import androidx.media3.session.LibraryResult
import androidx.media3.session.MediaLibraryService
import androidx.media3.session.MediaLibraryService.LibraryParams
import androidx.media3.session.MediaLibraryService.MediaLibrarySession
import androidx.media3.session.MediaSession
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionResult
import com.google.common.collect.ImmutableList
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture

/**
 * MediaLibraryService that drives both the standard media notification and
 * Android Auto's browse tree.
 *
 * Browse tree:
 *   root → [Home, Quick Picks, Playlists, Liked Songs]
 *   Home → [first-5 quick picks | playlists (folders) | categories (stations)]
 *   Quick Picks → all quick pick songs
 *   Playlists   → user playlists (folders) → songs
 *   Liked Songs → liked songs
 *
 * Lyrics: a CommandButton on the player screen toggles lyrics on/off.
 * When on, OffmusicPlayer.positionTicker updates ExoPlayer's subtitle field
 * with the current synced lyric line from AutoDataStore.lyricsWithTimestamps.
 */
class OffmusicService : MediaLibraryService() {

    private var session: MediaLibrarySession? = null

    companion object {
        @Volatile var sharedPlayer:  OffmusicPlayer?      = null
        @Volatile var sharedSession: MediaLibrarySession? = null

        // Browse node IDs
        const val ROOT_ID          = "root"
        const val NODE_HOME        = "node_home"
        const val NODE_QUICK       = "node_quick_picks"
        const val NODE_PLAYLISTS   = "node_playlists"
        const val NODE_LIKED       = "node_liked"
        const val PREFIX_PLAYLIST  = "playlist_"
        const val PREFIX_SONG      = "song_"
        const val PREFIX_CATEGORY  = "category_"
        const val PREFIX_SHUFFLE   = "shuffle_playlist_"

        // Custom action command
        const val CMD_TOGGLE_LYRICS = "com.offmusic.offmusic.TOGGLE_LYRICS"

        // Content-style hint constants (Android Auto browse UI)
        // https://developer.android.com/training/cars/media#default-content-style
        const val HINT_PLAYABLE  = "android.media.browse.CONTENT_STYLE_PLAYABLE_HINT"
        const val HINT_BROWSABLE = "android.media.browse.CONTENT_STYLE_BROWSABLE_HINT"
        const val HINT_GROUP     = "android.media.browse.CONTENT_STYLE_GROUP_TITLE_HINT"
        const val STYLE_LIST     = 1   // tall list row (songs, liked)
        const val STYLE_GRID     = 2   // square tile (playlists, categories)
    }

    override fun onCreate() {
        super.onCreate()
        tryCreateSession()
    }

    /**
     * Called every time startService() is invoked — including when PlayerBridge
     * sets sharedPlayer and starts the service after Android Auto already started
     * it (service was already running, onCreate skipped). Creates the session if
     * it hasn't been created yet.
     */
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val result = super.onStartCommand(intent, flags, startId)
        if (session == null) tryCreateSession()
        return result
    }

    private fun tryCreateSession() {
        if (session != null) return
        // Android Auto can start the service before Flutter creates PlayerBridge.
        // Create a player here so the session is always available for Auto.
        if (sharedPlayer == null) {
            sharedPlayer = OffmusicPlayer(applicationContext)
        }
        val player = sharedPlayer ?: return
        setMediaNotificationProvider(
            DefaultMediaNotificationProvider(this)
                .also { it.setSmallIcon(R.drawable.ic_notif_music) }
        )
        val activityIntent = packageManager.getLaunchIntentForPackage(packageName)
        val sessionActivity = if (activityIntent != null) {
            PendingIntent.getActivity(this, 0, activityIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        } else null
        val builder = MediaLibrarySession.Builder(this, player.routingPlayer, BrowseCallback())
            .setId("offmusic")
        if (sessionActivity != null) builder.setSessionActivity(sessionActivity)
        session = builder.build()
        sharedSession = session
        // Register with the base class so Media3 manages the phone-side
        // media notification. Without this call no notification is shown.
        session?.let { addSession(it) }
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaLibrarySession? = session

    override fun onTaskRemoved(rootIntent: Intent?) {
        val player = session?.player
        if (player == null || !player.isPlaying) {
            player?.stop()
            stopSelf()
        }
    }

    override fun onDestroy() {
        sharedSession = null
        session?.release()
        session = null
        super.onDestroy()
    }

    // ── Lyrics custom layout ───────────────────────────────────────────────

    private fun lyricsLayout(): List<CommandButton> {
        val showLyrics = AutoDataStore.showAutoLyrics
        return listOf(
            CommandButton.Builder()
                .setSessionCommand(SessionCommand(CMD_TOGGLE_LYRICS, Bundle.EMPTY))
                .setDisplayName(if (showLyrics) "Hide Lyrics" else "Lyrics")
                .setIconResId(R.drawable.ic_notif_music)
                .build()
        )
    }

    // ── Browse Callback ────────────────────────────────────────────────────

    inner class BrowseCallback : MediaLibrarySession.Callback {

        // Register the lyrics toggle command so Auto can use it.
        // The lyrics button is pushed to Auto via setCustomLayout only when
        // Auto connects, so the phone notification never shows the extra button.
        override fun onConnect(
            session: MediaSession,
            controller: MediaSession.ControllerInfo,
        ): MediaSession.ConnectionResult {
            val result = super.onConnect(session, controller)
            val commands = result.availableSessionCommands.buildUpon()
                .add(SessionCommand(CMD_TOGGLE_LYRICS, Bundle.EMPTY))
                .build()
            // Show the lyrics button in Android Auto but not in the phone notification
            if (isAutoController(controller)) {
                session.setCustomLayout(lyricsLayout())
                // Auto-resume playback if the user has the setting enabled
                if (AutoDataStore.autoPlayOnConnect) {
                    Handler(Looper.getMainLooper()).post { resumeForAuto() }
                }
            }
            return MediaSession.ConnectionResult.accept(commands, result.availablePlayerCommands)
        }

        override fun onCustomCommand(
            session: MediaSession,
            controller: MediaSession.ControllerInfo,
            customCommand: SessionCommand,
            args: Bundle,
        ): ListenableFuture<SessionResult> {
            if (customCommand.customAction == CMD_TOGGLE_LYRICS) {
                val wasShowing = AutoDataStore.showAutoLyrics
                AutoDataStore.showAutoLyrics = !wasShowing
                if (wasShowing) {
                    // Turning off: clear the subtitle field once
                    sharedPlayer?.clearSubtitle()
                }
                sharedPlayer?.resetLyricTracking()
                // Refresh the lyrics button label for Auto (setCustomLayout is
                // safe to call here — the phone notification ignores custom layout
                // because it was never set at session init time)
                if (sharedSession?.connectedControllers?.any { isAutoController(it) } == true) {
                    sharedSession?.setCustomLayout(lyricsLayout())
                }
                return Futures.immediateFuture(SessionResult(SessionResult.RESULT_SUCCESS))
            }
            return super.onCustomCommand(session, controller, customCommand, args)
        }

        override fun onGetLibraryRoot(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            params: LibraryParams?,
        ): ListenableFuture<LibraryResult<MediaItem>> =
            Futures.immediateFuture(
                LibraryResult.ofItem(buildFolder(ROOT_ID, "offmusic"), params)
            )

        override fun onGetChildren(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            parentId: String,
            page: Int,
            pageSize: Int,
            params: LibraryParams?,
        ): ListenableFuture<LibraryResult<ImmutableList<MediaItem>>> {
            val children = ImmutableList.copyOf(buildChildren(parentId))
            return Futures.immediateFuture(LibraryResult.ofItemList(children, params))
        }

        /**
         * Resolve media items before they reach ExoPlayer.
         *
         * Android Auto (via old MediaBrowserCompat protocol) may send items
         * with only a mediaId and no URI. We look the song up in AutoDataStore
         * and return it with the video-ID URI that ResolvingDataSource handles.
         *
         * For category items we expand to the full song list so ExoPlayer
         * gets a proper queue.
         */
        override fun onSetMediaItems(
            mediaSession: MediaSession,
            controller: MediaSession.ControllerInfo,
            mediaItems: List<MediaItem>,
            startIndex: Int,
            startPositionMs: Long,
        ): ListenableFuture<MediaSession.MediaItemsWithStartPosition> {
            val firstId = mediaItems.firstOrNull()?.mediaId ?: ""

            // Shuffle playlist: shuffle all songs in the playlist
            if (firstId.startsWith(PREFIX_SHUFFLE)) {
                val plId = firstId.removePrefix(PREFIX_SHUFFLE)
                val pl = AutoDataStore.playlists.find { it.id == plId }
                if (pl != null && pl.songs.isNotEmpty()) {
                    val shuffled = pl.songs.shuffled()
                    sharedPlayer?.sendAutoQueue(shuffled, 0)
                    return Futures.immediateFuture(
                        MediaSession.MediaItemsWithStartPosition(
                            shuffled.map(::buildSongItem), 0, C.TIME_UNSET)
                    )
                }
            }

            // Category station: expand to all songs in that category
            if (firstId.startsWith(PREFIX_CATEGORY)) {
                val catId = firstId.removePrefix(PREFIX_CATEGORY)
                val catSongs = AutoDataStore.categories.find { it.id == catId }?.songs
                if (!catSongs.isNullOrEmpty()) {
                    sharedPlayer?.sendAutoQueue(catSongs, 0)
                    return Futures.immediateFuture(
                        MediaSession.MediaItemsWithStartPosition(
                            catSongs.map(::buildSongItem), 0, C.TIME_UNSET)
                    )
                }
            }

            // Single song: expand to its full collection so Auto shows the whole
            // queue and Flutter gets the right song list immediately.
            if (mediaItems.size == 1) {
                val songId = firstId.removePrefix(PREFIX_SONG)

                AutoDataStore.quickPicks.indexOfFirst { it.id == songId }.let { idx ->
                    if (idx >= 0) {
                        sharedPlayer?.sendAutoQueue(AutoDataStore.quickPicks, idx)
                        return Futures.immediateFuture(
                            MediaSession.MediaItemsWithStartPosition(
                                AutoDataStore.quickPicks.map(::buildSongItem), idx, C.TIME_UNSET)
                        )
                    }
                }
                AutoDataStore.likedSongs.indexOfFirst { it.id == songId }.let { idx ->
                    if (idx >= 0) {
                        sharedPlayer?.sendAutoQueue(AutoDataStore.likedSongs, idx)
                        return Futures.immediateFuture(
                            MediaSession.MediaItemsWithStartPosition(
                                AutoDataStore.likedSongs.map(::buildSongItem), idx, C.TIME_UNSET)
                        )
                    }
                }
                for (pl in AutoDataStore.playlists) {
                    val idx = pl.songs.indexOfFirst { it.id == songId }
                    if (idx >= 0) {
                        sharedPlayer?.sendAutoQueue(pl.songs, idx)
                        return Futures.immediateFuture(
                            MediaSession.MediaItemsWithStartPosition(
                                pl.songs.map(::buildSongItem), idx, C.TIME_UNSET)
                        )
                    }
                }
            }

            // Fallback: resolve individual items
            val resolved = mediaItems.map { item -> resolveItem(item) }
            return Futures.immediateFuture(
                MediaSession.MediaItemsWithStartPosition(resolved, startIndex, startPositionMs)
            )
        }

        override fun onAddMediaItems(
            mediaSession: MediaSession,
            controller: MediaSession.ControllerInfo,
            mediaItems: List<MediaItem>,
        ): ListenableFuture<List<MediaItem>> =
            Futures.immediateFuture(mediaItems.map { resolveItem(it) })

        override fun onDisconnected(
            session: MediaSession,
            controller: MediaSession.ControllerInfo,
        ) {
            if (isAutoController(controller)) {
                Handler(Looper.getMainLooper()).post {
                    sharedPlayer?.pause()
                }
            }
        }

        private fun isAutoController(controller: MediaSession.ControllerInfo): Boolean {
            val pkg = controller.packageName
            return pkg == "com.google.android.projection.gearhead" ||
                   pkg.contains("gearhead") ||
                   pkg.contains("automotive")
        }
    }

    /**
     * Called on the main thread when Android Auto connects with auto-play enabled.
     * Resumes playback if ExoPlayer already has a media item loaded (e.g. the user
     * was listening before getting in the car). If the player has no media but
     * Quick Picks are available, starts the first one.
     */
    private fun resumeForAuto() {
        val player = sharedPlayer ?: return
        val exo = player.exoPlayer
        if (exo.mediaItemCount > 0) {
            // Re-prepare if idle (e.g. player was stopped), then play
            if (exo.playbackState == Player.STATE_IDLE) exo.prepare()
            exo.play()
        } else if (AutoDataStore.quickPicks.isNotEmpty()) {
            val song = AutoDataStore.quickPicks[0]
            player.play(song.id, title = song.title, artist = song.artist,
                thumbnailUrl = song.thumbnailUrl)
            player.sendAutoQueue(AutoDataStore.quickPicks, 0)
        }
    }

    // ── URI resolution ─────────────────────────────────────────────────────

    /**
     * If [item] already has a URI, return it unchanged.
     * Otherwise look it up in AutoDataStore by mediaId and return the full item.
     * Fallback: if not in AutoDataStore (e.g. Flutter hasn't pushed data yet),
     * use the stripped mediaId directly as a video ID URI so ResolvingDataSource
     * can still resolve the stream.
     */
    private fun resolveItem(item: MediaItem): MediaItem {
        if (item.localConfiguration?.uri != null) return item
        val songId = item.mediaId.removePrefix(PREFIX_SONG)
        val song = findSongById(songId)
        return if (song != null) {
            buildSongItem(song)
        } else {
            // Not in store yet — treat the ID as a raw video ID URI and let
            // ResolvingDataSource handle it (same path as Flutter-initiated play).
            item.buildUpon().setUri(songId.toUri()).build()
        }
    }

    private fun findSongById(songId: String): AutoDataStore.AutoSong? =
        AutoDataStore.quickPicks.find { it.id == songId }
            ?: AutoDataStore.likedSongs.find { it.id == songId }
            ?: AutoDataStore.playlists.flatMap { it.songs }.find { it.id == songId }
            ?: AutoDataStore.categories.flatMap { it.songs }.find { it.id == songId }

    // ── Browse tree builders ───────────────────────────────────────────────

    private fun buildChildren(parentId: String): List<MediaItem> = when {
        parentId == ROOT_ID -> listOf(
            buildFolder(NODE_HOME,      "Home"),
            buildFolder(NODE_QUICK,     "Quick Picks"),
            buildFolder(NODE_PLAYLISTS, "Playlists"),
            buildFolder(NODE_LIKED,     "Liked Songs"),
        )

        parentId == NODE_HOME      -> buildHomeChildren()

        // Quick Picks tab — all songs as list rows
        parentId == NODE_QUICK     ->
            AutoDataStore.quickPicks.map { buildSongItem(it) }

        // Liked Songs tab — list rows
        parentId == NODE_LIKED     ->
            AutoDataStore.likedSongs.map { buildSongItem(it) }

        // Playlists tab — square grid tiles
        parentId == NODE_PLAYLISTS ->
            AutoDataStore.playlists.map { pl ->
                buildFolder(PREFIX_PLAYLIST + pl.id, pl.name, style = STYLE_GRID)
            }

        parentId.startsWith(PREFIX_PLAYLIST) -> {
            val plId = parentId.removePrefix(PREFIX_PLAYLIST)
            val pl = AutoDataStore.playlists.find { it.id == plId }
            if (pl != null && pl.songs.isNotEmpty()) {
                listOf(buildShuffleItem(plId)) + pl.songs.map { buildSongItem(it) }
            } else emptyList()
        }

        else -> emptyList()
    }

    /**
     * Home page — three visually distinct sections separated by group-title
     * headers, matching the main app's layout:
     *
     *   [Quick Picks]   → list rows (songs)
     *   [Your Playlists] → square grid tiles (playlist folders)
     *   [Browse by Category] → square grid tiles (genre stations)
     */
    private fun buildHomeChildren(): List<MediaItem> {
        val items = mutableListOf<MediaItem>()

        // ── Section 1: Quick Picks (list style, first 10 songs) ───────────
        AutoDataStore.quickPicks.take(10).forEachIndexed { i, song ->
            items += buildSongItem(
                song,
                sectionTitle = if (i == 0) "Quick Picks" else null,
            )
        }

        // ── Section 2: Your Playlists (grid tiles) ────────────────────────
        if (AutoDataStore.playlists.isNotEmpty()) {
            AutoDataStore.playlists.forEachIndexed { i, pl ->
                items += buildFolder(
                    mediaId      = PREFIX_PLAYLIST + pl.id,
                    title        = pl.name,
                    style        = STYLE_GRID,
                    sectionTitle = if (i == 0) "Your Playlists" else null,
                )
            }
        }

        // ── Section 3: Browse by Category (grid tiles / genre stations) ───
        if (AutoDataStore.categories.isNotEmpty()) {
            AutoDataStore.categories.forEachIndexed { i, cat ->
                items += buildCategoryItem(
                    cat,
                    sectionTitle = if (i == 0) "Browse by Category" else null,
                )
            }
        }

        return items
    }

    private fun extras(
        playableStyle: Int? = null,
        browsableStyle: Int? = null,
        sectionTitle: String? = null,
    ): Bundle? {
        val b = Bundle()
        playableStyle?.let  { b.putInt(HINT_PLAYABLE, it) }
        browsableStyle?.let { b.putInt(HINT_BROWSABLE, it) }
        sectionTitle?.let   { b.putString(HINT_GROUP, it) }
        return if (b.isEmpty) null else b
    }

    private fun buildFolder(
        mediaId: String,
        title: String,
        style: Int = STYLE_LIST,
        sectionTitle: String? = null,
    ): MediaItem =
        MediaItem.Builder()
            .setMediaId(mediaId)
            .setMediaMetadata(
                MediaMetadata.Builder()
                    .setTitle(title)
                    .setIsPlayable(false)
                    .setIsBrowsable(true)
                    .setExtras(extras(browsableStyle = style, sectionTitle = sectionTitle))
                    .build()
            )
            .build()

    private fun buildSongItem(
        song: AutoDataStore.AutoSong,
        sectionTitle: String? = null,
    ): MediaItem =
        MediaItem.Builder()
            .setMediaId(PREFIX_SONG + song.id)
            .setUri(song.id.toUri()) // ResolvingDataSource converts video ID → stream URL
            .setMediaMetadata(
                MediaMetadata.Builder()
                    .setTitle(song.title)
                    .setArtist(song.artist)
                    .setArtworkUri(song.thumbnailUrl.takeIf { it.isNotBlank() }?.toUri())
                    .setIsPlayable(true)
                    .setIsBrowsable(false)
                    .setExtras(extras(playableStyle = STYLE_LIST, sectionTitle = sectionTitle))
                    .build()
            )
            .build()

    /** Category station — tapping plays all songs in the category. */
    private fun buildCategoryItem(
        cat: AutoDataStore.AutoCategory,
        sectionTitle: String? = null,
    ): MediaItem =
        MediaItem.Builder()
            .setMediaId(PREFIX_CATEGORY + cat.id)
            .setMediaMetadata(
                MediaMetadata.Builder()
                    .setTitle(cat.name)
                    .setIsPlayable(true)
                    .setIsBrowsable(false)
                    .setExtras(extras(playableStyle = STYLE_GRID, sectionTitle = sectionTitle))
                    .build()
            )
            .build()

    /** Shuffle button shown at the top of a playlist's song list in Android Auto. */
    private fun buildShuffleItem(playlistId: String): MediaItem =
        MediaItem.Builder()
            .setMediaId(PREFIX_SHUFFLE + playlistId)
            .setMediaMetadata(
                MediaMetadata.Builder()
                    .setTitle("Shuffle All")
                    .setIsPlayable(true)
                    .setIsBrowsable(false)
                    .setExtras(extras(playableStyle = STYLE_LIST))
                    .build()
            )
            .build()
}
