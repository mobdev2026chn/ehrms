package com.icapps.background_location_tracker.utils

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.location.Location
import android.os.Build
import androidx.core.app.NotificationCompat
import com.icapps.background_location_tracker.ext.getAppIcon
import com.icapps.background_location_tracker.ext.getAppName
import com.icapps.background_location_tracker.ext.notificationManager
import com.icapps.background_location_tracker.service.LocationUpdatesService
import java.text.DateFormat
import java.util.Date

internal object NotificationUtil {

    /**
     * The name of the channel for notifications.
     */
    private const val CHANNEL_ID = "com_icapps_background_tracking_notification_channel"

    /**
     * The identifier for the notification displayed for the foreground service.
     */
    private const val NOTIFICATION_ID = 879848645

    /**
     * Android O requires a Notification Channel.
     * This will create a new notification channel for the foreground notification
     */
    fun createNotificationChannels(context: Context, channelName: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, channelName, NotificationManager.IMPORTANCE_LOW)
            channel.enableVibration(false)
            channel.setSound(null, null)
            context.notificationManager().createNotificationChannel(channel)
        }
    }

    /**
     * Returns the [NotificationCompat] used as part of the foreground service.
     */
    private fun getNotification(context: Context, location: Location?): Notification {
        val intent = Intent(context, LocationUpdatesService::class.java)
        intent.putExtra(LocationUpdatesService.EXTRA_STARTED_FROM_NOTIFICATION, true)
        val cancelTrackingIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.getService(context, 0, intent, PendingIntent.FLAG_IMMUTABLE)
        } else {
            @Suppress("UnspecifiedImmutableFlag")
            PendingIntent.getService(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT)
        }

        val clickPendingIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.getActivity(context, 0, context.packageManager.getLaunchIntentForPackage(context.packageName), PendingIntent.FLAG_IMMUTABLE)
        } else {
            @Suppress("UnspecifiedImmutableFlag")
            PendingIntent.getActivity(context, 0, context.packageManager.getLaunchIntentForPackage(context.packageName), 0)
        }

        val title = if (SharedPrefsUtil.isNotificationLocationUpdatesEnabled(context)) {
            String.format("Location Update: %s", DateFormat.getDateTimeInstance().format(Date()))
        } else {
            context.getAppName()
        }

        val text = if (SharedPrefsUtil.isNotificationLocationUpdatesEnabled(context)) {
            if (location == null) "Unknown location" else "(" + location.latitude + ", " + location.longitude + ")"
        } else {
            SharedPrefsUtil.getNotificationBody(context)
        }

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
                .setContentTitle(title)
                .setContentText(text)
                .setContentIntent(clickPendingIntent)
                .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
        if (SharedPrefsUtil.isCancelTrackingActionEnabled(context)) {
            builder.addAction(0, SharedPrefsUtil.getCancelTrackingActionText(context), cancelTrackingIntent)
        }
        builder.setSmallIcon(resolveSmallIcon(context))

        builder.setOngoing(true)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setTicker(text)
                .setVibrate(null)
                .setDefaults(0)
                .setSound(null)
                .setWhen(System.currentTimeMillis())
        return builder.build()
    }

    /**
     * A small icon that is guaranteed to exist. startForeground with icon id 0 throws
     * "Bad notification for startForeground" and kills the app - which is what happened when
     * the service restarted on app launch with an icon name saved by an older app version
     * ("explore") that the current build no longer has. The service can restart before Dart
     * re-saves the config, so the saved name alone can't be trusted.
     */
    private fun resolveSmallIcon(context: Context): Int {
        val res = context.resources
        val pkg = context.packageName
        val saved = SharedPrefsUtil.getNotificationIcon(context)
        if (!saved.isNullOrBlank()) {
            val id = res.getIdentifier(saved, "drawable", pkg)
            if (id != 0) return id
            val mip = res.getIdentifier(saved, "mipmap", pkg)
            if (mip != 0) return mip
        }
        // App's status-bar icon, then the launcher icon as a last resort.
        val stat = res.getIdentifier("ic_stat_ektahr", "drawable", pkg)
        if (stat != 0) return stat
        return context.getAppIcon()
    }

    fun showNotification(context: Context, location: Location?) {
        val notification = getNotification(context, location)
        context.notificationManager().notify(NOTIFICATION_ID, notification)
    }

    fun startForeground(service: LocationUpdatesService, location: Location?) {
        // The service can be restarted by the system before Dart calls initialize(), which is
        // where the channel is normally created; a missing channel is also a "Bad notification".
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            service.notificationManager().getNotificationChannel(CHANNEL_ID) == null) {
            createNotificationChannels(service, "Live Tracking")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            service.startForeground(NOTIFICATION_ID, getNotification(service, location), ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
        } else {
            service.startForeground(NOTIFICATION_ID, getNotification(service, location))
        }
    }
}