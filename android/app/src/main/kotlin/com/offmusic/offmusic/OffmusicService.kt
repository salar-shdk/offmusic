@file:androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)

package com.offmusic.offmusic

import android.content.Intent
import androidx.media3.session.DefaultMediaNotificationProvider
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService

/**
 * MediaSessionService that integrates with Android's standard media notification system.
 *
 * Media3's DefaultMediaNotificationProvider automatically shows a persistent
 * notification with play/pause, prev, and next controls — including on the lock
 * screen and in the expanded notification shade — based entirely on the player's
 * live state and MediaItem.mediaMetadata (title, artist, artwork).
 *
 * No manual BroadcastReceiver or notification building needed.
 *
 * [PlayerBridge] sets [sharedPlayer] before starting the service so that
 * onCreate() can create the MediaSession with the correct player instance.
 */
class OffmusicService : MediaSessionService() {

    private var session: MediaSession? = null

    companion object {
        /** Set by [PlayerBridge] before calling startService. */
        @Volatile var sharedPlayer: OffmusicPlayer? = null
    }

    override fun onCreate() {
        super.onCreate()
        val player = sharedPlayer ?: return
        session = MediaSession.Builder(this, player.routingPlayer)
            .setId("offmusic")
            .build()
        // Use our existing small icon for the notification status bar icon.
        setMediaNotificationProvider(
            DefaultMediaNotificationProvider(this)
                .also { it.setSmallIcon(R.drawable.ic_notif_music) }
        )
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = session

    override fun onTaskRemoved(rootIntent: Intent?) {
        val player = session?.player
        // If nothing is playing when the user swipes away the app, stop the service.
        // If music is playing, keep the foreground service running.
        if (player == null || !player.isPlaying) {
            player?.stop()
            stopSelf()
        }
    }

    override fun onDestroy() {
        session?.release()
        session = null
        super.onDestroy()
    }
}
