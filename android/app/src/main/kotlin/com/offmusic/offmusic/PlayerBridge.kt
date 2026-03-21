package com.offmusic.offmusic

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges Flutter ↔ OffmusicPlayer via MethodChannel + EventChannel.
 * Starts [OffmusicService] (a MediaSessionService) so Media3 manages
 * the media notification automatically.
 */
class PlayerBridge(
    context: Context,
    methodChannel: MethodChannel,
    eventChannel: EventChannel,
) {
    private val appContext = context.applicationContext
    private val player = OffmusicPlayer(appContext)
    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null

    init {
        // Give the service a reference to the player so it can create a
        // MediaSession in onCreate(), then start the service.
        OffmusicService.sharedPlayer = player
        appContext.startService(Intent(appContext, OffmusicService::class.java))

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
                else -> result.notImplemented()
            }
        }
    }

    companion object {
        const val METHOD_CHANNEL = "com.offmusic.offmusic/player"
        const val EVENT_CHANNEL  = "com.offmusic.offmusic/player_events"
    }
}
