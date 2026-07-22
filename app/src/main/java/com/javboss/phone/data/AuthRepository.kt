package com.javboss.phone.data

import com.javboss.phone.data.api.ApiClient
import com.javboss.phone.data.api.dto.LoginRequest

class AuthRepository(
    private val session: SessionManager,
    private val apiClient: ApiClient,
) {
    /** 登录成功后 Cookie 由 CookieJar 自动持久化 */
    suspend fun login(serverUrl: String, password: String) {
        session.saveServerUrl(serverUrl)
        val res = apiClient.api().login(LoginRequest(password))
        if (!res.authenticated) throw IllegalStateException("登录失败")
    }

    /** 启动时校验本地会话是否仍有效 */
    suspend fun isAuthenticated(): Boolean {
        if (!session.hasSession) return false
        return runCatching { apiClient.api().authStatus().authenticated }.getOrDefault(false)
    }

    suspend fun logout() {
        runCatching { apiClient.api().logout() }
        apiClient.cookieJar.clear()
        session.clear()
    }
}
