package com.javboss.phone.ui.player

import android.app.Activity
import android.content.pm.ActivityInfo
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.unit.dp
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
import com.javboss.phone.ui.components.formatDuration
import kotlinx.coroutines.delay
import org.videolan.libvlc.util.VLCVideoLayout

/**
 * 播放页：双引擎。
 * - EXO：优先 direct 直流（硬解），出错自动 fallback 到下一个源（HLS）
 * - VLC：EXO 全部源失败后自动切换（libVLC 自带 ffmpeg，解 wmv 等冷门格式），
 *   经本地代理附加会话 Cookie，从 EXO 失败进度续播
 * 视频流请求带登录 Cookie（EXO 走 DefaultHttpDataSource 请求头，VLC 走本地代理）。
 * 进入时强制横屏 + 沉浸模式，退出恢复竖屏。
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
            state.engine == PlayerEngine.EXO -> ExoStage(
                urls = state.urls,
                cookieHeader = viewModel.cookieHeader,
                onAllSourcesFailed = { positionMs -> viewModel.switchToVlc(positionMs) },
                onBack = onBack,
            )
            else -> VlcStage(
                urls = state.urls,
                startPositionMs = state.vlcStartPositionMs,
                proxyUrl = viewModel::proxyUrl,
                onAllSourcesFailed = { viewModel.failPlayback("所有播放源均播放失败") },
                onBack = onBack,
            )
        }
    }
}

/** ExoPlayer 阶段：自带控制条（单击显隐） */
@Composable
private fun ExoStage(
    urls: List<String>,
    cookieHeader: String,
    onAllSourcesFailed: (positionMs: Long) -> Unit,
    onBack: () -> Unit,
) {
    val context = LocalContext.current
    var sourceIndex by remember { mutableIntStateOf(0) }

    val player = remember {
        val httpFactory = DefaultHttpDataSource.Factory()
            .setDefaultRequestProperties(mapOf("Cookie" to cookieHeader))
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

    LaunchedEffect(urls, sourceIndex) {
        if (urls.isNotEmpty() && sourceIndex < urls.size) {
            player.setMediaItem(MediaItem.fromUri(urls[sourceIndex]))
            player.prepare()
            player.playWhenReady = true
        }
    }

    // 出错时 fallback 到下一个源；全部失败则切换 VLC 引擎
    LaunchedEffect(urls) {
        player.addListener(object : Player.Listener {
            override fun onPlayerError(error: PlaybackException) {
                if (sourceIndex + 1 < urls.size) {
                    sourceIndex += 1
                } else {
                    onAllSourcesFailed(player.currentPosition)
                }
            }
        })
    }

    AndroidView(
        factory = { ctx ->
            PlayerView(ctx).apply {
                useController = true
                this.player = player
            }
        },
        modifier = Modifier.fillMaxSize(),
    )
}

/** libVLC 阶段：VLCVideoLayout + 自绘简易控制条（点按显隐） */
@Composable
private fun VlcStage(
    urls: List<String>,
    startPositionMs: Long,
    proxyUrl: (String) -> String,
    onAllSourcesFailed: () -> Unit,
    onBack: () -> Unit,
) {
    val context = LocalContext.current
    var sourceIndex by remember { mutableIntStateOf(0) }
    // 已确认的最近进度：源间切换时从此处续播
    var resumePositionMs by remember { mutableLongStateOf(startPositionMs) }

    val controller = remember { VlcPlayerController(context) }

    var controlsVisible by remember { mutableStateOf(false) }
    var isPlaying by remember { mutableStateOf(false) }
    var positionMs by remember { mutableLongStateOf(0L) }
    var durationMs by remember { mutableLongStateOf(0L) }

    DisposableEffect(Unit) {
        controller.onError = {
            resumePositionMs = positionMs
            if (sourceIndex + 1 < urls.size) {
                sourceIndex += 1
            } else {
                onAllSourcesFailed()
            }
        }
        onDispose { controller.release() }
    }

    BackHandler {
        controller.mediaPlayer.stop()
        onBack()
    }

    // 播放当前源（经本地代理带 Cookie）
    LaunchedEffect(urls, sourceIndex) {
        if (urls.isNotEmpty() && sourceIndex < urls.size) {
            controller.play(proxyUrl(urls[sourceIndex]), resumePositionMs)
        }
    }

    // 轮询播放状态驱动控制条（VLC 事件不带进度，轮询最直白）
    LaunchedEffect(Unit) {
        while (true) {
            isPlaying = controller.mediaPlayer.isPlaying
            durationMs = controller.mediaPlayer.length.coerceAtLeast(0)
            positionMs = controller.mediaPlayer.time.coerceAtLeast(0)
            if (isPlaying && positionMs > 0) resumePositionMs = positionMs
            delay(500)
        }
    }

    Box(
        Modifier
            .fillMaxSize()
            .pointerInput(Unit) {
                detectTapGestures { controlsVisible = !controlsVisible }
            },
    ) {
        AndroidView(
            factory = { ctx -> VLCVideoLayout(ctx).also(controller::attach) },
            modifier = Modifier.fillMaxSize(),
        )

        if (controlsVisible) {
            Surface(
                color = Color.Black.copy(alpha = 0.6f),
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth(),
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.padding(horizontal = 8.dp),
                ) {
                    IconButton(onClick = {
                        if (controller.mediaPlayer.isPlaying) controller.mediaPlayer.pause()
                        else controller.mediaPlayer.play()
                    }) {
                        Icon(
                            if (isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                            contentDescription = if (isPlaying) "暂停" else "播放",
                            tint = Color.White,
                        )
                    }
                    Text(
                        formatDuration(positionMs / 1000).ifEmpty { "0:00" },
                        color = Color.White,
                        style = MaterialTheme.typography.labelMedium,
                    )
                    Slider(
                        value = if (durationMs > 0) positionMs.toFloat() / durationMs else 0f,
                        onValueChange = { fraction ->
                            if (durationMs > 0) {
                                controller.mediaPlayer.time = (fraction * durationMs).toLong()
                            }
                        },
                        modifier = Modifier
                            .weight(1f)
                            .padding(horizontal = 8.dp),
                    )
                    Text(
                        formatDuration(durationMs / 1000).ifEmpty { "--:--" },
                        color = Color.White,
                        style = MaterialTheme.typography.labelMedium,
                    )
                }
            }
        }
    }
}
