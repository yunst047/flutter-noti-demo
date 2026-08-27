package com.f0h.fltnotidemo

import android.util.Log
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService

/**
 * Drives the Live Update from server-sent delivery steps, natively.
 *
 * The obvious design — have the Dart background handler call the
 * `noti_demo/live_update` MethodChannel — cannot work. Background messages run
 * on a separate FlutterEngine with no Activity, and the channel handler is
 * registered in MainActivity.configureFlutterEngine, so the background isolate
 * raises:
 *
 *   MissingPluginException: No implementation found for method start
 *   on channel noti_demo/live_update
 *
 * App-local Kotlin is not part of GeneratedPluginRegistrant either, so nothing
 * registers it on that engine. Rather than fight the engine lifecycle, the
 * delivery steps are handled here, before Dart is involved at all — which also
 * means they work identically whether the app is foregrounded, backgrounded or
 * killed, instead of only when an isolate happens to be reachable.
 *
 * super.onMessageReceived is still called so Dart continues to see every
 * message for the event log.
 */
class DeliveryMessagingService : FlutterFirebaseMessagingService() {

    private companion object { const val TAG = "DeliveryMsgSvc" }

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        val data = remoteMessage.data
        Log.i(TAG, "onMessageReceived type=${data["type"]} index=${data["index"]}")
        if (data["type"] == "delivery_step") {
            handleDeliveryStep(data)
        }
        super.onMessageReceived(remoteMessage)
    }

    private fun handleDeliveryStep(data: Map<String, String>) {
        val plugin = LiveUpdatePlugin(applicationContext)
        val index = data["index"]?.toIntOrNull() ?: 1
        val total = data["total"]?.toIntOrNull() ?: 4
        val title = "Order ${data["orderId"].orEmpty()}"
        val eta = data["eta"].orEmpty()

        when {
            index <= 1 -> plugin.startDelivery(title, eta)
            index >= total -> {
                // Show the final stage briefly, then clear it. Leaving an
                // ongoing notification behind after the delivery has finished
                // is the thing users complain about.
                plugin.updateDelivery(title, index - 1, eta)
                plugin.endDeliveryDelayed()
            }
            else -> plugin.updateDelivery(title, index - 1, eta)
        }
    }
}
