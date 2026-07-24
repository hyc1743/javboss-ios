package com.javboss.phone.ui.main

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.Collections
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.javboss.phone.ui.favorites.FavoritesScreen
import com.javboss.phone.ui.videos.VideosScreen
import com.javboss.phone.ui.works.WorksScreen

/**
 * 主页：底部三 tab（视频 / 作品 / 收藏夹）+ 末尾的登出入口。
 * tab 切换只是本地状态，ViewModel 挂在 main 路由的 NavBackStackEntry 上，
 * 切 tab 不丢滚动位置和已加载数据。
 */
@Composable
fun MainScreen(
    onOpenDetail: (videoId: Long, code: String?) -> Unit,
    onOpenJavList: (title: String, idolIds: String, tagIds: String, studioId: Long, seriesId: Long) -> Unit,
    onFavGroupClick: (groupId: Long, name: String) -> Unit,
    onSessionExpired: () -> Unit,
    onLogout: () -> Unit,
) {
    var tab by rememberSaveable { mutableIntStateOf(0) }
    var showLogoutConfirm by remember { mutableStateOf(false) }

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
                // 登出不是 tab，点击只弹确认框，不改变选中态
                NavigationBarItem(
                    selected = false,
                    onClick = { showLogoutConfirm = true },
                    icon = { Icon(Icons.AutoMirrored.Filled.Logout, contentDescription = "退出") },
                    label = { Text("退出") },
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

    if (showLogoutConfirm) {
        AlertDialog(
            onDismissRequest = { showLogoutConfirm = false },
            title = { Text("退出登录") },
            text = { Text("将清除本机的登录状态，需要重新输入服务器地址和密码。") },
            confirmButton = {
                TextButton(onClick = {
                    showLogoutConfirm = false
                    onLogout()
                }) { Text("退出") }
            },
            dismissButton = {
                TextButton(onClick = { showLogoutConfirm = false }) { Text("取消") }
            },
        )
    }
}
