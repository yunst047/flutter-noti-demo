package com.f0h.fltnotidemo

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.graphics.Color
import android.os.Build
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Android Live Updates — promoted ongoing notifications.
 *
 * flutter_local_notifications does not expose Notification.ProgressStyle, so
 * this is a MethodChannel down to the platform API.
 *
 * Two different API levels matter and are constantly confused:
 *
 *  - **API 36 (Android 16)** introduced ProgressStyle and
 *    setRequestPromotedOngoing. The notification renders with a segmented
 *    progress bar and updates in place.
 *  - **API 36.1 (Android 16 QPR1)** is where the request is actually honoured
 *    and the notification is *promoted* — status-bar chip, elevated treatment.
 *
 * Build.VERSION.SDK_INT reports 36 on both, so it cannot tell them apart.
 * SDK_INT_FULL (also 36.1+) is what distinguishes them. On a 36-but-not-36.1
 * device the notification still works and simply is not promoted: that is
 * correct behaviour, not a bug.
 */
class LiveUpdatePlugin(private val context: Context) {

    companion object {
        const val CHANNEL = "noti_demo/live_update"
        private const val CHANNEL_ID = "demo_live_update"
        private const val NOTIFICATION_ID = 4001

        /** The four delivery stages, matching the backend's scenarios.Steps. */
        private val STEPS = listOf(
            "Order received",
            "Restaurant is preparing your order",
            "Rider picked up your order",
            "Rider is on the way",
        )
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "capabilities" -> result.success(capabilities())
            "start" -> {
                show(
                    title = call.argument<String>("title") ?: "Delivery",
                    step = 0,
                    eta = call.argument<String>("eta") ?: "25 min",
                )
                result.success(true)
            }
            "update" -> {
                show(
                    title = call.argument<String>("title") ?: "Delivery",
                    step = call.argument<Int>("step") ?: 0,
                    eta = call.argument<String>("eta") ?: "",
                )
                result.success(true)
            }
            "end" -> {
                end()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    /**
     * What this device can actually do, so the UI can say so instead of
     * silently degrading and looking broken.
     */
    private fun capabilities(): Map<String, Any> {
        val nm = context.getSystemService(NotificationManager::class.java)
        val sdkFull = if (Build.VERSION.SDK_INT >= 36) {
            // SDK_INT_FULL encodes major*100_000 + minor; 36.1 -> 3_600_001.
            runCatching { Build.VERSION::class.java.getField("SDK_INT_FULL").getInt(null) }
                .getOrDefault(0)
        } else 0

        val canPost = if (Build.VERSION.SDK_INT >= 36) {
            runCatching {
                NotificationManager::class.java
                    .getMethod("canPostPromotedNotifications")
                    .invoke(nm) as Boolean
            }.getOrDefault(false)
        } else false

        return mapOf(
            "sdkInt" to Build.VERSION.SDK_INT,
            "sdkIntFull" to sdkFull,
            "supportsProgressStyle" to (Build.VERSION.SDK_INT >= 36),
            "canPostPromoted" to canPost,
        )
    }

    private fun ensureChannel(nm: NotificationManager) {
        // Importance must not be MIN or the notification is ineligible for
        // promotion. DEFAULT keeps it eligible without making every progress
        // tick play a sound.
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Live delivery updates",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "Promoted ongoing notification for the delivery demo"
            setShowBadge(false)
        }
        nm.createNotificationChannel(channel)
    }

    private fun show(
        title: String,
        step: Int,
        eta: String,
        finished: Boolean = false,
        timeoutAfterMs: Long = 0,
    ) {
        val nm = context.getSystemService(NotificationManager::class.java)
        ensureChannel(nm)

        val builder = Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            // A content title is mandatory for promotion.
            .setContentTitle(title)
            .setContentText(STEPS.getOrElse(step) { "" })
            // Ongoing is mandatory while in progress: a Live Update represents
            // something still happening, and the system refuses to promote a
            // dismissible one. Once finished it must be dropped, or the user is
            // left with a notification they cannot swipe away.
            .setOngoing(!finished)
            // Deliberately NOT setColorized(true) and NOT a group summary, and
            // no custom RemoteViews — each of those disqualifies promotion on
            // its own, silently.
            .setOnlyAlertOnce(true)

        if (finished) {
            builder.setAutoCancel(true)
            if (timeoutAfterMs > 0) builder.setTimeoutAfter(timeoutAfterMs)
        }

        if (Build.VERSION.SDK_INT >= 36) {
            applyProgressStyle(builder, step, eta, promote = !finished)
        }

        nm.notify(NOTIFICATION_ID, builder.build())
    }

    /**
     * ProgressStyle with one segment per delivery stage and a point marking
     * each boundary, which is what gives the bar its stepped appearance rather
     * than a plain percentage.
     */
    private fun applyProgressStyle(
        builder: Notification.Builder,
        step: Int,
        eta: String,
        promote: Boolean = true,
    ) {
        runCatching {
            val styleCls = Class.forName("android.app.Notification\$ProgressStyle")
            val segCls = Class.forName("android.app.Notification\$ProgressStyle\$Segment")
            val pointCls = Class.forName("android.app.Notification\$ProgressStyle\$Point")

            val style = styleCls.getConstructor().newInstance()

            // Four equal segments, coloured up to the current stage.
            val segments = STEPS.indices.map { i ->
                segCls.getConstructor(Int::class.javaPrimitiveType).newInstance(25).also { seg ->
                    segCls.getMethod("setColor", Int::class.javaPrimitiveType)
                        .invoke(seg, if (i <= step) Color.parseColor("#3B6EF6") else Color.LTGRAY)
                }
            }
            styleCls.getMethod("setProgressSegments", List::class.java).invoke(style, segments)

            // A point at each completed boundary.
            val points = (1..step).map { i ->
                pointCls.getConstructor(Int::class.javaPrimitiveType).newInstance(i * 25).also { p ->
                    pointCls.getMethod("setColor", Int::class.javaPrimitiveType)
                        .invoke(p, Color.WHITE)
                }
            }
            styleCls.getMethod("setProgressPoints", List::class.java).invoke(style, points)

            styleCls.getMethod("setProgress", Int::class.javaPrimitiveType)
                .invoke(style, ((step + 1) * 25).coerceAtMost(100))

            builder.style = style as Notification.Style

            // Asks the system to promote this to a Live Update. Honoured only
            // on 36.1+; on plain 36 it is accepted and ignored. Not requested
            // for the final state — that is no longer in progress.
            Notification.Builder::class.java
                .getMethod("setRequestPromotedOngoing", Boolean::class.javaPrimitiveType)
                .invoke(builder, promote)

            // The short text shown in the status-bar chip once promoted.
            if (eta.isNotEmpty()) {
                Notification.Builder::class.java
                    .getMethod("setShortCriticalText", String::class.java)
                    .invoke(builder, eta)
            }
        }.onFailure {
            // Reflection is used so the app still builds and runs against an
            // SDK without these classes. A failure here means no promotion, not
            // a crash — the notification is still posted, just unpromoted.
            android.util.Log.w("LiveUpdatePlugin", "ProgressStyle unavailable: ${it.message}")
        }
    }

    private fun end() {
        context.getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
    }

    // --- entry points for DeliveryMessagingService -------------------------
    //
    // Server-driven steps arrive natively rather than through the
    // MethodChannel, because the background isolate cannot reach it.

    fun startDelivery(title: String, eta: String) = show(title, 0, eta)

    fun updateDelivery(title: String, step: Int, eta: String) = show(title, step, eta)

    /**
     * Posts the final stage so it lingers briefly, then expires on its own.
     *
     * The obvious approach — Handler.postDelayed { end() } — does not survive:
     * this runs inside a FirebaseMessagingService, which Android may tear down
     * as soon as onMessageReceived returns, taking the pending callback with
     * it. The notification then stays on screen forever, and because it is
     * ongoing the user cannot even swipe it away.
     *
     * setTimeoutAfter hands expiry to the system instead, so it happens whether
     * or not this process is still alive. Ongoing is also dropped here: the
     * delivery is over, so it should no longer be promoted or undismissable.
     */
    fun endDeliveryFinal(title: String, step: Int, eta: String, lingerMs: Long = 8000) {
        show(title, step, eta, finished = true, timeoutAfterMs = lingerMs)
    }
}
