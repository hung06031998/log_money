package com.example.log_noti_codex

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

/** Append-only journal. A posted callback is never deduplicated or overwritten. */
class NotificationStore internal constructor(context: Context, databaseName: String = "notifications.db") : SQLiteOpenHelper(context, databaseName, null, 1) {
    companion object {
        @Volatile private var instance: NotificationStore? = null
        fun get(context: Context): NotificationStore = instance ?: synchronized(this) {
            instance ?: NotificationStore(context.applicationContext).also { instance = it }
        }
    }
    override fun onConfigure(db: SQLiteDatabase) {
        // Commit the journal before returning from the listener callback.
        db.execSQL("PRAGMA synchronous=FULL")
    }
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("""CREATE TABLE notifications (
            id INTEGER PRIMARY KEY AUTOINCREMENT, notification_key TEXT NOT NULL,
            posted INTEGER NOT NULL, received INTEGER NOT NULL, source TEXT NOT NULL,
            package_name TEXT NOT NULL, app_name TEXT NOT NULL, title TEXT NOT NULL,
            body TEXT NOT NULL, payload TEXT NOT NULL)""")
        db.execSQL("CREATE INDEX notification_identity ON notifications(notification_key, posted)")
    }
    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit

    @Synchronized fun append(key: String, posted: Long, source: String, pkg: String,
        app: String, title: String, body: String, payload: String): Boolean {
        val db = writableDatabase
        // Reconnection snapshots only: skip an exact previously archived snapshot.
        if (source == "recovered") {
            db.rawQuery("SELECT 1 FROM notifications WHERE notification_key=? AND posted=? AND payload=? LIMIT 1",
                arrayOf(key, posted.toString(), payload)).use { if (it.moveToFirst()) return false }
        }
        val values = ContentValues().apply {
            put("notification_key", key); put("posted", posted); put("received", System.currentTimeMillis())
            put("source", source); put("package_name", pkg); put("app_name", app)
            put("title", title); put("body", body); put("payload", payload)
        }
        db.insertOrThrow("notifications", null, values)
        return true
    }
    fun page(before: Long, query: String): List<Map<String, Any>> {
        val rows = mutableListOf<Map<String, Any>>()
        readableDatabase.rawQuery("""SELECT id, app_name, package_name, title, body, posted, received, source
            FROM notifications WHERE id < ? AND
            (instr(lower(app_name),lower(?))>0 OR instr(lower(package_name),lower(?))>0 OR
             instr(lower(title),lower(?))>0 OR instr(lower(body),lower(?))>0)
            ORDER BY id DESC LIMIT 50""", arrayOf(before.toString(), query, query, query, query)).use { c ->
            while(c.moveToNext()) rows.add(mapOf("id" to c.getLong(0), "app" to c.getString(1),
                "package" to c.getString(2), "title" to c.getString(3), "body" to c.getString(4),
                "posted" to c.getLong(5), "received" to c.getLong(6), "source" to c.getString(7)))
        }
        return rows
    }
    fun detail(id: Long): String? = readableDatabase.rawQuery("SELECT payload FROM notifications WHERE id=?", arrayOf(id.toString())).use {
        if (it.moveToFirst()) it.getString(0) else null
    }
    fun stats(): Map<String, Long> = readableDatabase.rawQuery("SELECT count(*), coalesce(max(id),0) FROM notifications", null).use {
        it.moveToFirst(); mapOf("count" to it.getLong(0), "latest" to it.getLong(1))
    }
}
