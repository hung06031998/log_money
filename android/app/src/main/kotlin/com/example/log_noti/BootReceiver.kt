package com.example.log_noti

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (action == Intent.ACTION_BOOT_COMPLETED ||
            action == Intent.ACTION_USER_UNLOCKED ||
            action == Intent.ACTION_LOCKED_BOOT_COMPLETED
        ) {
            NotificationCaptureService.requestReconnect(context)
            NotificationWorker.start(context)
        }
    }
}
