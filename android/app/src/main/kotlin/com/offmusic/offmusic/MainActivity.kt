package com.offmusic.offmusic

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onStart() {
        super.onStart()
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
    }
}
