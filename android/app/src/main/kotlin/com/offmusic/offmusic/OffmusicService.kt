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
        // Use our existing small icon for the notification status bar icon.
        setMediaNotificationProvider(
            DefaultMediaNotificationProvider(this)
                .also { it.setSmallIcon(R.drawable.ic_notif_music) }
        )
        session = MediaSession.Builder(this, player.routingPlayer)
            .setId("offmusic")
            .build()
        // addSession() registers the session with MediaNotificationManager so it
        // starts observing player state and shows the notification automatically —
        // no MediaController connection required.
        addSession(session!!)
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = session

    override fun onTaskRemoved(rootIntent: Intent?) {
        val player = session?.player
        // Stop service (and music) when user dismisses the app while paused.
        // Keep running if music is actively playing.
        if (player == null || !player.isPlaying) {
            player?.stop()
            stopSelf()
        }
    }

    override fun onDestroy() {
        // MediaSessionService.onDestroy() releases all sessions in getSessions().
        // Clear our reference first; super handles the actual release.
        session = null
        super.onDestroy()
    }
}
