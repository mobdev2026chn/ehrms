package com.icapps.background_location_tracker.receiver

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.LocationManager
import android.os.Build
import androidx.core.app.AlarmManagerCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.core.location.LocationManagerCompat
import com.icapps.background_location_tracker.ext.notificationManager
import com.icapps.background_location_tracker.service.LocationUpdatesService
import com.icapps.background_location_tracker.utils.Logger
import com.icapps.background_location_tracker.utils.NotificationUtil
import com.icapps.background_location_tracker.utils.SharedPrefsUtil
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Tracking watchdog that works with the app closed or killed (not force-stopped).
 *
 * While tracking runs, a system alarm wakes this receiver every [CHECK_EVERY_MS]. When no
 * location fix has arrived for [STALE_MS] - the tracker was stopped by the phone, GPS was
 * switched off, or the location permission was taken away - it tries to start tracking again
 * and shows the employee an alarm notification saying what is wrong; tapping it opens the app,
 * which resumes tracking. The alert clears itself as soon as fixes arrive again.
 *
 * Fixes arrive every few seconds even while standing still, so a quiet stretch here always
 * means tracking is not working - never "the employee is idle".
 */
internal class TrackingWatchdogReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val ctx = context.applicationContext
        try {
            if (!SharedPrefsUtil.isTracking(ctx)) {
                cancel(ctx)
                clearAlert(ctx)
                return
            }
            // One-shot alarm (allowed in Doze): chain the next check first.
            schedule(ctx)

            val now = System.currentTimeMillis()
            val reference = maxOf(SharedPrefsUtil.lastFixMs(ctx), SharedPrefsUtil.trackingStartedMs(ctx))
            if (reference > 0 && now - reference < STALE_MS) return

            val gpsOn = isLocationEnabled(ctx)
            val permitted = hasLocationPermission(ctx)
            if (gpsOn && permitted) restartTracking(ctx)
            showAlert(ctx, if (reference > 0) reference else now, gpsOn, permitted)
        } catch (e: Throwable) {
            Logger.error(TAG, "Watchdog check failed: $e")
        }
    }

    companion object {
        private val TAG = TrackingWatchdogReceiver::class.java.simpleName

        /** How often the watchdog looks (Android allows ~9 min minimum in Doze). */
        const val CHECK_EVERY_MS = 10 * 60 * 1000L

        /** No fix for this long while tracking = tracking is not working. */
        const val STALE_MS = 8 * 60 * 1000L

        // Same channel as the app's own tracking alerts; its own id so neither clears the other.
        private const val CHANNEL_ID = "hrms_tracking_health"
        private const val NOTIFICATION_ID = 7302
        private const val REQUEST_CODE = 7302

        private fun pendingIntent(ctx: Context): PendingIntent {
            val intent = Intent(ctx, TrackingWatchdogReceiver::class.java)
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            return PendingIntent.getBroadcast(ctx, REQUEST_CODE, intent, flags)
        }

        /** Arms the next check. Called when tracking starts and from each check. */
        fun schedule(ctx: Context) {
            try {
                val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                AlarmManagerCompat.setAndAllowWhileIdle(
                    am,
                    AlarmManager.RTC_WAKEUP,
                    System.currentTimeMillis() + CHECK_EVERY_MS,
                    pendingIntent(ctx),
                )
            } catch (e: Throwable) {
                Logger.error(TAG, "Could not schedule the watchdog: $e")
            }
        }

        /** Tracking stopped on purpose (punch-out): no more checks. */
        fun cancel(ctx: Context) {
            try {
                val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                am.cancel(pendingIntent(ctx))
            } catch (_: Throwable) {
            }
        }

        /** A fix arrived (or tracking stopped): remove a "tracking stopped" alert if shown. */
        fun clearAlert(ctx: Context) {
            if (!SharedPrefsUtil.isWatchdogAlertShown(ctx)) return
            try {
                ctx.notificationManager().cancel(NOTIFICATION_ID)
            } catch (_: Throwable) {
            }
            SharedPrefsUtil.saveWatchdogAlertShown(ctx, false)
        }

        private fun isLocationEnabled(ctx: Context): Boolean = try {
            val lm = ctx.getSystemService(Context.LOCATION_SERVICE) as LocationManager
            LocationManagerCompat.isLocationEnabled(lm)
        } catch (_: Throwable) {
            true
        }

        private fun hasLocationPermission(ctx: Context): Boolean {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
            val fine = ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_FINE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED
            if (!fine) return false
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return true
            return ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_BACKGROUND_LOCATION) ==
                PackageManager.PERMISSION_GRANTED
        }

        /** Best effort: Android 12+ allows it when the app is exempt from battery optimisation. */
        private fun restartTracking(ctx: Context) {
            try {
                ContextCompat.startForegroundService(ctx, Intent(ctx, LocationUpdatesService::class.java))
            } catch (e: Throwable) {
                Logger.error(TAG, "Could not restart tracking from the watchdog: $e")
            }
        }

        private fun showAlert(ctx: Context, lastFixMs: Long, gpsOn: Boolean, permitted: Boolean) {
            val since = SimpleDateFormat("hh:mm a", Locale.getDefault()).format(Date(lastFixMs))
            val (title, body) = when {
                !gpsOn -> "Tracking stopped: GPS is off" to
                    "No location since $since. Turn on Location (GPS) so your route is tracked."
                !permitted -> "Tracking stopped: location not allowed" to
                    "No location since $since. Set EktaHR location to \"Allow all the time\"."
                else -> "Tracking stopped" to
                    "No location since $since. Tap to open EktaHR and resume tracking. Set battery usage to \"Unrestricted\" so it keeps running."
            }
            val nm = ctx.notificationManager()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && nm.getNotificationChannel(CHANNEL_ID) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(CHANNEL_ID, "Tracking alerts", NotificationManager.IMPORTANCE_HIGH).apply {
                        description = "Alerts when your phone settings stop attendance tracking"
                    }
                )
            }
            val launch = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
            val contentIntent = launch?.let {
                PendingIntent.getActivity(
                    ctx,
                    REQUEST_CODE,
                    it,
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0,
                )
            }
            val notification = NotificationCompat.Builder(ctx, CHANNEL_ID)
                .setSmallIcon(NotificationUtil.resolveSmallIcon(ctx))
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setDefaults(NotificationCompat.DEFAULT_ALL)
                .setOngoing(true)
                .setAutoCancel(false)
                .apply { if (contentIntent != null) setContentIntent(contentIntent) }
                .build()
            try {
                nm.notify(NOTIFICATION_ID, notification)
                SharedPrefsUtil.saveWatchdogAlertShown(ctx, true)
            } catch (e: Throwable) {
                // Android 13+ without notification permission: nothing more we can do here.
                Logger.error(TAG, "Could not show the watchdog alert: $e")
            }
        }
    }
}
