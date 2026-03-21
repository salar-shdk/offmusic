package com.offmusic.offmusic

import com.grack.nanojson.JsonWriter
import okhttp3.OkHttpClient
import org.json.JSONObject
import org.schabi.newpipe.extractor.NewPipe
import org.schabi.newpipe.extractor.localization.ContentCountry
import org.schabi.newpipe.extractor.localization.Localization
import org.schabi.newpipe.extractor.services.youtube.YoutubeJavaScriptPlayerManager
import org.schabi.newpipe.extractor.services.youtube.YoutubeStreamHelper

/**
 * Resolves a YouTube video ID → playable stream URL.
 * Mirrors Kreate's makeStreamCache() + resolver() in PlayerModule.kt:
 *   1. InnerTube ANDROID player request via NewPipeExtractor
 *   2. Fallback to IOS player request
 *   3. n-parameter deobfuscation via YoutubeJavaScriptPlayerManager
 *
 * MUST be called on a background thread.
 */
object StreamResolver {

    @Volatile private var initialized = false

    fun init(client: OkHttpClient) {
        if (initialized) return
        synchronized(this) {
            if (initialized) return
            NewPipe.init(NewPipeDownloaderImpl(client))
            initialized = true
        }
    }

    fun resolve(videoId: String, client: OkHttpClient): String {
        init(client)

        val cpn = buildString {
            val chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
            repeat(16) { append(chars.random()) }
        }
        val gl = ContentCountry("US")
        val hl = Localization("en")

        // Try ANDROID client, fall back to IOS — same as Kreate
        val jsonResponse = try {
            YoutubeStreamHelper.getAndroidReelPlayerResponse(gl, hl, videoId, cpn)
        } catch (e: Exception) {
            YoutubeStreamHelper.getIosPlayerResponse(gl, hl, videoId, cpn, null)
        }

        val json = JSONObject(JsonWriter.string(jsonResponse))
        val playStatus = json.optJSONObject("playabilityStatus")
        val status = playStatus?.optString("status") ?: "ERROR"
        if (status != "OK") {
            throw Exception("${playStatus?.optString("reason") ?: status}")
        }

        val formats = json.optJSONObject("streamingData")
            ?.optJSONArray("adaptiveFormats")
            ?: throw Exception("No adaptiveFormats")

        // Prefer audio/mp4 (AAC) — universally supported on Android
        var bestMp4: JSONObject? = null
        var bestWebm: JSONObject? = null
        for (i in 0 until formats.length()) {
            val fmt = formats.optJSONObject(i) ?: continue
            val mime = fmt.optString("mimeType")
            if (!mime.startsWith("audio/")) continue
            val url = fmt.optString("url").takeIf { it.isNotEmpty() } ?: continue
            val bitrate = fmt.optLong("bitrate")
            if (mime.contains("mp4")) {
                if (bestMp4 == null || bitrate > bestMp4!!.optLong("bitrate")) bestMp4 = fmt
            } else {
                if (bestWebm == null || bitrate > bestWebm!!.optLong("bitrate")) bestWebm = fmt
            }
        }

        val rawUrl = (bestMp4 ?: bestWebm)?.optString("url")
            ?: throw Exception("No direct-URL audio format found")

        // Deobfuscate the n-parameter — the critical step Kreate does to
        // prevent YouTube CDN from aborting/throttling the connection.
        return try {
            YoutubeJavaScriptPlayerManager
                .getUrlWithThrottlingParameterDeobfuscated(videoId, rawUrl)
        } catch (e: Exception) {
            rawUrl  // Fall back to raw URL if JS deobfuscation fails
        }
    }
}
