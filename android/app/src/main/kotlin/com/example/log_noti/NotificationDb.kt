package com.example.log_noti

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.util.concurrent.Executors

/** Generic SQLite transport plus a durable inbox while the Dart engine starts.
 * Application schema, migration, queries and deduplication are owned by Dart.
 */
class NotificationDb private constructor(context: Context) {
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val db by lazy {
        val app = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N)
            context.createDeviceProtectedStorageContext() else context
        app.openOrCreateDatabase("notification_log.db", Context.MODE_PRIVATE, null).apply {
            enableWriteAheadLogging()
            execSQL("CREATE TABLE IF NOT EXISTS native_inbox (id INTEGER PRIMARY KEY AUTOINCREMENT, payload TEXT NOT NULL, snapshot INTEGER NOT NULL)")
        }
    }

    fun enqueue(row: Map<String, Any?>, snapshot: Boolean, done: () -> Unit) {
        executor.execute {
            db.insertOrThrow("native_inbox", null, ContentValues().apply {
                put("payload", JSONObject(row).toString())
                put("snapshot", if (snapshot) 1 else 0)
            })
            main.post { done() }
        }
    }

    fun execute(statements: List<Map<String, Any?>>, result: MethodChannel.Result) {
        executor.execute {
            try {
                db.beginTransaction()
                try {
                    for (statement in statements) {
                        val args = statement["args"] as? List<*> ?: emptyList<Any?>()
                        db.execSQL(statement["sql"] as String, args.toTypedArray())
                    }
                    db.setTransactionSuccessful()
                } finally { db.endTransaction() }
                main.post { result.success(null) }
            } catch (_: Exception) {
                main.post { result.error("database", "Không ghi được dữ liệu SQLite.", null) }
            }
        }
    }

    fun query(sql: String, args: List<*>, result: MethodChannel.Result) {
        executor.execute {
            try {
                val rows = db.rawQuery(sql, args.map { it?.toString() ?: "" }.toTypedArray()).use { cursor ->
                    val output = mutableListOf<Map<String, Any?>>()
                    while (cursor.moveToNext()) {
                        output.add(cursor.columnNames.mapIndexed { index, name ->
                            name to when (cursor.getType(index)) {
                                Cursor.FIELD_TYPE_NULL -> null
                                Cursor.FIELD_TYPE_INTEGER -> cursor.getLong(index)
                                Cursor.FIELD_TYPE_FLOAT -> cursor.getDouble(index)
                                Cursor.FIELD_TYPE_BLOB -> cursor.getBlob(index)
                                else -> cursor.getString(index)
                            }
                        }.toMap())
                    }
                    output
                }
                main.post { result.success(rows) }
            } catch (_: Exception) {
                main.post { result.error("database", "Không đọc được dữ liệu SQLite.", null) }
            }
        }
    }

    companion object {
        @Volatile private var instance: NotificationDb? = null
        fun get(context: Context): NotificationDb = instance ?: synchronized(this) {
            instance ?: NotificationDb(context.applicationContext).also { instance = it }
        }
    }
}
