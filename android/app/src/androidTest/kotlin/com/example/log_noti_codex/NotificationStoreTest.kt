package com.example.log_noti_codex

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class NotificationStoreTest {
    private val store = NotificationStore(InstrumentationRegistry.getInstrumentation().targetContext, "test-notifications.db")
    @Before fun reset() { store.writableDatabase.delete("notifications", null, null) }
    private fun append(index: Int, source: String = "posted", payload: String = "payload$index") =
        store.append("same-key", index.toLong(), source, "test.app", "Test", "Title$index", "Body$index", payload)

    @Test fun repeatedCallbacksArePreservedButRecoveryIsIdempotent() {
        assertTrue(append(1)); assertTrue(append(1))
        assertFalse(append(1, "recovered"))
        assertTrue(append(1, "recovered", "changed"))
        assertEquals(3L, store.stats()["count"])
    }
    @Test fun pagesDoNotSkipRowsWhenNotificationsArrive() {
        for (i in 1..121) append(i)
        val first = store.page(Long.MAX_VALUE, "")
        append(122)
        val second = store.page(first.last()["id"] as Long, "")
        val third = store.page(second.last()["id"] as Long, "")
        val all = first + second + third
        assertEquals(121, all.size)
        assertEquals(121, all.map { it["id"] }.toSet().size)
        assertEquals("Title1", all.last()["title"])
        assertEquals(1, store.page(Long.MAX_VALUE, "Title122").size)
    }
    @Test fun longUnicodePayloadSurvivesDatabaseReopen() {
        val payload = "Thông báo đầy đủ 🌿\n".repeat(5000)
        append(1, payload = payload)
        val id = store.stats()["latest"]!!
        store.close()
        assertEquals(payload, store.detail(id))
    }
}
