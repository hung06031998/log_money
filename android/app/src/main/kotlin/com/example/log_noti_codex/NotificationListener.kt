package com.example.log_noti_codex

import android.app.Notification
import android.content.ComponentName
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

class NotificationListener : NotificationListenerService() {
    companion object { @Volatile var connected = false }
    override fun onListenerConnected() {
        connected = true
        try { activeNotifications?.forEach { archive(it, "recovered") } }
        catch (e: Exception) { recordError(e) }
    }
    override fun onListenerDisconnected() {
        connected = false
        requestRebind(ComponentName(this, NotificationListener::class.java))
    }
    override fun onDestroy() { connected = false; super.onDestroy() }
    override fun onNotificationPosted(sbn: StatusBarNotification) { archive(sbn, "posted") }

    private fun recordError(e: Exception) {
        Log.e("NotificationArchive", "Archive operation failed", e)
        getSharedPreferences("health", MODE_PRIVATE).edit()
            .putString("error", "${System.currentTimeMillis()}: ${e.javaClass.simpleName}: ${e.message}").commit()
    }
    private fun jsonValue(value: Any?): Any = when(value) {
        null -> JSONObject.NULL
        is Bundle -> JSONObject().apply {
            value.keySet().sorted().forEach { key ->
                put(key, try { jsonValue(value.get(key)) } catch (e: Exception) { "[Unreadable: ${e.javaClass.simpleName}]" })
            }
        }
        is CharSequence -> value.toString()
        is Number, is Boolean -> value
        is Array<*> -> JSONArray().apply { value.forEach { put(jsonValue(it)) } }
        is Iterable<*> -> JSONArray().apply { value.forEach { put(jsonValue(it)) } }
        is IntArray -> JSONArray(value.toList())
        is LongArray -> JSONArray(value.toList())
        is BooleanArray -> JSONArray(value.toList())
        else -> "[Non-text ${value.javaClass.name}]"
    }
    private fun archive(sbn: StatusBarNotification, source: String) {
        try {
            val n = sbn.notification
            val extras = n.extras ?: Bundle()
            val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
            val messages = extras.getParcelableArray("android.messages")?.mapNotNull { item ->
                (item as? Bundle)?.let { message ->
                    listOfNotNull(message.getCharSequence("sender"), message.getCharSequence("text"))
                        .joinToString(": ")
                }
            }?.joinToString("\n")
            val body = listOfNotNull(messages,
                extras.getCharSequence(Notification.EXTRA_TEXT)?.toString(),
                extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString(),
                extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString(),
                extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)?.joinToString("\n")
            ).distinct().joinToString("\n")
            val app = try { packageManager.getApplicationLabel(packageManager.getApplicationInfo(sbn.packageName, 0)).toString() }
                catch (_: Exception) { sbn.packageName }
            val payload = JSONObject().apply {
                put("key", sbn.key); put("package", sbn.packageName); put("id", sbn.id)
                put("tag", sbn.tag); put("postTime", sbn.postTime); put("when", n.`when`)
                put("user", sbn.user.toString()); put("groupKey", sbn.groupKey)
                put("category", n.category); put("flags", n.flags); put("visibility", n.visibility)
                put("groupSummary", n.flags and Notification.FLAG_GROUP_SUMMARY != 0)
                put("ticker", n.tickerText?.toString()); put("extras", jsonValue(extras))
                if (Build.VERSION.SDK_INT >= 26) put("channel", n.channelId)
                put("actions", JSONArray().apply { n.actions?.forEach { put(it.title?.toString()) } })
            }.toString(2)
            NotificationStore.get(this).append(sbn.key, sbn.postTime, source, sbn.packageName, app, title, body, payload)
        } catch (e: Exception) { recordError(e) }
    }
}

class RebindReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED || intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            NotificationListenerService.requestRebind(ComponentName(context, NotificationListener::class.java))
        }
    }
}
