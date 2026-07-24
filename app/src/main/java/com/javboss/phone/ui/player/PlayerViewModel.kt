package com.javboss.phone.ui.player

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.javboss.phone.JavBossApp
import com.javboss.phone.data.EngineMode
import kotlinx.coroutines.launch

data class PlayerUiState(
    val urls: List<String> = emptyList(),
    val loading: Boolean = true,
    val error: String? = null,
    /** 用户设置的引擎偏好（自动 / 仅 ExoPlayer / 仅 libVLC） */
    val engineMode: EngineMode = EngineMode.AUTO,
    /** 当前实际使用的引擎（AUTO 模式下失败可从 EXO 切到 VLC） */
    val activeEngine: EngineMode = EngineMode.EXO,
    /** 切引擎时的续播起点（上个引擎失败时的进度） */
    val fallbackPositionMs: Long = 0,
)

class PlayerViewModel(app: Application) : AndroidViewModel(app) {
    private val container = (app as JavBossApp).container

    var uiState by mutableStateOf(PlayerUiState())
        private set

    val cookieHeader: String get() = container.cookieJar.cookieHeader()

    fun load(videoId: Long) {
        viewModelScope.launch {
            try {
                val urls = container.videoRepository.resolvePlayUrls(videoId)
                if (urls.isEmpty()) {
                    uiState = PlayerUiState(loading = false, error = "没有可用的播放源")
                } else {
                    val mode = container.settings.engineMode
                    uiState = PlayerUiState(
                        urls = urls,
                        loading = false,
                        engineMode = mode,
                        activeEngine = if (mode == EngineMode.VLC) EngineMode.VLC else EngineMode.EXO,
                    )
                    container.videoRepository.reportPlay(videoId)
                }
            } catch (e: Exception) {
                uiState = PlayerUiState(loading = false, error = e.message ?: "获取播放源失败")
            }
        }
    }

    /** AUTO 模式下 ExoPlayer 全部源失败 → 切 libVLC 引擎，从失败进度续播 */
    fun switchToVlc(startPositionMs: Long) {
        uiState = uiState.copy(activeEngine = EngineMode.VLC, fallbackPositionMs = startPositionMs)
    }

    /** 播放页内切换引擎偏好，立即从当前进度重建对应引擎。 */
    fun selectEngineMode(mode: EngineMode, positionMs: Long) {
        viewModelScope.launch { container.settings.saveEngineMode(mode) }
        uiState = uiState.copy(
            engineMode = mode,
            activeEngine = if (mode == EngineMode.VLC) EngineMode.VLC else EngineMode.EXO,
            fallbackPositionMs = positionMs,
        )
    }

    /** libVLC 经本地代理播放（代理负责附加会话 Cookie） */
    fun proxyUrl(url: String): String = container.authProxy.proxyUrl(url)

    /** 播放终态失败 */
    fun failPlayback(message: String) {
        uiState = uiState.copy(error = message)
    }
}
