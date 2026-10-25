package com.javboss.phone.data

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.first

private val Context.dataStore by preferencesDataStore(name = "session")

/**
 * 会话持久化：服务器地址 + 登录 Cookie。
 * 服务端会话有效期 14 天且每 24h 自动续期，所以本地只要跟着存最新 Cookie 即可。
 */
class SessionManager(private val context: Context) {

    private val keyServerUrl = stringPreferencesKey("server_url")
    private val keyCookie = stringPreferencesKey("cookie_header")

    @Volatile
    var serverUrl: String = ""
        private set

    @Volatile
    var cookieHeader: String = ""
        private set

    val hasSession: Boolean get() = serverUrl.isNotBlank() && cookieHeader.isNotBlank()

    /** App 启动时从 DataStore 恢复（阻塞读一次，量在字节级，可接受） */
    suspend fun restore() {
        val prefs = context.dataStore.data.first()
        serverUrl = prefs[keyServerUrl] ?: ""
        cookieHeader = prefs[keyCookie] ?: ""
    }

    suspend fun saveServerUrl(url: String) {
        var normalized = url.trim().trimEnd('/')
        // 遥控器输入从简：没带协议头时自动补 http://
        if (normalized.isNotBlank() && !normalized.startsWith("http://") && !normalized.startsWith("https://")) {
            normalized = "http://$normalized"
        }
        serverUrl = normalized
        context.dataStore.edit { it[keyServerUrl] = normalized }
    }

    suspend fun saveCookie(header: String) {
        cookieHeader = header
        context.dataStore.edit { it[keyCookie] = header }
    }

    suspend fun clear() {
        serverUrl = ""
        cookieHeader = ""
        context.dataStore.edit {
            it.remove(keyServerUrl)
            it.remove(keyCookie)
        }
    }
}
