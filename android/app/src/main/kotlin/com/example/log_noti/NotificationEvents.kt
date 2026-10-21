package com.example.log_noti

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

object NotificationEvents {
    @Volatile
    var sink: EventChannel.EventSink? = null
    private val main = Handler(Looper.getMainLooper())

    fun emitNotification(row: Map<String, Any?>) {
        emit(
            mapOf(
                "type" to "notification",
                "notification" to row,
            )
        )
    }

    fun emitFilterChanged() {
        emit(mapOf("type" to "filter"))
    }

    fun emitStatus() {
        emit(
            mapOf(
                "type" to "status",
                "listenerConnected" to NotificationCaptureService.connected.get(),
            )
        )
    }

    fun emit(payload: Map<String, Any?>) {
        main.post {
            sink?.success(payload)
        }
    }
}
