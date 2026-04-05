package com.offmusic.offmusic

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges Flutter ↔ OffmusicPlayer via MethodChannel + EventChannel.
 * Starts [OffmusicService] (a MediaLibraryService) so Media3 manages
 * the media notification and Android Auto browse automatically.
 */
class PlayerBridge(
    context: Context,
    methodChannel: MethodChannel,
    eventChannel: EventChannel,
) {
    private val appContext = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null

    // Reuse the existing player if the service is already running (e.g. app
    // was reopened while music was playing in the background). Creating a new
    // player would leave the old ExoPlayer running and cause dual playback.
    private val player: OffmusicPlayer = OffmusicService.sharedPlayer
        ?: OffmusicPlayer(appContext)

    init {
        // Only register the player and start the service if it isn't already
        // running. If the service is live, it already has a MediaSession
        // pointing at this same player instance.
        if (OffmusicService.sharedPlayer == null) {
            OffmusicService.sharedPlayer = player
            appContext.startService(Intent(appContext, OffmusicService::class.java))
        }

        // Forward all player state changes to Flutter via the event channel.
        player.onStateChange = { state ->
            mainHandler.post { eventSink?.success(state) }
        }

        // Notification prev/next taps are intercepted by ForwardingPlayer and
        // routed back to Flutter as command events, so Flutter's queue logic handles them.
        player.onSkipNext = {
            mainHandler.post { eventSink?.success(mapOf("command" to "skipNext")) }
        }
        player.onSkipPrev = {
            mainHandler.post { eventSink?.success(mapOf("command" to "skipPrev")) }
        }

        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                eventSink = events
            }
            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })

        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "play" -> {
                    val videoId = call.argument<String>("videoId")
                    if (videoId.isNullOrBlank()) {
                        result.error("INVALID", "videoId required", null)
                    } else {
                        val filePath     = call.argument<String>("filePath")
                        val title        = call.argument<String>("title") ?: ""
                        val artist       = call.argument<String>("artist") ?: ""
                        val thumbnailUrl = call.argument<String>("thumbnailUrl") ?: ""
                        player.play(videoId, filePath, title, artist, thumbnailUrl)
                        result.success(null)
                    }
                }
                "pause"  -> { player.pause();  result.success(null) }
                "resume" -> { player.resume(); result.success(null) }
                "stop"   -> { player.stop();   result.success(null) }
                "seek"   -> {
                    val ms = (call.argument<Number>("positionMs"))?.toLong() ?: 0L
                    player.seek(ms)
                    result.success(null)
                }
                "downloadAudio" -> {
                    val videoId  = call.argument<String>("videoId")
                    val destPath = call.argument<String>("destPath")
                    if (videoId.isNullOrBlank() || destPath.isNullOrBlank()) {
                        result.error("INVALID", "videoId and destPath required", null)
                    } else {
                        Thread {
                            try {
                                player.downloadAudio(videoId, destPath)
                                mainHandler.post { result.success(null) }
                            } catch (e: Exception) {
                                mainHandler.post { result.error("DOWNLOAD_FAILED", e.message, null) }
                            }
                        }.start()
                    }
                }

                // ── Android Auto browse data ───────────────────────────────
                "auto_setQuickPicks" -> {
                    AutoDataStore.quickPicks = parseAutoSongs(call.argument("songs"))
                    notifyAutoChildren(OffmusicService.NODE_QUICK)
                    result.success(null)
                }
                "auto_setLikedSongs" -> {
                    AutoDataStore.likedSongs = parseAutoSongs(call.argument("songs"))
                    notifyAutoChildren(OffmusicService.NODE_LIKED)
                    result.success(null)
                }
                "auto_setPlaylists" -> {
                    val raw = call.argument<List<Map<String, Any?>>>("playlists") ?: emptyList()
                    AutoDataStore.playlists = raw.map { pl ->
                        AutoDataStore.AutoPlaylist(
                            id    = pl["id"]   as? String ?: "",
                            name  = pl["name"] as? String ?: "",
                            songs = parseAutoSongs(
                                @Suppress("UNCHECKED_CAST")
                                pl["songs"] as? List<Map<String, Any?>>
                            ),
                        )
                    }
                    notifyAutoChildren(OffmusicService.NODE_PLAYLISTS)
                    result.success(null)
                }
                "auto_setLyrics" -> {
                    val raw = call.argument<List<Map<String, Any?>>>("lines") ?: emptyList()
                    AutoDataStore.lyricsWithTimestamps = raw.map { l ->
                        AutoDataStore.LyricLine(
                            timestampMs = (l["ms"] as? Number)?.toLong() ?: 0L,
                            text        = l["text"] as? String ?: "",
                        )
                    }
                    result.success(null)
                }
                "auto_setCategories" -> {
                    val rawCats = call.argument<List<Map<String, Any?>>>("categories") ?: emptyList()
                    AutoDataStore.categories = rawCats.map { c ->
                        AutoDataStore.AutoCategory(
                            id    = c["id"]   as? String ?: "",
                            name  = c["name"] as? String ?: "",
                            songs = parseAutoSongs(
                                @Suppress("UNCHECKED_CAST")
                                c["songs"] as? List<Map<String, Any?>>
                            ),
                        )
                    }
                    notifyAutoChildren(OffmusicService.NODE_HOME)
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun parseAutoSongs(raw: List<Map<String, Any?>>?): List<AutoDataStore.AutoSong> =
        raw?.map { m ->
            AutoDataStore.AutoSong(
                id           = m["id"]           as? String ?: "",
                title        = m["title"]        as? String ?: "",
                artist       = m["artist"]       as? String ?: "",
                thumbnailUrl = m["thumbnailUrl"] as? String ?: "",
            )
        } ?: emptyList()

    /** Push a child-changed notification to all connected Auto browsers. */
    private fun notifyAutoChildren(parentId: String) {
        val sess = OffmusicService.sharedSession ?: return
        for (controller in sess.connectedControllers) {
            sess.notifyChildrenChanged(controller, parentId, Int.MAX_VALUE, null)
        }
    }

    companion object {
        const val METHOD_CHANNEL = "com.offmusic.offmusic/player"
        const val EVENT_CHANNEL  = "com.offmusic.offmusic/player_events"
    }
}
