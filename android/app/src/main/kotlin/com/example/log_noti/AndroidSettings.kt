package com.example.log_noti

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Android storage/Keystore adapter. Validation and filter policy live in Dart. */
class AndroidSettings(private val context: Context) {
    private val prefs get() = context.getSharedPreferences("notification_filter", Context.MODE_PRIVATE)
    fun read(): Map<String, Any?> = mapOf(
        "includes" to prefs.getString("includes", ""),
        "excludes" to prefs.getString("excludes", ""),
        "apiKey" to readKey(),
        "model" to prefs.getString("model", null),
    )
    fun write(values: Map<String, String>) {
        check(prefs.edit().putString("includes", values["includes"])
            .putString("excludes", values["excludes"])
            .putString("key", encrypt(values["apiKey"].orEmpty()))
            .putString("model", values["model"]).commit())
    }
    private fun secretKey(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey("notification_gemini", null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder("notification_gemini", KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }

    private fun encrypt(value: String): String {
        if (value.isBlank()) return ""
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        return Base64.encodeToString(cipher.iv + cipher.doFinal(value.toByteArray(Charsets.UTF_8)), Base64.NO_WRAP)
    }

    private fun readKey(): String = try {
        val encoded = prefs.getString("key", "").orEmpty()
        if (encoded.isBlank()) "" else {
            val bytes = Base64.decode(encoded, Base64.NO_WRAP)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
            String(cipher.doFinal(bytes.copyOfRange(12, bytes.size)), Charsets.UTF_8)
        }
    } catch (_: Exception) { "" }

}
