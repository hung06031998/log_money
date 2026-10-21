package com.example.log_noti

import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.Manifest
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class NotificationLogPlugin(
    private val context: Context,
    private val activity: () -> Activity?,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isPermissionGranted" -> result.success(isPermissionGranted())
            "openPermissionSettings" -> {
                openPermissionSettings()
                result.success(true)
            }
            "isListenerConnected" -> result.success(NotificationCaptureService.connected.get())
            "requestRebind" -> {
                NotificationCaptureService.requestReconnect(context)
                result.success(true)
            }
            "isIgnoringBatteryOptimizations" -> result.success(isIgnoringBattery())
            "requestIgnoreBatteryOptimizations" -> {
                requestIgnoreBattery()
                result.success(true)
            }
            "hasPostNotificationsPermission" -> result.success(hasPostNotificationsPermission())
            "requestPostNotifications" -> {
                val current = activity()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && current != null) {
                    current.requestPermissions(
                        arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                        2001,
                    )
                }
                result.success(true)
            }
            "postNotification" -> {
                val title = call.argument<String>("title").orEmpty()
                val text = call.argument<String>("text").orEmpty()
                val bigText = call.argument<String>("bigText")
                result.success(postNotification(title, text, bigText))
            }
            "openAppSettings" -> {
                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:${context.packageName}")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                result.success(true)
            }
            else -> NotificationWorker.call(context, call, result)
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        NotificationEvents.sink = events
        NotificationEvents.emitStatus()
        NotificationWorker.start(context)
    }

    override fun onCancel(arguments: Any?) {
        NotificationEvents.sink = null
    }

    private fun isPermissionGranted(): Boolean {
        return NotificationManagerCompat.getEnabledListenerPackages(context)
            .contains(context.packageName)
    }

    private fun openPermissionSettings() {
        val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val current = activity()
        if (current != null) {
            current.startActivity(intent)
        } else {
            context.startActivity(intent)
        }
    }

    private fun isIgnoringBattery(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(context.packageName)
    }

    private fun requestIgnoreBattery() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        if (isIgnoringBattery()) return
        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
            data = Uri.parse("package:${context.packageName}")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val current = activity()
        if (current != null) {
            current.startActivity(intent)
        } else {
            context.startActivity(intent)
        }
    }

    private fun hasPostNotificationsPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return manager.areNotificationsEnabled()
    }

    private fun postNotification(title: String, text: String, bigText: String?): Boolean {
        if (!hasPostNotificationsPermission()) {
            return false
        }
        ensureManualChannel()
        val now = System.currentTimeMillis()
        val notificationId = (now and 0x7FFFFFFF).toInt().let { if (it == 0) 1 else it }
        val launch = Intent(context, MainActivity::class.java)
        val pending = PendingIntent.getActivity(
            context,
            notificationId,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or pendingImmutable(),
        )
        val displayTitle = title.ifBlank { context.getString(R.string.app_name) }
        val displayText = text.ifBlank { bigText.orEmpty() }
        val builder = NotificationCompat.Builder(context, MANUAL_CHANNEL_ID)
            .setContentTitle(displayTitle)
            .setContentText(displayText.ifBlank { displayTitle })
            .setSmallIcon(R.drawable.ic_notification)
            .setContentIntent(pending)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
        val expanded = bigText?.trim().orEmpty().ifBlank { displayText }
        if (expanded.isNotBlank()) {
            builder.setStyle(NotificationCompat.BigTextStyle().bigText(expanded))
        }
        try {
            NotificationManagerCompat.from(context).notify(notificationId, builder.build())
        } catch (_: SecurityException) {
            return false
        }

        val packageName = context.packageName
        val row = mapOf<String, Any?>(
            "packageName" to packageName,
            "opPackage" to packageName,
            "appName" to context.getString(R.string.app_name),
            "title" to displayTitle,
            "text" to displayText,
            "bigText" to bigText?.trim()?.ifBlank { null },
            "subText" to null,
            "infoText" to null,
            "summaryText" to null,
            "conversationTitle" to null,
            "messages" to null,
            "channelId" to MANUAL_CHANNEL_ID,
            "category" to NotificationCompat.CATEGORY_MESSAGE,
            "notificationKey" to "$packageName|manual|$notificationId|$now",
            "tag" to "manual",
            "notificationId" to notificationId,
            "postTime" to now,
            "receivedAt" to now,
            "isOngoing" to false,
            "isGroupSummary" to false,
            "extrasJson" to null,
        )
        NotificationDb.get(context).enqueue(row, false) {
            NotificationWorker.start(context)
        }
        return true
    }

    private fun ensureManualChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            MANUAL_CHANNEL_ID,
            context.getString(R.string.manual_channel_name),
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = context.getString(R.string.manual_channel_desc)
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

    companion object {
        private const val METHOD = "com.example.log_noti/methods"
        private const val EVENTS = "com.example.log_noti/events"
        private const val MANUAL_CHANNEL_ID = "manual_notifications"

        fun register(engine: FlutterEngine, activity: Activity) {
            val plugin = NotificationLogPlugin(activity.applicationContext) { activity }
            MethodChannel(engine.dartExecutor.binaryMessenger, METHOD)
                .setMethodCallHandler(plugin)
            EventChannel(engine.dartExecutor.binaryMessenger, EVENTS)
                .setStreamHandler(plugin)
        }
    }
}
