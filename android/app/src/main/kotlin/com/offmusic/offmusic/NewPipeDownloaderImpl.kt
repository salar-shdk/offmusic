package com.offmusic.offmusic

import okhttp3.OkHttpClient
import okhttp3.RequestBody.Companion.toRequestBody
import org.schabi.newpipe.extractor.downloader.Downloader
import org.schabi.newpipe.extractor.downloader.Request
import org.schabi.newpipe.extractor.downloader.Response
import org.schabi.newpipe.extractor.exceptions.ReCaptchaException
import java.io.IOException

private const val USER_AGENT =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) " +
    "AppleWebKit/537.36 (KHTML, like Gecko) " +
    "Chrome/128.0.0.0 Safari/537.36"

class NewPipeDownloaderImpl(private val client: OkHttpClient) : Downloader() {

    @Throws(IOException::class, ReCaptchaException::class)
    override fun execute(request: Request): Response {
        val builder = okhttp3.Request.Builder()
            .method(request.httpMethod(), request.dataToSend()?.toRequestBody())
            .url(request.url())
            .header("User-Agent", USER_AGENT)

        request.headers().forEach { (name, values) ->
            if (values.size == 1) {
                builder.header(name, values[0])
            } else {
                builder.removeHeader(name)
                values.forEach { builder.addHeader(name, it) }
            }
        }

        val response = client.newCall(builder.build()).execute()
        if (response.code == 429) {
            response.close()
            throw ReCaptchaException("Rate limited", request.url())
        }
        val body = response.body?.string() ?: ""
        val latestUrl = response.request.url.toString()
        return Response(
            response.code,
            response.message,
            response.headers.toMultimap(),
            body,
            latestUrl
        )
    }
}
