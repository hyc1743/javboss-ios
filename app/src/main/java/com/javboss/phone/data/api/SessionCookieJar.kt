package com.javboss.phone.data.api

import com.javboss.phone.data.SessionManager
import okhttp3.Cookie
import okhttp3.CookieJar
import okhttp3.HttpUrl

/**
 * 极简 CookieJar：内存保存当前 JavBoss 服务端的会话 Cookie，并把 Cookie 头持久化到 DataStore。
 *
 * 客户端只需要服务端会话 Cookie，但必须严格限制为当前配置的同源请求：Coil 和
 * libVLC 代理共用这个客户端，绝不能把会话带到外部封面、跳转地址或其他服务器。
 */
class SessionCookieJar(private val session: SessionManager) : CookieJar {

    private val store = java.util.concurrent.ConcurrentHashMap<String, String>()

    /** 启动时从持久化的 Cookie 头恢复 */
    fun restoreFromSession() {
        if (session.cookieHeader.isBlank()) return
        session.cookieHeader.split("; ").forEach { pair ->
            val idx = pair.indexOf('=')
            if (idx > 0) store[pair.substring(0, idx)] = pair.substring(idx + 1)
        }
    }

    fun cookieHeader(): String =
        store.entries.joinToString("; ") { "${it.key}=${it.value}" }

    fun clear() = store.clear()

    private fun isServerOrigin(url: HttpUrl): Boolean {
        return ServerOrigin.matches(session.serverUrl, url.toString())
    }

    override fun saveFromResponse(url: HttpUrl, cookies: List<Cookie>) {
        if (cookies.isEmpty() || !isServerOrigin(url)) return
        var changed = false
        for (cookie in cookies) {
            if (cookie.expiresAt < System.currentTimeMillis()) {
                changed = store.remove(cookie.name) != null || changed
            } else {
                store[cookie.name] = cookie.value
                changed = true
            }
        }
        if (changed) {
            // CookieJar 回调在 IO 线程，允许阻塞写一次 DataStore
            kotlinx.coroutines.runBlocking { session.saveCookie(cookieHeader()) }
        }
    }

    override fun loadForRequest(url: HttpUrl): List<Cookie> {
        if (store.isEmpty() || !isServerOrigin(url)) return emptyList()
        return store.map { (name, value) ->
            Cookie.Builder()
                .name(name)
                .value(value)
                .hostOnlyDomain(url.host)
                .path("/")
                .build()
        }
    }
}
