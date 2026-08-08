package com.javboss.phone.data

import com.javboss.phone.data.api.ApiClient
import com.javboss.phone.data.api.dto.LoginRequest

class AuthRepository(
    private val session: SessionManager,
    private val apiClient: ApiClient,
) {
    /** 登录成功后 Cookie 由 CookieJar 自动持久化。切换服务器前先清除旧会话，避免跨服务器复用。 */
    suspend fun login(serverUrl: String, password: String) {
        apiClient.cookieJar.clear()
        session.saveCookie("")
        session.saveServerUrl(serverUrl)
        val res = apiClient.api().login(LoginRequest(password))
        if (!res.authenticated) throw IllegalStateException("登录失败")
    }

    /** 启动时校验本地会话是否仍有效 */
    suspend fun isAuthenticated(): Boolean {
        if (!session.hasSession) return false
        return runCatching { apiClient.api().authStatus().authenticated }.getOrDefault(false)
    }

    /** 通知服务端销毁会话。失败忽略，供登出时后台 fire-and-forget 调用。 */
    suspend fun notifyServerLogout() {
        runCatching { apiClient.api().logout() }
    }

    /** 立即清除本地会话（内存 Cookie + DataStore），不依赖网络 */
    suspend fun clearLocalSession() {
        apiClient.cookieJar.clear()
        session.clear()
    }
}
