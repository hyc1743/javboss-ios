package com.javboss.phone.ui.player

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.javboss.phone.JavBossApp
import kotlinx.coroutines.launch

data class PlayerUiState(
    val urls: List<String> = emptyList(),
    val loading: Boolean = true,
    val error: String? = null,
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
}
