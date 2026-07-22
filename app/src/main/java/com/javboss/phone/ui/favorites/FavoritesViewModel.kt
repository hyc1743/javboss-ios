package com.javboss.phone.ui.favorites

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.javboss.phone.JavBossApp
import com.javboss.phone.data.api.AuthExpiredException
import com.javboss.phone.data.api.dto.FavoriteGroupDto
import com.javboss.phone.data.api.dto.FavoriteItemDto
import kotlinx.coroutines.launch

data class FavoritesUiState(
    val groups: List<FavoriteGroupDto> = emptyList(),
    val loading: Boolean = false,
    val error: String? = null,
    /** 操作失败（创建/重命名/删除）的提示信息，UI 用 Toast 展示 */
    val notice: String? = null,
    val sessionExpired: Boolean = false,
)

class FavoritesViewModel(app: Application) : AndroidViewModel(app) {
    private val container = (app as JavBossApp).container

    var uiState by mutableStateOf(FavoritesUiState())
        private set

    init {
        refresh()
    }

    fun refresh() {
        viewModelScope.launch {
            uiState = uiState.copy(loading = true, error = null)
            try {
                val groups = container.favoriteRepository.listGroups()
                uiState = uiState.copy(groups = groups, loading = false)
            } catch (e: AuthExpiredException) {
                uiState = uiState.copy(loading = false, sessionExpired = true)
            } catch (e: Exception) {
                uiState = uiState.copy(loading = false, error = e.message ?: "加载失败")
            }
        }
    }

    fun createGroup(name: String) {
        if (name.isBlank()) return
        viewModelScope.launch {
            try {
                container.favoriteRepository.createGroup(name.trim())
                refresh()
            } catch (e: AuthExpiredException) {
                uiState = uiState.copy(sessionExpired = true)
            } catch (e: Exception) {
                uiState = uiState.copy(notice = "创建失败：名称可能为空或已存在")
            }
        }
    }

    fun renameGroup(id: Long, name: String) {
        if (name.isBlank()) return
        viewModelScope.launch {
            try {
                container.favoriteRepository.renameGroup(id, name.trim())
                refresh()
            } catch (e: AuthExpiredException) {
                uiState = uiState.copy(sessionExpired = true)
            } catch (e: Exception) {
                uiState = uiState.copy(notice = "重命名失败：名称可能为空或已存在")
            }
        }
    }

    fun deleteGroup(id: Long) {
        viewModelScope.launch {
            try {
                container.favoriteRepository.deleteGroup(id)
                refresh()
            } catch (e: AuthExpiredException) {
                uiState = uiState.copy(sessionExpired = true)
            } catch (e: Exception) {
                uiState = uiState.copy(notice = "删除失败")
            }
        }
    }

    fun consumeNotice() {
        uiState = uiState.copy(notice = null)
    }
}

// ---------- 收藏夹详情 ----------

data class FavGroupUiState(
    val items: List<FavoriteItemDto> = emptyList(),
    val loading: Boolean = false,
    val error: String? = null,
    val notice: String? = null,
    val sessionExpired: Boolean = false,
)

class FavGroupViewModel(app: Application) : AndroidViewModel(app) {
    private val container = (app as JavBossApp).container

    var uiState by mutableStateOf(FavGroupUiState())
        private set

    fun load(groupId: Long) {
        viewModelScope.launch {
            uiState = uiState.copy(loading = true, error = null)
            try {
                val items = container.favoriteRepository.listItems(groupId)
                uiState = uiState.copy(items = items, loading = false)
            } catch (e: AuthExpiredException) {
                uiState = uiState.copy(loading = false, sessionExpired = true)
            } catch (e: Exception) {
                uiState = uiState.copy(loading = false, error = e.message ?: "加载失败")
            }
        }
    }

    fun removeItem(groupId: Long, item: FavoriteItemDto) {
        viewModelScope.launch {
            try {
                container.favoriteRepository.removeItems(groupId, listOf(item.id))
                uiState = uiState.copy(items = uiState.items.filterNot { it.id == item.id })
            } catch (e: AuthExpiredException) {
                uiState = uiState.copy(sessionExpired = true)
            } catch (e: Exception) {
                uiState = uiState.copy(notice = "移除失败")
            }
        }
    }

    /**
     * 收藏夹条目只有番号没有视频 id，点击时用番号搜 /jav 找关联视频；
     * 找不到视频时 videoId=0，详情页降级为纯元数据展示
     */
    fun openItem(item: FavoriteItemDto, onResolved: (videoId: Long, code: String) -> Unit) {
        viewModelScope.launch {
            try {
                val jav = container.videoRepository.searchJavs(limit = 5, offset = 0, search = item.code)
                    .items.firstOrNull { it.code.equals(item.code, ignoreCase = true) }
                onResolved(jav?.videos?.firstOrNull()?.id ?: 0, item.code)
            } catch (e: AuthExpiredException) {
                uiState = uiState.copy(sessionExpired = true)
            } catch (e: Exception) {
                onResolved(0, item.code)
            }
        }
    }

    fun coverUrl(code: String): String? =
        code.takeIf { it.isNotBlank() }?.let { container.apiClient.javCoverUrl(it) }

    fun consumeNotice() {
        uiState = uiState.copy(notice = null)
    }
}
