package com.simplelive.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "simple_live/background_playback",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    startService()
                    result.success(null)
                }

                "stop" -> {
                    stopService(Intent(this, BackgroundPlaybackService::class.java))
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "simple_live/live_notifications",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "showLiveStart" -> {
                    showLiveStartNotification(
                        notificationId = call.argument<Int>("notificationId") ?: 1002,
                        title = call.argument<String>("title") ?: "特别关注开播了",
                        body = call.argument<String>("body") ?: "点击回到 Simple Live",
                    )
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "simple_live/app_icon",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setIcon" -> {
                    val icon = call.argument<String>("icon") ?: "classic"
                    try {
                        setLauncherIcon(icon)
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("APP_ICON_SWITCH_FAILED", error.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun startService() {
        val intent = Intent(this, BackgroundPlaybackService::class.java)
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun setLauncherIcon(icon: String) {
        val classic = ComponentName(this, "$packageName.ClassicIcon")
        val simpleLive = ComponentName(this, "$packageName.SimpleLiveIcon")
        val useModern = icon == "modern" || icon == "simplelive"
        val selected = if (useModern) simpleLive else classic
        val unselected = if (useModern) classic else simpleLive

        packageManager.setComponentEnabledSetting(
            selected,
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP,
        )
        packageManager.setComponentEnabledSetting(
            unselected,
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            PackageManager.DONT_KILL_APP,
        )
    }

    private fun showLiveStartNotification(notificationId: Int, title: String, body: String) {
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        createLiveStartNotificationChannel(manager)
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, LIVE_START_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(body)
            .setAutoCancel(true)
            .setShowWhen(true)
            .setContentIntent(
                PendingIntent.getActivity(
                    this,
                    notificationId,
                    Intent(this, MainActivity::class.java).apply {
                        flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                    },
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                ),
            )
            .build()
        manager.notify(notificationId, notification)
    }

    private fun createLiveStartNotificationChannel(manager: NotificationManager) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val channel = NotificationChannel(
            LIVE_START_CHANNEL_ID,
            "开播提醒",
            NotificationManager.IMPORTANCE_DEFAULT,
        )
        channel.description = "特别关注主播开播提醒"
        manager.createNotificationChannel(channel)
    }

    companion object {
        private const val LIVE_START_CHANNEL_ID = "simple_live_live_start"
    }
}
