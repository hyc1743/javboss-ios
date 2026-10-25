package com.javboss.phone.ui.detail

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.javboss.phone.JavBossApp
import com.javboss.phone.data.api.AuthExpiredException
import com.javboss.phone.data.api.dto.FavoriteGroupDto
import com.javboss.phone.data.api.dto.IdolDto
import com.javboss.phone.data.api.dto.JavDto
import com.javboss.phone.data.api.dto.JavItemUpdateRequest
import com.javboss.phone.data.api.dto.ScreenshotDto
import com.javboss.phone.data.api.dto.SeriesDto
import com.javboss.phone.data.api.dto.StudioDto
import com.javboss.phone.data.api.dto.TagDto
import com.javboss.phone.data.api.dto.VideoDto
import kotlinx.coroutines.launch

data class DetailUiState(
    /** videoId <= 0 时为纯元数据模式（作品没有关联视频），video 保持 null */
    val video: VideoDto? = null,
    /** 通过 /jav?search=<code> 精确匹配拿到的完整元数据（含片商/标签/演员） */
    val javMeta: JavDto? = null,
    val seriesName: String = "",
    val screenshots: List<ScreenshotDto> = emptyList(),
    val loading: Boolean = true,
    val error: String? = null,
    /** 一次性提示（收藏/编辑成功失败），UI 用 Toast 展示 */
    val notice: String? = null,
    val sessionExpired: Boolean = false,
)

class DetailViewModel(app: Application) : AndroidViewModel(app) {
    private val container = (app as JavBossApp).container

    var uiState by mutableStateOf(DetailUiState())
        private set

    /**
     * @param javCode 从列表页带过来的番号；/videos/{id} 详情不内嵌 JAV 元数据，
     *   需要用它搜索 /jav 精确匹配出完整条目（对齐网页版 JavDetailModal 的数据源）
     */
    fun load(videoId: Long, javCode: String?) {
        viewModelScope.launch {
            uiState = uiState.copy(loading = true, error = null)
            try {
                var code = javCode
                if (videoId > 0) {
                    val video = container.videoRepository.getVideo(videoId)
                    uiState = uiState.copy(video = video)
                    if (code.isNullOrBlank()) code = video.jav?.code
                }

                if (!code.isNullOrBlank()) {
                    val meta = runCatching {
                        container.videoRepository.searchJavs(limit = 5, offset = 0, search = code)
                            .items.firstOrNull { it.code.equals(code, ignoreCase = true) }
                    }.getOrNull()
                    uiState = uiState.copy(javMeta = meta)

                    val sid = meta?.seriesId
                    if (sid != null && sid > 0) {
                        val series = container.videoRepository.getJavSeries(sid)
                        if (series != null) uiState = uiState.copy(seriesName = series.name)
                    }
                }

                if (videoId > 0) {
                    val shots = container.videoRepository.listVideoScreenshots(videoId)
                    uiState = uiState.copy(screenshots = shots)
                }
                uiState = uiState.copy(loading = false)
            } catch (e: AuthExpiredException) {
                uiState = uiState.copy(loading = false, sessionExpired = true)
            } catch (e: Exception) {
                uiState = uiState.copy(loading = false, error = e.message ?: "加载失败")
            }
        }
    }

    // ---------- 收藏 ----------

    /** 收藏弹窗数据：全部收藏夹 + 当前作品已选中的收藏夹 id */
    suspend fun loadFavoriteData(javId: Long): Pair<List<FavoriteGroupDto>, Set<Long>> {
        val groups = container.favoriteRepository.listGroups()
        val selected = container.favoriteRepository.selectedGroupIds(javId)
        return groups to selected.toSet()
    }

    fun saveFavorite(javId: Long, groupIds: Set<Long>) {
        viewModelScope.launch {
            try {
                container.favoriteRepository.replaceGroups(javId, groupIds.toList())
                uiState = uiState.copy(notice = "收藏已保存")
            } catch (e: AuthExpiredException) {
                uiState = uiState.copy(sessionExpired = true)
            } catch (e: Exception) {
                uiState = uiState.copy(notice = "收藏保存失败")
            }
        }
    }

    suspend fun createFavoriteGroup(name: String): FavoriteGroupDto =
        container.favoriteRepository.createGroup(name)

    // ---------- 编辑 ----------

    data class EditOptions(
        val studios: List<StudioDto> = emptyList(),
        val series: List<SeriesDto> = emptyList(),
        val tags: List<TagDto> = emptyList(),
    )

    suspend fun loadEditOptions(): EditOptions {
        val studios = runCatching {
            container.videoRepository.listJavStudios(limit = 500, offset = 0).items
        }.getOrDefault(emptyList())
        val series = runCatching {
            container.videoRepository.listJavSeries(limit = 500, offset = 0).items
        }.getOrDefault(emptyList())
        val tags = runCatching {
            container.videoRepository.listJavTags()
        }.getOrDefault(emptyList())
        return EditOptions(studios, series, tags)
    }

    suspend fun searchIdols(query: String): List<IdolDto> =
        runCatching {
            container.videoRepository.listJavIdols(limit = 8, offset = 0, search = query).items
        }.getOrDefault(emptyList())

    suspend fun createTag(name: String): TagDto =
        container.videoRepository.createJavTag(name)

    fun saveEdit(javId: Long, request: JavItemUpdateRequest) {
        viewModelScope.launch {
            try {
                val updated = container.videoRepository.updateJavItem(javId, request)
                var seriesName = uiState.seriesName
                val sid = updated.seriesId
                if (sid != null && sid > 0 && sid != uiState.javMeta?.seriesId) {
                    seriesName = container.videoRepository.getJavSeries(sid)?.name ?: seriesName
                } else if (sid == null || sid <= 0) {
                    seriesName = ""
                }
                uiState = uiState.copy(javMeta = updated, seriesName = seriesName, notice = "已保存")
            } catch (e: AuthExpiredException) {
                uiState = uiState.copy(sessionExpired = true)
            } catch (e: Exception) {
                uiState = uiState.copy(notice = "保存失败：${e.message ?: "未知错误"}")
            }
        }
    }

    // ---------- 外部链接 ----------

    suspend fun resolveJavDbUrl(code: String): String? =
        container.videoRepository.getJavDbUrl(code)

    // ---------- 工具 ----------

    fun coverUrl(): String? {
        val code = uiState.javMeta?.code ?: uiState.video?.jav?.code
        return code?.takeIf { it.isNotBlank() }?.let { container.apiClient.javCoverUrl(it) }
            ?: uiState.video?.let { container.apiClient.videoThumbnailUrl(it.id) }
    }

    fun screenshotUrl(videoId: Long, name: String): String =
        container.apiClient.videoScreenshotUrl(videoId, name)

    fun consumeNotice() {
        uiState = uiState.copy(notice = null)
    }
}
