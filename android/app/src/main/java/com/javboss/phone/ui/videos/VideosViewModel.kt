package com.javboss.phone.ui.videos

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.javboss.phone.JavBossApp
import com.javboss.phone.data.api.AuthExpiredException
import com.javboss.phone.data.api.dto.VideoDto
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** 与网页版一致的视频排序选项（见 web/src/constants/video.js） */
enum class VideoSort(val label: String, val value: String) {
    RECENT("最近加入", "recent"),
    RECENT_ASC("最早加入", "recent_asc"),
    DURATION("时长 长→短", "duration"),
    DURATION_ASC("时长 短→长", "duration_asc"),
    PLAY_COUNT("播放 多→少", "play_count"),
    PLAY_COUNT_ASC("播放 少→多", "play_count_asc"),
    FILENAME("文件名 A→Z", "filename"),
    FILENAME_DESC("文件名 Z→A", "filename_desc"),
}

data class VideosUiState(
    val videos: List<VideoDto> = emptyList(),
    val total: Int = 0,
    val loading: Boolean = false,
    val loadingMore: Boolean = false,
    val endReached: Boolean = false,
    val search: String = "",
    val sort: VideoSort = VideoSort.RECENT,
    val error: String? = null,
    val sessionExpired: Boolean = false,
)

class VideosViewModel(app: Application) : AndroidViewModel(app) {
    private val container = (app as JavBossApp).container

    var uiState by mutableStateOf(VideosUiState())
        private set

    private var searchJob: Job? = null

    init {
        refresh()
    }

    private suspend fun fetch(limit: Int, offset: Int) =
        container.videoRepository.listVideos(
            limit = limit,
            offset = offset,
            search = uiState.search,
            sort = uiState.sort.value,
        )

    fun refresh() {
        viewModelScope.launch {
            uiState = uiState.copy(loading = true, error = null)
            try {
                val res = fetch(PAGE_SIZE, 0)
                uiState = uiState.copy(
                    videos = res.items,
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
                val res = fetch(PAGE_SIZE, s.videos.size)
                // 服务端排序键不稳定时跨页可能返回重复 id，合并时按 id 去重
                val merged = (s.videos + res.items).distinctBy { it.id }
                uiState = uiState.copy(
                    videos = merged,
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

    /** 搜索防抖：停止输入 400ms 后触发 */
    fun onSearchChange(value: String) {
        uiState = uiState.copy(search = value)
        searchJob?.cancel()
        searchJob = viewModelScope.launch {
            delay(400)
            refresh()
        }
    }

    fun onSortChange(sort: VideoSort) {
        if (sort == uiState.sort) return
        uiState = uiState.copy(sort = sort)
        refresh()
    }

    fun thumbnailUrl(videoId: Long): String =
        container.apiClient.videoThumbnailUrl(videoId)

    companion object {
        const val PAGE_SIZE = 24
    }
}
