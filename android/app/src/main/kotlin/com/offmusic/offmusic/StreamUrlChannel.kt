package com.offmusic.offmusic

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import okhttp3.OkHttpClient

private const val CHANNEL_NAME = "com.offmusic.offmusic/stream"

class StreamUrlChannel(channel: MethodChannel) {

    private val scope = CoroutineScope(Dispatchers.IO)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val okClient = OkHttpClient.Builder().build()

    init {
        // Delegate initialization to StreamResolver (shared with OffmusicPlayer)
        StreamResolver.init(okClient)

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getStreamUrl" -> {
                    val videoId = call.argument<String>("videoId")
                    if (videoId.isNullOrBlank()) {
                        result.error("INVALID_ARGS", "videoId is required", null)
                        return@setMethodCallHandler
                    }
                    scope.launch {
                        try {
                            val url = StreamResolver.resolve(videoId, okClient)
                            mainHandler.post { result.success(url) }
                        } catch (e: Exception) {
                            mainHandler.post {
                                result.error("STREAM_ERROR", e.message ?: "Unknown error", null)
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    companion object {
        const val NAME = CHANNEL_NAME
    }
}
