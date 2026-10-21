package com.example.log_noti_codex

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.pm.PackageManager
import android.os.Build
import java.util.UUID
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import android.service.notification.NotificationListenerService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var pendingNotification: Triple<String, String, MethodChannel.Result>? = null
    private val notificationPermissionRequest = 101
    private val notificationChannelId = "manual_notifications"
    private val reader = Executors.newSingleThreadExecutor()
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "notification_archive").setMethodCallHandler { call, result ->
            when (call.method) {
                "createNotification" -> {
                    val title = call.argument<String>("title").orEmpty().trim()
                    val body = call.argument<String>("body").orEmpty().trim()
                    if (title.isEmpty() || body.isEmpty() || title.length > 200 || body.length > 4000) {
                        result.error("INVALID", "Vui lòng nhập tiêu đề và nội dung hợp lệ.", null)
                    } else if (pendingNotification != null) {
                        result.error("BUSY", "Đang chờ cấp quyền thông báo.", null)
                    } else if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        pendingNotification = Triple(title, body, result)
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), notificationPermissionRequest)
                    } else {
                        postNotification(title, body, result)
                    }
                }
                "status", "page", "detail" -> reader.execute {
                    try {
                        val store = NotificationStore.get(this)
                        val value: Any? = when(call.method) {
                            "page" -> store.page(call.argument<Number>("before")?.toLong() ?: Long.MAX_VALUE, call.argument<String>("query") ?: "")
                            "detail" -> store.detail(call.argument<Number>("id")!!.toLong())
                            else -> {
                                val enabled = Settings.Secure.getString(contentResolver, "enabled_notification_listeners").orEmpty()
                                    .split(":").any { ComponentName.unflattenFromString(it) == ComponentName(this, NotificationListener::class.java) }
                                store.stats() + mapOf("enabled" to enabled, "connected" to NotificationListener.connected,
                                    "batteryExempt" to (getSystemService(POWER_SERVICE) as PowerManager).isIgnoringBatteryOptimizations(packageName),
                                    "error" to getSharedPreferences("health", MODE_PRIVATE).getString("error", null))
                            }
                        }
                        runOnUiThread { result.success(value) }
                    } catch(e: Exception) { runOnUiThread { result.error("STORAGE", e.message, null) } }
                }
                else -> try {
                    when(call.method) {
                        "access" -> startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                        "battery" -> startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                        "settings" -> startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
                        "reconnect" -> NotificationListenerService.requestRebind(ComponentName(this, NotificationListener::class.java))
                        else -> { result.notImplemented(); return@setMethodCallHandler }
                    }
                    result.success(null)
                } catch(e: Exception) { result.error("SETTINGS", e.message, null) }
            }
        }
    }
    private fun postNotification(title: String, body: String, result: MethodChannel.Result) {
        try {
            val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= 26) {
                manager.createNotificationChannel(NotificationChannel(notificationChannelId, "Thông báo tự tạo", NotificationManager.IMPORTANCE_DEFAULT))
            }
            if (!manager.areNotificationsEnabled() || (Build.VERSION.SDK_INT >= 26 && manager.getNotificationChannel(notificationChannelId)?.importance == NotificationManager.IMPORTANCE_NONE)) {
                result.error("DISABLED", "Thông báo đang bị tắt. Hãy bật thông báo cho ứng dụng trong cài đặt Android rồi thử lại.", null)
                return
            }
            val intent = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, notificationChannelId) else Notification.Builder(this)
            val notification = builder
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(Notification.BigTextStyle().bigText(body))
                .setContentIntent(intent)
                .setAutoCancel(true)
                .build()
            manager.notify(UUID.randomUUID().toString(), 1, notification)
            result.success(null)
        } catch (e: Exception) {
            result.error("NOTIFICATION", "Không tạo được thông báo: ${e.message}", null)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != notificationPermissionRequest) return
        val pending = pendingNotification ?: return
        pendingNotification = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            postNotification(pending.first, pending.second, pending.third)
        } else {
            pending.third.error("PERMISSION", "Chưa được cấp quyền gửi thông báo. Hãy cho phép thông báo trong cài đặt ứng dụng rồi thử lại.", null)
        }
    }

    override fun onDestroy() { reader.shutdown(); super.onDestroy() }
}
