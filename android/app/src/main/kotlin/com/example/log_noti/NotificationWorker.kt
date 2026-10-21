package com.example.log_noti

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.UserManager
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** One headless Dart engine per process; survives Activity disposal. */
object NotificationWorker {
    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private var ready = false
    private val pending = mutableListOf<Pair<MethodCall, MethodChannel.Result>>()
    private val main = Handler(Looper.getMainLooper())

    fun start(context: Context) {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            main.post { start(context.applicationContext) }
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N &&
            !context.getSystemService(UserManager::class.java).isUserUnlocked) return
        if (engine != null) {
            if (ready) channel?.invokeMethod("drain", null)
            return
        }
        val app = context.applicationContext
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(app)
        loader.ensureInitializationComplete(app, null)
        val worker = FlutterEngine(app)
        engine = worker
        val bridge = MethodChannel(worker.dartExecutor.binaryMessenger, "com.example.log_noti/worker")
        channel = bridge
        val settings = AndroidSettings(app)
        bridge.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "ready" -> {
                        ready = true
                        result.success(null)
                        pending.toList().also { pending.clear() }.forEach { (request, reply) ->
                            bridge.invokeMethod(request.method, request.arguments, reply)
                        }
                        bridge.invokeMethod("drain", null)
                    }
                    "query" -> NotificationDb.get(app).query(
                        call.argument<String>("sql")!!,
                        call.argument<List<Any?>>("args") ?: emptyList<Any?>(), result)
                    "execute" -> NotificationDb.get(app).execute(
                        call.argument<List<Map<String, Any?>>>("statements")!!, result)
                    "readSettings" -> result.success(settings.read())
                    "writeSettings" -> {
                        settings.write(call.arguments as Map<String, String>)
                        result.success(null)
                    }
                    "emit" -> {
                        NotificationEvents.emit(call.arguments as Map<String, Any?>)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                result.error("native", "Không thực hiện được thao tác Android.", null)
            }
        }
        worker.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "notificationWorkerMain"))
    }

    fun call(context: Context, call: MethodCall, result: MethodChannel.Result) {
        start(context)
        if (engine == null) {
            result.error("locked", "Hãy mở khóa thiết bị trước.", null)
        } else if (ready) {
            channel!!.invokeMethod(call.method, call.arguments, result)
        } else {
            pending.add(call to result)
        }
    }
}
