package com.javboss.phone.ui.main

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Collections
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.javboss.phone.ui.favorites.FavoritesScreen
import com.javboss.phone.ui.videos.VideosScreen
import com.javboss.phone.ui.works.WorksScreen

/**
 * 主页：底部三 tab（视频 / 作品 / 收藏夹）。
 * tab 切换只是本地状态，ViewModel 挂在 main 路由的 NavBackStackEntry 上，
 * 切 tab 不丢滚动位置和已加载数据。
 */
@Composable
fun MainScreen(
    onOpenDetail: (videoId: Long, code: String?) -> Unit,
    onOpenJavList: (title: String, idolIds: String, tagIds: String, studioId: Long, seriesId: Long) -> Unit,
    onFavGroupClick: (groupId: Long, name: String) -> Unit,
    onSessionExpired: () -> Unit,
) {
    var tab by rememberSaveable { mutableIntStateOf(0) }

    Scaffold(
        bottomBar = {
            NavigationBar {
                NavigationBarItem(
                    selected = tab == 0,
                    onClick = { tab = 0 },
                    icon = { Icon(Icons.Filled.PlayCircle, contentDescription = "视频") },
                    label = { Text("视频") },
                )
                NavigationBarItem(
                    selected = tab == 1,
                    onClick = { tab = 1 },
                    icon = { Icon(Icons.Filled.Collections, contentDescription = "作品") },
                    label = { Text("作品") },
                )
                NavigationBarItem(
                    selected = tab == 2,
                    onClick = { tab = 2 },
                    icon = { Icon(Icons.Filled.Favorite, contentDescription = "收藏夹") },
                    label = { Text("收藏夹") },
                )
            }
        },
    ) { padding ->
        Box(Modifier.padding(padding)) {
            when (tab) {
                0 -> VideosScreen(
                    onVideoClick = onOpenDetail,
                    onSessionExpired = onSessionExpired,
                )
                1 -> WorksScreen(
                    onOpenDetail = onOpenDetail,
                    onOpenJavList = onOpenJavList,
                    onSessionExpired = onSessionExpired,
                )
                else -> FavoritesScreen(
                    onGroupClick = onFavGroupClick,
                    onSessionExpired = onSessionExpired,
                )
            }
        }
    }
}
