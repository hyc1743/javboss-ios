package com.javboss.phone.data.api

import com.javboss.phone.data.SessionManager
import okhttp3.Cookie
import okhttp3.CookieJar
import okhttp3.HttpUrl

/**
 * 极简 CookieJar：内存保存服务端 Set-Cookie，并把整个 Cookie 头持久化到 DataStore。
 *
 * 服务端只有会话 Cookie（javboss_session*），单用户场景下不需要按 domain/path 精细管理。
 * OkHttp、Coil（封面图）、ExoPlayer（视频流）共用同一份 Cookie。
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

    override fun saveFromResponse(url: HttpUrl, cookies: List<Cookie>) {
        if (cookies.isEmpty()) return
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
        if (store.isEmpty()) return emptyList()
        return store.map { (name, value) ->
            Cookie.Builder()
                .name(name)
                .value(value)
                .domain(url.host)
                .build()
        }
    }
}
