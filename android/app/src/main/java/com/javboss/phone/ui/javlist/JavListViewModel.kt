package com.javboss.phone.ui.javlist

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.javboss.phone.JavBossApp
import com.javboss.phone.data.api.AuthExpiredException
import com.javboss.phone.data.api.dto.JavDto
import kotlinx.coroutines.launch

data class JavListUiState(
    val items: List<JavDto> = emptyList(),
    val total: Int = 0,
    val loading: Boolean = false,
    val loadingMore: Boolean = false,
    val endReached: Boolean = false,
    val error: String? = null,
    val sessionExpired: Boolean = false,
)

/** 演员/标签/片商/系列点击后的过滤作品列表 */
class JavListViewModel(app: Application) : AndroidViewModel(app) {
    private val container = (app as JavBossApp).container

    var uiState by mutableStateOf(JavListUiState())
        private set

    private var idolIds: List<Long> = emptyList()
    private var tagIds: List<Long> = emptyList()
    private var studioId: Long? = null
    private var seriesId: Long? = null

    private var started = false

    fun start(idolIds: String, tagIds: String, studioId: Long, seriesId: Long) {
        if (started) return
        started = true
        this.idolIds = idolIds.split(',').mapNotNull { it.trim().toLongOrNull() }
        this.tagIds = tagIds.split(',').mapNotNull { it.trim().toLongOrNull() }
        this.studioId = studioId.takeIf { it > 0 }
        this.seriesId = seriesId.takeIf { it > 0 }
        refresh()
    }

    private suspend fun fetch(limit: Int, offset: Int) =
        container.videoRepository.searchJavs(
            limit = limit,
            offset = offset,
            idolIds = idolIds,
            tagIds = tagIds,
            studioId = studioId,
            seriesId = seriesId,
            sort = "recent",
        )

    fun refresh() {
        viewModelScope.launch {
            uiState = uiState.copy(loading = true, error = null)
            try {
                val res = fetch(PAGE_SIZE, 0)
                uiState = uiState.copy(
                    items = res.items,
                    total = res.total,
                    loading = false,
                    endReached = res.items.size >= res.total,
                )
            } catch (e: AuthExpiredException) {
                uiState = uiState.copy(loading = false, sessionExpired = true)
            } catch (e: Exception) {
                uiState = uiState.copy(loading = false, error = e.message ?: "加载失败")
            }
        }
    }

    fun loadMore() {
        val s = uiState
        if (s.loading || s.loadingMore || s.endReached) return
        viewModelScope.launch {
            uiState = uiState.copy(loadingMore = true)
            try {
                val res = fetch(PAGE_SIZE, s.items.size)
                val merged = (s.items + res.items).distinctBy { it.id }
                uiState = uiState.copy(
                    items = merged,
                    total = res.total,
                    loadingMore = false,
                    endReached = merged.size >= res.total || res.items.isEmpty(),
                )
            } catch (e: AuthExpiredException) {
                uiState = uiState.copy(loadingMore = false, sessionExpired = true)
            } catch (e: Exception) {
                uiState = uiState.copy(loadingMore = false, error = e.message ?: "加载失败")
            }
        }
    }

    fun coverUrl(code: String): String = container.apiClient.javCoverUrl(code)

    companion object {
        const val PAGE_SIZE = 24
    }
}
