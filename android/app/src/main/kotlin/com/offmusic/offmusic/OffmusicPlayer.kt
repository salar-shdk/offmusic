@file:androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)

package com.offmusic.offmusic

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.core.net.toUri
import java.io.File
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.ForwardingPlayer
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.ResolvingDataSource
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import okhttp3.OkHttpClient

private const val CHROME_UA =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) " +
    "AppleWebKit/537.36 (KHTML, like Gecko) " +
    "Chrome/128.0.0.0 Safari/537.36"

// Same chunk size as Kreate's PlayerModule.kt
private const val CHUNK_LENGTH = 512 * 1024L

/**
 * Native ExoPlayer instance configured identically to Kreate's PlayerModule:
 * - OkHttpDataSource with Chrome User-Agent
 * - ResolvingDataSource: video ID → deobfuscated YouTube stream URL
 * - 512 KB chunked range requests (same as Kreate)
 */
class OffmusicPlayer(private val context: Context) {

    private val mainHandler = Handler(Looper.getMainLooper())
    val okClient: OkHttpClient = OkHttpClient.Builder().build()

    var onStateChange: ((Map<String, Any?>) -> Unit)? = null
    var onSkipNext: (() -> Unit)? = null
    var onSkipPrev: (() -> Unit)? = null

    // Current song metadata — persists across Flutter engine restarts so Dart
    // can restore its state when the app is reopened while music is playing.
    var currentVideoId: String = ""
    var currentTitle: String = ""
    var currentArtist: String = ""
    var currentThumbnailUrl: String = ""

    private fun buildDataSourceFactory(): ResolvingDataSource.Factory {
        // OkHttpDataSource with Chrome UA — same as Kreate's OkHttpDataSource.Factory
        val okhttpFactory = OkHttpDataSource.Factory(okClient).setUserAgent(CHROME_UA)
        // DefaultDataSource wraps OkHttp for local file support
        val upstreamFactory = DefaultDataSource.Factory(context, okhttpFactory)

        return ResolvingDataSource.Factory(upstreamFactory) { dataSpec ->
            val songId = dataSpec.uri.toString()

            // Local files and already-resolved URLs pass through unchanged
            if (songId.startsWith("http") || songId.startsWith("content://") ||
                songId.startsWith("file://")) {
                return@Factory dataSpec
            }

            // songId is a YouTube video ID — resolve to a stream URL.
            // This runs on ExoPlayer's loading thread (background).
            val streamUrl = StreamResolver.resolve(songId, okClient)

            // Return modified DataSpec with real URL + 512 KB range limit,
            // identical to Kreate's resolver() in PlayerModule.kt line 386-388.
            dataSpec.withUri(streamUrl.toUri())
                .subrange(dataSpec.uriPositionOffset, CHUNK_LENGTH)
        }
    }

