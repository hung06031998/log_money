package com.example.log_noti

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.IntentFilter
import androidx.core.content.ContextCompat
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import androidx.core.app.NotificationCompat
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.atomic.AtomicBoolean

class NotificationCaptureService : NotificationListenerService() {

    private val keepAliveStarted = AtomicBoolean(false)
    private val unlockReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent?) {
            NotificationWorker.start(context)
        }
    }

    override fun onCreate() {
        super.onCreate()
        startKeepAlive()
        ContextCompat.registerReceiver(this, unlockReceiver,
            IntentFilter(Intent.ACTION_USER_UNLOCKED), ContextCompat.RECEIVER_NOT_EXPORTED)
        NotificationWorker.start(this)
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        connected.set(true)
        startKeepAlive()
        NotificationEvents.emitStatus()
        try {
            activeNotifications?.forEach { sbn ->
                persist(sbn, fromSnapshot = true)
            }
        } catch (_: SecurityException) {
            // Listener just connected; retry on next posted event.
        }
    }

    override fun onListenerDisconnected() {
        connected.set(false)
        NotificationEvents.emitStatus()
        super.onListenerDisconnected()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            requestRebind(ComponentName(this, NotificationCaptureService::class.java))
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        persist(sbn, fromSnapshot = false)
    }

    override fun onNotificationPosted(
        sbn: StatusBarNotification?,
        rankingMap: RankingMap?,
    ) {
        persist(sbn, fromSnapshot = false)
    }

    override fun onDestroy() {
        unregisterReceiver(unlockReceiver)
        connected.set(false)
        super.onDestroy()
    }

    private fun persist(sbn: StatusBarNotification?, fromSnapshot: Boolean) {
        if (sbn == null) return
        if (sbn.packageName == packageName) return

        val notification = sbn.notification ?: return
        val extras = notification.extras ?: Bundle()
        val row = mapOf<String, Any?>(
            "packageName" to sbn.packageName,
            "opPackage" to sbn.opPkg,
            "appName" to appLabel(sbn.packageName),
            "title" to charSequence(extras, Notification.EXTRA_TITLE),
            "titleBig" to charSequence(extras, Notification.EXTRA_TITLE_BIG),
            "tickerText" to notification.tickerText?.toString(),
            "textLines" to extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)?.map { it?.toString() },
            "text" to charSequence(extras, Notification.EXTRA_TEXT),
            "bigText" to charSequence(extras, Notification.EXTRA_BIG_TEXT).ifBlank { null },
            "subText" to charSequence(extras, Notification.EXTRA_SUB_TEXT).ifBlank { null },
            "infoText" to charSequence(extras, Notification.EXTRA_INFO_TEXT).ifBlank { null },
            "summaryText" to charSequence(extras, Notification.EXTRA_SUMMARY_TEXT).ifBlank { null },
            "conversationTitle" to charSequence(extras, Notification.EXTRA_CONVERSATION_TITLE).ifBlank { null },
            "messageItems" to messagingItems(notification, extras),
            "channelId" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) notification.channelId else null,
            "category" to notification.category,
            "notificationKey" to (sbn.key ?: ""),
            "tag" to sbn.tag,
            "notificationId" to sbn.id,
            "postTime" to sbn.postTime,
            "receivedAt" to System.currentTimeMillis(),
            "isOngoing" to (notification.flags and Notification.FLAG_ONGOING_EVENT != 0),
            "isGroupSummary" to (notification.flags and Notification.FLAG_GROUP_SUMMARY != 0),
            "extrasJson" to extrasToJson(extras),
        )

        NotificationDb.get(this).enqueue(row, fromSnapshot) {
            NotificationWorker.start(this)
        }
    }

    private fun appLabel(packageName: String): String {
        return try {
            val pm = packageManager
            val info = pm.getApplicationInfo(packageName, 0)
            pm.getApplicationLabel(info).toString()
        } catch (_: Exception) {
            packageName
        }
    }

    private fun startKeepAlive() {
        if (!keepAliveStarted.compareAndSet(false, true)) return
        createChannel()
        val launch = Intent(this, MainActivity::class.java)
        val pending = PendingIntent.getActivity(
            this,
            0,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or pendingImmutable(),
        )
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.listener_notification_title))
            .setContentText(getString(R.string.listener_notification_text))
            .setSmallIcon(R.drawable.ic_notification)
            .setOngoing(true)
            .setContentIntent(pending)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setSilent(true)
            .build()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(
                    KEEP_ALIVE_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
                )
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForeground(KEEP_ALIVE_ID, notification)
            }
        } catch (_: Exception) {
            keepAliveStarted.set(false)
        }
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.listener_channel_name),
            NotificationManager.IMPORTANCE_MIN,
        ).apply {
            description = getString(R.string.listener_channel_desc)
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun pendingImmutable(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE
        } else {
            0
        }
    }

    private fun charSequence(extras: Bundle, key: String): String {
        return extras.getCharSequence(key)?.toString()?.trim().orEmpty()
    }

    private fun messagingItems(notification: Notification, extras: Bundle): List<Map<String, String?>> {
        val style = NotificationCompat.MessagingStyle.extractMessagingStyleFromNotification(notification)
        if (style != null && style.messages.isNotEmpty()) {
            return style.messages.map { message ->
                mapOf("sender" to (message.person?.name?.toString()
                    ?: message.extras.getCharSequence("sender")?.toString()),
                    "text" to message.text?.toString())
            }
        }
        return extras.getParcelableArray("android.messages")?.mapNotNull { item ->
            val bundle = item as? Bundle ?: return@mapNotNull null
            mapOf("sender" to bundle.getCharSequence("sender")?.toString(),
                "text" to bundle.getCharSequence("text")?.toString())
        } ?: emptyList()
    }

    private fun extrasToJson(extras: Bundle): String {
        return try {
            bundleToJson(extras, 0).toString()
        } catch (_: Exception) {
            "{}"
        }
    }

    private fun bundleToJson(bundle: Bundle, depth: Int): JSONObject {
        val json = JSONObject()
        if (depth > 3) return json
        for (key in bundle.keySet()) {
            if (key.contains("bitmap", ignoreCase = true) ||
                key.contains("icon", ignoreCase = true) ||
                key.contains("picture", ignoreCase = true) ||
                key.contains("largeIcon", ignoreCase = true)
            ) {
                continue
            }
            try {
                json.put(key, valueToJson(bundle.get(key), depth))
            } catch (_: Exception) {
                json.put(key, "<unreadable>")
            }
        }
        return json
    }

    private fun valueToJson(value: Any?, depth: Int): Any {
        return when (value) {
            null -> JSONObject.NULL
            is Bundle -> bundleToJson(value, depth + 1)
            is CharSequence -> value.toString()
            is Boolean, is Int, is Long, is Double, is Float -> value
            is Array<*> -> JSONArray(value.map { valueToJson(it, depth + 1) })
            else -> value.toString()
        }
    }

    companion object {
        const val CHANNEL_ID = "notification_listener_keepalive"
        const val KEEP_ALIVE_ID = 1001
        val connected = AtomicBoolean(false)

        fun requestReconnect(context: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                requestRebind(
                    ComponentName(context, NotificationCaptureService::class.java)
                )
            }
        }
    }
}
