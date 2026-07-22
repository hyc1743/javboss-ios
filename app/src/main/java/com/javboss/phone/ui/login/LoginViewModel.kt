package com.javboss.phone.ui.login

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.javboss.phone.JavBossApp
import com.javboss.phone.data.api.AuthExpiredException
import kotlinx.coroutines.launch
import retrofit2.HttpException
import java.io.IOException

data class LoginUiState(
    val serverUrl: String = "",
    val password: String = "",
    val loading: Boolean = false,
    val error: String? = null,
)

class LoginViewModel(app: Application) : AndroidViewModel(app) {
    private val container = (app as JavBossApp).container

    var uiState by mutableStateOf(
        LoginUiState(
            // 自用默认配置：没存过地址时预填默认服务器和密码
            serverUrl = container.session.serverUrl.ifBlank { DEFAULT_SERVER_URL },
            password = DEFAULT_PASSWORD,
        )
    )
        private set

    fun onServerUrlChange(value: String) {
        uiState = uiState.copy(serverUrl = value, error = null)
    }

    fun onPasswordChange(value: String) {
        uiState = uiState.copy(password = value, error = null)
    }

    fun login(onSuccess: () -> Unit) {
        val url = uiState.serverUrl.trim()
        if (url.isBlank()) {
            uiState = uiState.copy(error = "请填写服务器地址，例如 http://192.168.1.10:8655")
            return
        }
        if (uiState.password.isBlank()) {
            uiState = uiState.copy(error = "请填写密码")
            return
        }
        viewModelScope.launch {
            uiState = uiState.copy(loading = true, error = null)
            try {
                container.authRepository.login(url, uiState.password)
                uiState = uiState.copy(loading = false)
                onSuccess()
            } catch (e: Exception) {
                val message = when (e) {
                    is HttpException -> {
                        val body = runCatching { e.response()?.errorBody()?.string() }.getOrNull()
                        if (e.code() == 429) "尝试次数过多，请稍后再试"
                        else container.apiClient.parseError(body)
                    }
                    is IOException -> "无法连接服务器，请检查地址和网络"
                    is AuthExpiredException -> "登录状态异常，请重试"
                    else -> e.message ?: "登录失败"
                }
                uiState = uiState.copy(loading = false, error = message)
            }
        }
    }

    companion object {
        private const val DEFAULT_SERVER_URL = "http://192.168.1.1:8655"
        private const val DEFAULT_PASSWORD = "admin"
    }
}
