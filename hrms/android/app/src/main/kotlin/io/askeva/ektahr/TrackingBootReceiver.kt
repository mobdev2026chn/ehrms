package io.askeva.ektahr

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Restarts punch-in location tracking after the phone reboots (or the app is updated), so a
 * field employee who is still punched in is tracked without having to open the app.
 *
 * Only when all of these hold:
 *  - the tracker was running when the phone went down (plugin's IS_TRACKING flag), and
 *  - tracking was switched on TODAY (app's presence_tracking_date) - a shift left open from an
 *    earlier day is not resumed, and
 *  - location is allowed "all the time" (Android will not start background location otherwise).
 *
 * The tracker service resumes location updates by itself in onCreate when IS_TRACKING is set,
 * and its locations reach the app's background Dart callback as usual.
 */
class TrackingBootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action !in RESTART_ACTIONS) return
        try {
            if (!wasTracking(context)) return
            if (!trackingDateIsToday(context)) {
                Log.i(TAG, "Not restarting: tracking was not started today")
                return
            }
            if (!hasBackgroundLocation(context)) {
                Log.i(TAG, "Not restarting: location is not allowed all the time")
                return
            }
            markAppClosed(context)
            val service = Intent().setClassName(context, TRACKER_SERVICE)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(service)
            } else {
                context.startService(service)
            }
            Log.i(TAG, "Tracking restarted after $action")
        } catch (e: Throwable) {
            Log.e(TAG, "Could not restart tracking after $action: $e")
        }
    }

    private fun wasTracking(ctx: Context): Boolean =
        ctx.getSharedPreferences(TRACKER_PREFS, Context.MODE_PRIVATE).getBoolean(TRACKER_IS_TRACKING, false)

    private fun trackingDateIsToday(ctx: Context): Boolean {
        // Flutter's SharedPreferences: file "FlutterSharedPreferences", keys prefixed "flutter.".
        val stored = ctx.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getString("flutter.presence_tracking_date", null) ?: return false
        val today = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
        return stored == today
    }

    /**
     * The app cannot be open right after a reboot, but its saved lifecycle state may still say
     * "foreground" (phone switched off with the app open) - and the background sender skips
     * every point while it does. Record it as closed, which is also how the points are labelled.
     */
    private fun markAppClosed(ctx: Context) {
        ctx.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .edit()
            .putString("flutter.presence_app_lifecycle_state", "closed")
            .putString("flutter.live_tracking_app_lifecycle_state", "closed")
            .apply()
    }

    private fun hasBackgroundLocation(ctx: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val fine = ctx.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        if (!fine) return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return true
        return ctx.checkSelfPermission(Manifest.permission.ACCESS_BACKGROUND_LOCATION) == PackageManager.PERMISSION_GRANTED
    }

    companion object {
        private const val TAG = "TrackingBootReceiver"
        private const val TRACKER_SERVICE = "com.icapps.background_location_tracker.service.LocationUpdatesService"
        private const val TRACKER_PREFS = "background_location_tracker"
        private const val TRACKER_IS_TRACKING = "background.location.tracker.manager.IS_TRACKING"
        private val RESTART_ACTIONS = setOf(
            Intent.ACTION_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON",
            Intent.ACTION_MY_PACKAGE_REPLACED,
        )
    }
}
