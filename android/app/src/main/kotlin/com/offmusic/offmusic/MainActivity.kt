package com.offmusic.offmusic

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        const val LINK_CHANNEL = "com.offmusic.offmusic/links"
    }

    // Link from cold-start intent (before Flutter engine is ready)
    private var initialLink: String? = null
    private var linkChannel: MethodChannel? = null

    /** Extract a YouTube Music URL from any intent type we handle. */
    private fun youtubeMusicUrlFromIntent(intent: Intent?): String? {
        if (intent == null) return null
        return when (intent.action) {
            Intent.ACTION_VIEW -> intent.data?.toString()
            Intent.ACTION_SEND -> intent.getStringExtra(Intent.EXTRA_TEXT)
            else -> null
        }?.takeIf { it.contains("music.youtube.com") }
    }

    override fun onStart() {
        super.onStart()
        // Capture link from cold-start intent
        youtubeMusicUrlFromIntent(intent)?.let { initialLink = it }

        // Request POST_NOTIFICATIONS permission on Android 13+ (API 33+).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED
            ) {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    0
                )
            }
        }
    }

    // Called when app is already running and a new link arrives (singleTop)
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        youtubeMusicUrlFromIntent(intent)?.let { url ->
            linkChannel?.invokeMethod("onLink", url)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // Stream URL channel — for Dart-side fallback URL resolution
        StreamUrlChannel(MethodChannel(messenger, StreamUrlChannel.NAME))

        // Native ExoPlayer bridge — primary audio playback (identical to Kreate)
        PlayerBridge(
            applicationContext,
            MethodChannel(messenger, PlayerBridge.METHOD_CHANNEL),
            EventChannel(messenger, PlayerBridge.EVENT_CHANNEL),
        )

        // Link channel — delivers YouTube Music URLs to Flutter
        linkChannel = MethodChannel(messenger, LINK_CHANNEL).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialLink" -> {
                        result.success(initialLink)
                        initialLink = null
                    }
                    "openDefaultAppsSettings" -> {
                        // Opens the system "Open by default" screen for this app so the
                        // user can add music.youtube.com as a supported link with one tap.
                        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            Intent(
                                Settings.ACTION_APP_OPEN_BY_DEFAULT_SETTINGS,
                                Uri.parse("package:$packageName"),
                            )
                        } else {
                            // Android 11 and below: open general app details page
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.parse("package:$packageName")
                            }
                        }
                        startActivity(intent)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }
}
