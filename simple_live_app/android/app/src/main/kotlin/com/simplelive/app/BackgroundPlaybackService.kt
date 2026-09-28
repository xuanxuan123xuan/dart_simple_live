package com.simplelive.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.IBinder
import android.graphics.drawable.Icon

class BackgroundPlaybackService : Service() {
    private lateinit var mediaSession: MediaSession
    private lateinit var audioManager: AudioManager
    private var audioFocusRequest: AudioFocusRequest? = null
    private var isPlaying = true
    private var resumeAfterTransientFocusLoss = false
    private var title = "Simple Live"
    private var artist = "正在后台播放直播"
    private var album = ""

    private val audioFocusListener = AudioManager.OnAudioFocusChangeListener { change ->
        when (change) {
            AudioManager.AUDIOFOCUS_GAIN -> {
                if (resumeAfterTransientFocusLoss) {
                    resumeAfterTransientFocusLoss = false
                    isPlaying = true
                    updatePlaybackState()
                    sendControlToFlutter("resume")
                } else {
                    sendControlToFlutter("unduck")
                }
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                resumeAfterTransientFocusLoss = isPlaying
                isPlaying = false
                updatePlaybackState()
                sendControlToFlutter("pause")
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                sendControlToFlutter("duck")
            }
            AudioManager.AUDIOFOCUS_LOSS -> {
                resumeAfterTransientFocusLoss = false
                isPlaying = false
                updatePlaybackState()
                sendControlToFlutter("pause")
                abandonAudioFocus()
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        audioManager = getSystemService(AudioManager::class.java)
        mediaSession = MediaSession(this, "SimpleLiveBackgroundPlayback").apply {
            setCallback(object : MediaSession.Callback() {
                override fun onPlay() = handleControl(ACTION_PLAY)
                override fun onPause() = handleControl(ACTION_PAUSE)
                override fun onStop() = handleControl(ACTION_STOP)
            })
            isActive = true
        }
        requestAudioFocus()
        updatePlaybackState()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_PLAY -> handleControl(ACTION_PLAY)
            ACTION_PAUSE -> handleControl(ACTION_PAUSE)
            ACTION_STOP -> handleControl(ACTION_STOP)
            ACTION_UPDATE_METADATA -> updateMetadata(intent)
            ACTION_UPDATE_PLAYBACK_STATE -> {
                isPlaying = intent.getBooleanExtra(EXTRA_PLAYING, isPlaying)
                updatePlaybackState()
            }
        }
        startForeground(NOTIFICATION_ID, buildNotification())
        return START_STICKY
    }

    override fun onDestroy() {
        abandonAudioFocus()
        if (::mediaSession.isInitialized) {
            mediaSession.isActive = false
            mediaSession.release()
        }
        super.onDestroy()
    }

    private fun handleControl(action: String) {
        when (action) {
            ACTION_PLAY -> {
                isPlaying = true
                requestAudioFocus()
                updatePlaybackState()
                sendControlToFlutter("play")
            }
            ACTION_PAUSE -> {
                isPlaying = false
                updatePlaybackState()
                sendControlToFlutter("pause")
            }
            ACTION_STOP -> {
                isPlaying = false
                updatePlaybackState()
                sendControlToFlutter("stop")
                stopSelf()
            }
        }
        if (action != ACTION_STOP) updateNotification()
    }

    private fun updateMetadata(intent: Intent) {
        title = intent.getStringExtra(EXTRA_TITLE)?.trim().orEmpty().ifEmpty { "Simple Live" }
        artist = intent.getStringExtra(EXTRA_ARTIST)?.trim().orEmpty().ifEmpty { "正在后台播放直播" }
        album = intent.getStringExtra(EXTRA_ALBUM)?.trim().orEmpty()
        mediaSession.setMetadata(
            MediaMetadata.Builder()
                .putString(MediaMetadata.METADATA_KEY_TITLE, title)
                .putString(MediaMetadata.METADATA_KEY_ARTIST, artist)
                .putString(MediaMetadata.METADATA_KEY_ALBUM, album)
                .build(),
        )
        updateNotification()
    }

    private fun updatePlaybackState() {
        val state = if (isPlaying) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED
        mediaSession.setPlaybackState(
            PlaybackState.Builder()
                .setActions(
                    PlaybackState.ACTION_PLAY or
                        PlaybackState.ACTION_PAUSE or
                        PlaybackState.ACTION_STOP,
                )
                .setState(state, PlaybackState.PLAYBACK_POSITION_UNKNOWN, 1f)
                .build(),
        )
        updateNotification()
    }

    private fun updateNotification() {
        val manager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java)
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        }
        manager.notify(NOTIFICATION_ID, buildNotification())
    }

    private fun sendControlToFlutter(control: String) {
        sendBroadcast(
            Intent(ACTION_CONTROL).setPackage(packageName).putExtra(EXTRA_CONTROL, control),
        )
    }

    private fun requestAudioFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build(),
                )
                .setOnAudioFocusChangeListener(audioFocusListener)
                .build()
            audioFocusRequest = request
            audioManager.requestAudioFocus(request)
        } else {
            @Suppress("DEPRECATION")
            audioManager.requestAudioFocus(
                audioFocusListener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN,
            )
        }
    }

    private fun abandonAudioFocus() {
        if (!::audioManager.isInitialized) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioFocusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
            audioFocusRequest = null
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(audioFocusListener)
        }
    }

    private fun buildNotification(): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(if (album.isEmpty()) artist else "$artist · $album")
            .setOngoing(isPlaying)
            .setShowWhen(false)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .addAction(buildAction(if (isPlaying) ACTION_PAUSE else ACTION_PLAY, if (isPlaying) "暂停" else "播放"))
            .addAction(buildAction(ACTION_STOP, "停止"))
            .setStyle(
                Notification.MediaStyle()
                    .setMediaSession(mediaSession.sessionToken)
                    .setShowActionsInCompactView(0, 1),
            )
            .setContentIntent(
                PendingIntent.getActivity(
                    this,
                    0,
                    Intent(this, MainActivity::class.java).apply {
                        flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                    },
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                ),
            )
            .build()
    }

    private fun buildAction(action: String, label: String): Notification.Action {
        val pendingIntent = PendingIntent.getService(
            this,
            action.hashCode(),
            Intent(this, BackgroundPlaybackService::class.java).setAction(action),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Notification.Action.Builder(
                Icon.createWithResource(this, applicationInfo.icon),
                label,
                pendingIntent,
            ).build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Action.Builder(applicationInfo.icon, label, pendingIntent).build()
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            CHANNEL_ID,
            "后台播放",
            NotificationManager.IMPORTANCE_LOW,
        )
        channel.description = "直播后台播放保活"
        manager.createNotificationChannel(channel)
    }

    companion object {
        const val ACTION_PLAY = "com.simplelive.app.action.PLAY"
        const val ACTION_PAUSE = "com.simplelive.app.action.PAUSE"
        const val ACTION_STOP = "com.simplelive.app.action.STOP"
        const val ACTION_UPDATE_METADATA = "com.simplelive.app.action.UPDATE_METADATA"
        const val ACTION_UPDATE_PLAYBACK_STATE = "com.simplelive.app.action.UPDATE_PLAYBACK_STATE"
        const val ACTION_CONTROL = "com.simplelive.app.action.CONTROL"
        const val EXTRA_CONTROL = "control"
        const val EXTRA_TITLE = "title"
        const val EXTRA_ARTIST = "artist"
        const val EXTRA_ALBUM = "album"
        const val EXTRA_PLAYING = "playing"
        private const val CHANNEL_ID = "simple_live_background_playback"
        private const val NOTIFICATION_ID = 1001
    }
}
