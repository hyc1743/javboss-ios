@file:androidx.annotation.OptIn(markerClass = [androidx.media3.common.util.UnstableApi::class])

package com.javboss.phone.ui.player

import android.app.Activity
import android.content.pm.ActivityInfo
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
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
import androidx.compose.runtime.key
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
import com.javboss.phone.data.EngineMode
import com.javboss.phone.ui.components.formatDuration
import kotlinx.coroutines.delay

/**
 * 统一播放页：一套 UI + 一套自绘控制条，引擎（ExoPlayer / libVLC）只负责解码渲染。
 * - 引擎由设置页偏好决定；AUTO 模式下 ExoPlayer 全部源失败自动切 libVLC 续播
 * - ExoPlayer 直接带 Cookie 头请求；libVLC 经本地代理附加 Cookie
 * - 控制条点按显隐：播放/暂停 + 进度拖动 + 时间 + 当前引擎标识 + 缓冲指示
 * - 进入时强制横屏 + 沉浸模式，退出恢复竖屏
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
        val previousOrientation = activity?.requestedOrientation
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
            activity?.requestedOrientation = previousOrientation ?: ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
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
            else -> UnifiedPlayerStage(
                urls = state.urls,
                activeEngine = state.activeEngine,
                autoFallback = state.engineMode == EngineMode.AUTO,
                startPositionMs = state.fallbackPositionMs,
                cookieHeader = viewModel.cookieHeader,
                proxyUrl = viewModel::proxyUrl,
                onSwitchToVlc = { positionMs -> viewModel.switchToVlc(positionMs) },
                onAllSourcesFailed = { viewModel.failPlayback("所有播放源均播放失败") },
                onBack = onBack,
            )
        }
    }
}

@Composable
private fun UnifiedPlayerStage(
    urls: List<String>,
    activeEngine: EngineMode,
    autoFallback: Boolean,
    startPositionMs: Long,
    cookieHeader: String,
    proxyUrl: (String) -> String,
    onSwitchToVlc: (positionMs: Long) -> Unit,
    onAllSourcesFailed: () -> Unit,
    onBack: () -> Unit,
) {
    val context = LocalContext.current

    // 引擎实例随 activeEngine 重建（AUTO 兜底切换时）
    val engine = remember(activeEngine) {
        when (activeEngine) {
            EngineMode.VLC -> VlcPlayerEngine(context)
            else -> ExoPlayerEngine(context, cookieHeader)
        }
    }
    // 渲染表面必须在 play() 之前创建并挂到引擎上（remember 在组合期执行，
    // 早于 LaunchedEffect）：libVLC 若无附着视图直接起播会判定无 vout，
    // 整场只剩音频黑屏（video output creation failed）
    // 起播再等 SurfaceView 真正创建（surfaceCreated），否则解码器先于表面
    // 创建 vout 失败，同样整场黑屏
    // 渲染表面就绪信号：VLCVideoLayout 在 AndroidView factory 里创建并 attach 后，
    // 递归找到其内部 SurfaceView，等 surfaceCreated 才真正起播，
    // 否则解码器先于表面创建 vout 会整场黑屏（video output creation failed）
    var surfaceReady by remember(activeEngine) { mutableStateOf(activeEngine != EngineMode.VLC) }
    // 切引擎后从头一个源重试（源顺序 direct → HLS 与引擎无关）
    var sourceIndex by remember(activeEngine) { mutableIntStateOf(0) }
    // 已确认的最近进度：换源/换引擎时从此处续播
    var resumePositionMs by remember(activeEngine) { mutableLongStateOf(startPositionMs) }

    var controlsVisible by remember { mutableStateOf(false) }
    var isPlaying by remember { mutableStateOf(false) }
    var isBuffering by remember { mutableStateOf(true) }
    var positionMs by remember { mutableLongStateOf(0L) }
    var durationMs by remember { mutableLongStateOf(0L) }

    DisposableEffect(activeEngine) {
        engine.onError = {
            resumePositionMs = engine.positionMs
            if (sourceIndex + 1 < urls.size) {
                sourceIndex += 1
            } else if (autoFallback && activeEngine != EngineMode.VLC) {
                onSwitchToVlc(engine.positionMs)
            } else {
                onAllSourcesFailed()
            }
        }
        onDispose { engine.release() }
    }

    BackHandler {
        engine.stop()
        onBack()
    }

    // 播放当前源（libVLC 需经本地代理带 Cookie；且等渲染表面就绪后起播）
    LaunchedEffect(urls, sourceIndex, activeEngine, surfaceReady) {
        if (surfaceReady && urls.isNotEmpty() && sourceIndex < urls.size) {
            val raw = urls[sourceIndex]
            engine.play(if (activeEngine == EngineMode.VLC) proxyUrl(raw) else raw, resumePositionMs)
        }
    }

    // 轮询播放状态驱动控制条
    LaunchedEffect(activeEngine) {
        while (true) {
            isPlaying = engine.isPlaying
            isBuffering = engine.isBuffering
            durationMs = engine.durationMs
            positionMs = engine.positionMs
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
        // key(activeEngine) 强制 AndroidView 随引擎整体重建：
        // AndroidView 的 factory 在同一组合位置只执行一次，不加 key 时
        // 切换到 libVLC 后工厂不重跑，VLCVideoLayout 从未被创建和挂载
        key(activeEngine) {
            AndroidView(
                factory = { ctx ->
                    engine.createView(ctx).also { view ->
                        if (activeEngine == EngineMode.VLC) {
                            findSurfaceView(view)?.holder?.addCallback(object : SurfaceHolder.Callback {
                                override fun surfaceCreated(holder: SurfaceHolder) {
                                    surfaceReady = true
                                }
                                override fun surfaceChanged(h: SurfaceHolder, f: Int, w: Int, ht: Int) {}
                                override fun surfaceDestroyed(holder: SurfaceHolder) {}
                            })
                        }
                    }
                },
                modifier = Modifier.fillMaxSize(),
            )
        }

        if (isBuffering && !controlsVisible) {
            Text(
                "加载中…",
                color = Color.White,
                style = MaterialTheme.typography.bodyLarge,
                modifier = Modifier.align(Alignment.Center),
            )
        }

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
                    IconButton(onClick = { engine.setPlaying(!isPlaying) }) {
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
                            if (durationMs > 0) engine.seekTo((fraction * durationMs).toLong())
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
                    Text(
                        if (activeEngine == EngineMode.VLC) "libVLC" else "ExoPlayer",
                        color = Color.White.copy(alpha = 0.5f),
                        style = MaterialTheme.typography.labelSmall,
                        modifier = Modifier.padding(start = 8.dp),
                    )
                }
            }
        }
    }
}

/** 递归找视图树里第一个 SurfaceView（VLCVideoLayout 的表面嵌套在多层 FrameLayout 里） */
private fun findSurfaceView(view: View): SurfaceView? = when (view) {
    is SurfaceView -> view
    is ViewGroup -> (0 until view.childCount).asSequence()
        .mapNotNull { findSurfaceView(view.getChildAt(it)) }
        .firstOrNull()
    else -> null
}
