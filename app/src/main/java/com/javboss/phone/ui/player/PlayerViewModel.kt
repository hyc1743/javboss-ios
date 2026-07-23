package com.javboss.phone.ui.player

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.javboss.phone.JavBossApp
import kotlinx.coroutines.launch

enum class PlayerEngine { EXO, VLC }

data class PlayerUiState(
    val urls: List<String> = emptyList(),
    val loading: Boolean = true,
    val error: String? = null,
    val engine: PlayerEngine = PlayerEngine.EXO,
    /** 切到 VLC 引擎时的续播起点（ExoPlayer 失败时的进度） */
    val vlcStartPositionMs: Long = 0,
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
                    uiState = PlayerUiState(urls = urls, loading = false)
                    container.videoRepository.reportPlay(videoId)
                }
            } catch (e: Exception) {
                uiState = PlayerUiState(loading = false, error = e.message ?: "获取播放源失败")
            }
        }
    }

    /** ExoPlayer 全部源失败 → 切 libVLC 引擎，从失败进度续播 */
    fun switchToVlc(startPositionMs: Long) {
        uiState = uiState.copy(engine = PlayerEngine.VLC, vlcStartPositionMs = startPositionMs)
    }

    /** libVLC 经本地代理播放（代理负责附加会话 Cookie） */
    fun proxyUrl(url: String): String = container.authProxy.proxyUrl(url)

    /** 两个引擎都失败后的终态 */
    fun failPlayback(message: String) {
        uiState = uiState.copy(error = message)
    }
}