    val exoPlayer: ExoPlayer = ExoPlayer.Builder(context)
        .setMediaSourceFactory(DefaultMediaSourceFactory(buildDataSourceFactory()))
        .setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(C.USAGE_MEDIA)
                .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                .build(),
            /* handleAudioFocus= */ true,
        )
        .build()
        .also { player ->
            player.addListener(object : Player.Listener {
                override fun onIsPlayingChanged(isPlaying: Boolean) = emitState()
                override fun onPlaybackStateChanged(state: Int) {
                    emitState()
                    if (state == Player.STATE_ENDED) {
                        mainHandler.post {
                            onStateChange?.invoke(mapOf("command" to "songEnded"))
                        }
                    }
                }
                override fun onPositionDiscontinuity(
                    old: Player.PositionInfo,
                    new: Player.PositionInfo,
                    reason: Int,
                ) = emitState()
                override fun onPlayerError(error: PlaybackException) = emitError(error)

                /**
                 * Sync currentVideoId/title/artist when Android Auto (or any
                 * external controller) switches the media item without going
                 * through OffmusicPlayer.play(). This ensures Flutter's UI
                 * always reflects what's actually playing natively.
                 */
                override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
                    val item = mediaItem ?: return
                    // Strip the "song_" prefix that the Auto browse tree adds.
                    val newId = item.mediaId.removePrefix(OffmusicService.PREFIX_SONG)
                    if (newId.isBlank() || newId == currentVideoId) return
                    currentVideoId     = newId
                    currentTitle       = item.mediaMetadata.title?.toString() ?: newId
                    currentArtist      = item.mediaMetadata.artist?.toString() ?: ""
                    currentThumbnailUrl = item.mediaMetadata.artworkUri?.toString() ?: ""
                    lastLyricIdx       = -2
                    emitState()
                }
            })
        }

    /**
     * ForwardingPlayer that intercepts seekToNext/seekToPrevious and routes them
     * back to Flutter instead of advancing within a single-item ExoPlayer queue.
     * Always advertises next/prev as available so the notification shows both buttons.
     * Overrides both seekToNext/seekToNextMediaItem because Media3 may dispatch either
     * form, and hasNextMediaItem/hasPreviousMediaItem to prevent silent no-ops when
     * ExoPlayer's queue contains only one item.
     */
    val routingPlayer: ForwardingPlayer = object : ForwardingPlayer(exoPlayer) {
        override fun getAvailableCommands(): Player.Commands =
            super.getAvailableCommands().buildUpon()
                .add(Player.COMMAND_SEEK_TO_NEXT)
                .add(Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM)
                .add(Player.COMMAND_SEEK_TO_PREVIOUS)
                .add(Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM)
                .build()
        override fun hasNextMediaItem()     = true
        override fun hasPreviousMediaItem() = true
        override fun seekToNext()          { mainHandler.post { onSkipNext?.invoke() } }
        override fun seekToNextMediaItem() { mainHandler.post { onSkipNext?.invoke() } }
        override fun seekToPrevious()          { mainHandler.post { onSkipPrev?.invoke() } }
        override fun seekToPreviousMediaItem() { mainHandler.post { onSkipPrev?.invoke() } }
    }

    // Tracks which lyric line is currently shown in ExoPlayer's subtitle field.
    // -2 = not initialised, -1 = subtitle cleared (lyrics off or unavailable).
    private var lastLyricIdx: Int = -2

    /**
     * Called by OffmusicService when the user toggles lyrics via the custom
     * action button, so the next positionTicker tick forces a fresh update.
     */
    fun resetLyricTracking() = mainHandler.post { lastLyricIdx = -2 }

    /**
     * Update ExoPlayer's subtitle field with the current synced lyric line.
     *
     * IMPORTANT: replaceMediaItem is ONLY called when lyrics are visible and
     * the line has actually changed. Never called when lyrics are off, so
     * normal phone playback is never interrupted.
     */
    private fun updateLyricsSubtitle() {
        val lines = AutoDataStore.lyricsWithTimestamps
        if (!AutoDataStore.showAutoLyrics || lines.isEmpty()) {
            // Just reset the index tracker — do NOT touch ExoPlayer.
            lastLyricIdx = -1
            return
        }
        val pos = exoPlayer.currentPosition
        var idx = 0
        for (i in lines.indices) {
            if (lines[i].timestampMs <= pos) idx = i else break
        }
        if (idx == lastLyricIdx) return
        lastLyricIdx = idx
        setSubtitle(lines[idx].text)
    }

    /**
     * Replaces the current MediaItem's subtitle metadata without changing the
     * URI, so ExoPlayer does not reload the media source.
     * Only call this when lyrics are actively displayed.
     */
    private fun setSubtitle(text: String) {
        val i = exoPlayer.currentMediaItemIndex
        if (i < 0) return
        val item = exoPlayer.currentMediaItem ?: return
        val updated = item.buildUpon()
            .setMediaMetadata(item.mediaMetadata.buildUpon().setSubtitle(text).build())
            .build()
        exoPlayer.replaceMediaItem(i, updated)
    }

    /** Explicitly clears the subtitle (called once when lyrics are toggled off). */
    fun clearSubtitle() = mainHandler.post { setSubtitle("") }

    // Periodic position ticker — emits state every 500 ms while the player exists.
    private val positionTicker = object : Runnable {
        override fun run() {
            emitState()
            updateLyricsSubtitle()
            mainHandler.postDelayed(this, 500)
        }
    }

    init {
        mainHandler.postDelayed(positionTicker, 500)
    }

    /**
     * Play a song. Pass [videoId] for online streaming (native resolver handles URL),
     * or [filePath] for an already-cached local file.
     */
    fun play(
        videoId: String,
        filePath: String? = null,
        title: String = "",
        artist: String = "",
        thumbnailUrl: String = "",
    ) = mainHandler.post {
        val uri = if (!filePath.isNullOrBlank()) {
            Uri.fromFile(File(filePath))  // cached local file — bypasses resolver
        } else {
            videoId.toUri()               // video ID — resolver fetches & deobfuscates URL
        }
        currentVideoId = videoId
        currentTitle = title
        currentArtist = artist
        currentThumbnailUrl = thumbnailUrl
        lastLyricIdx = -2 // force lyric line re-evaluation on new song
        exoPlayer.setMediaItem(
            MediaItem.Builder()
                .setMediaId(videoId)
                .setUri(uri)
                .setCustomCacheKey(videoId)
                .setMediaMetadata(
                    MediaMetadata.Builder()
                        .setTitle(title.ifBlank { videoId })
                        .setArtist(artist)
                        .setArtworkUri(thumbnailUrl.toUri().takeIf { thumbnailUrl.isNotBlank() })
                        .build()
                )
                .build()
        )
        exoPlayer.prepare()
        exoPlayer.playWhenReady = true
    }

    /**
     * Sends the full collection queue to Flutter so its UI and queue logic
     * reflect the same list that ExoPlayer is playing in Android Auto.
     */
    fun sendAutoQueue(songs: List<AutoDataStore.AutoSong>, startIndex: Int) {
        val songsData = songs.map { s ->
            mapOf("id" to s.id, "title" to s.title, "artist" to s.artist,
                "thumbnailUrl" to s.thumbnailUrl)
        }
        mainHandler.post {
            onStateChange?.invoke(mapOf(
                "command"    to "autoQueue",
                "songs"      to songsData,
                "startIndex" to startIndex,
            ))
        }
    }

    fun pause()  = mainHandler.post { exoPlayer.pause() }
    fun resume() = mainHandler.post { exoPlayer.play() }
    fun seek(ms: Long) = mainHandler.post { exoPlayer.seekTo(ms) }
    fun stop()   = mainHandler.post { exoPlayer.stop() }

    /**
     * Download a song to [destPath] using parallel range requests (blocking — call from
     * background thread). YouTube CDN throttles single-connection downloads to playback speed,
     * so we use 6 concurrent range requests (like aria2c) to saturate the available bandwidth.
     */
    fun downloadAudio(videoId: String, destPath: String) {
        val url = StreamResolver.resolve(videoId, okClient)
        val dest = File(destPath)
        dest.parentFile?.mkdirs()

        // Probe for content length via a tiny range request.
        // YouTube CDN always returns Content-Range: bytes 0-0/TOTAL on a Range: bytes=0-0 request.
        val probeReq = okhttp3.Request.Builder()
            .url(url)
            .header("User-Agent", CHROME_UA)
            .header("Range", "bytes=0-0")
            .build()
        val contentLength: Long = try {
            okClient.newCall(probeReq).execute().use { res ->
                // Content-Range: bytes 0-0/1234567
                res.header("Content-Range")
                    ?.substringAfterLast('/')
                    ?.trim()
                    ?.toLongOrNull()
                    ?: res.header("Content-Length")?.toLongOrNull()
                    ?: -1L
            }
        } catch (_: Exception) { -1L }

        if (contentLength > 0) {
            // Parallel chunk download — 6 threads × 2 MB chunks
            val chunkSize = 2 * 1024 * 1024L
            val numChunks = ((contentLength + chunkSize - 1) / chunkSize).toInt()
            val parallelism = minOf(numChunks, 6)
            val executor = java.util.concurrent.Executors.newFixedThreadPool(parallelism)

            java.io.RandomAccessFile(dest, "rw").use { raf ->
                raf.setLength(contentLength)
                val channel = raf.channel
                val futures = (0 until numChunks).map { i ->
                    val start = i * chunkSize
                    val end = minOf(start + chunkSize - 1, contentLength - 1)
                    executor.submit<Unit> {
                        val req = okhttp3.Request.Builder()
                            .url(url)
                            .header("User-Agent", CHROME_UA)
                            .header("Range", "bytes=$start-$end")
                            .build()
                        okClient.newCall(req).execute().use { res ->
                            val bytes = res.body?.bytes()
                                ?: throw Exception("Empty chunk $i")
                            // FileChannel.write(buf, pos) is thread-safe for distinct positions
                            channel.write(java.nio.ByteBuffer.wrap(bytes), start)
                        }
                    }
                }
                try { futures.forEach { it.get() } }
                finally { executor.shutdown() }
            }
        } else {
            // Fallback: single-connection stream (e.g. if CDN doesn't advertise length)
            val req = okhttp3.Request.Builder()
                .url(url)
                .header("User-Agent", CHROME_UA)
                .build()
            okClient.newCall(req).execute().use { res ->
                val body = res.body ?: throw Exception("Empty response body")
                body.byteStream().use { input ->
                    dest.outputStream().use { out -> input.copyTo(out) }
                }
            }
        }
    }

    private fun emitState() {
        val dur = exoPlayer.duration.takeIf { it != C.TIME_UNSET } ?: 0L
        onStateChange?.invoke(mapOf(
            "isPlaying"    to exoPlayer.isPlaying,
            "isBuffering"  to (exoPlayer.playbackState == Player.STATE_BUFFERING),
            "isLoading"    to (exoPlayer.playbackState == Player.STATE_BUFFERING),
            "position"     to exoPlayer.currentPosition,
            "duration"     to dur,
            // Always include song metadata so Flutter can restore state when
            // the app is reopened while music is playing in the background.
            "videoId"      to currentVideoId,
            "title"        to currentTitle,
            "artist"       to currentArtist,
            "thumbnailUrl" to currentThumbnailUrl,
        ))
    }

    private fun emitError(error: PlaybackException) {
        onStateChange?.invoke(mapOf(
            "error"       to "ExoPlayer error ${error.errorCode}: ${error.message}",
            "isPlaying"   to false,
            "isLoading"   to false,
            "isBuffering" to false,
            "position"    to exoPlayer.currentPosition,
            "duration"    to 0L,
        ))
    }
}
