package com.javboss.phone.ui.player

import android.app.Activity
import android.content.pm.ActivityInfo
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.PlayerView

/**
 * 播放页：优先用服务端 preferred 源（通常 direct 直流），
 * 播放报错时自动 fallback 到下一个源（HLS 转码兜底）。
 * 视频流请求带登录 Cookie（DefaultHttpDataSource 请求头）。
 * 进入时强制横屏 + 沉浸模式，退出恢复竖屏；控制条用 Media3 自带的（单击显隐）。
 */
@Composable
fun PlayerScreen(
    videoId: Long,
    onBack: () -> Unit,
    viewModel: PlayerViewModel = viewModel(),
) {
    val context = LocalContext.current
    val activity = context as? Activity
    val state = viewModel.uiState

    LaunchedEffect(videoId) { viewModel.load(videoId) }

    // 横屏 + 隐藏系统栏，离开时恢复
    DisposableEffect(Unit) {
        val window = activity?.window
        val controller = window?.let { WindowInsetsControllerCompat(it, it.decorView) }
        activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        if (window != null && controller != null) {
            WindowCompat.setDecorFitsSystemWindows(window, false)
            controller.hide(WindowInsetsCompat.Type.systemBars())
            controller.systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }
        onDispose {
            if (window != null && controller != null) {
                controller.show(WindowInsetsCompat.Type.systemBars())
                WindowCompat.setDecorFitsSystemWindows(window, true)
            }
            activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        }
    }

    // 当前尝试的播放源下标
    var sourceIndex by remember { mutableIntStateOf(0) }

    val player = remember {
        val httpFactory = DefaultHttpDataSource.Factory()
            .setDefaultRequestProperties(
                mapOf("Cookie" to viewModel.cookieHeader)
            )
            .setUserAgent("JavBossPhone/0.1")
        ExoPlayer.Builder(context)
            .setMediaSourceFactory(DefaultMediaSourceFactory(context).setDataSourceFactory(httpFactory))
            .build()
    }

    DisposableEffect(Unit) {
        onDispose { player.release() }
    }

    BackHandler {
        player.stop()
        onBack()
    }

    // 播放源就绪后设置给播放器
    LaunchedEffect(state.urls, sourceIndex) {
        if (state.urls.isNotEmpty() && sourceIndex < state.urls.size) {
            player.setMediaItem(MediaItem.fromUri(state.urls[sourceIndex]))
            player.prepare()
            player.playWhenReady = true
        }
    }

    // 出错时 fallback 到下一个源
    LaunchedEffect(state.urls) {
        player.addListener(object : Player.Listener {
            override fun onPlayerError(error: PlaybackException) {
                if (sourceIndex + 1 < state.urls.size) {
                    sourceIndex += 1
                }
            }
        })
    }

    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black),
        contentAlignment = Alignment.Center,
    ) {
        when {
            state.loading -> Text("加载播放源…", style = MaterialTheme.typography.bodyLarge)
            state.error != null -> Text(
                "无法播放：${state.error}",
                color = MaterialTheme.colorScheme.error,
            )
            else -> AndroidView(
                factory = { ctx ->
                    PlayerView(ctx).apply {
                        useController = true
                        this.player = player
                    }
                },
                modifier = Modifier.fillMaxSize(),
            )
        }
    }
}
