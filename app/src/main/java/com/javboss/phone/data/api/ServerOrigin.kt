package com.javboss.phone.data.api

import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

/** 受会话保护的请求只能发往用户当前配置的同源 JavBoss 服务。 */
internal object ServerOrigin {
    fun matches(serverUrl: String, candidateUrl: String): Boolean {
        val server = serverUrl.toHttpUrlOrNull() ?: return false
        val candidate = candidateUrl.toHttpUrlOrNull() ?: return false
        return candidate.scheme == server.scheme &&
            candidate.host == server.host &&
            candidate.port == server.port
    }
}
