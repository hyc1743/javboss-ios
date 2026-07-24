@file:androidx.annotation.OptIn(markerClass = [androidx.media3.common.util.UnstableApi::class])

package com.javboss.phone.ui.player

import android.app.Activity
import android.content.Context
import android.content.pm.ActivityInfo
import android.media.AudioManager
import android.os.Build
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import android.view.Window
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.LockOpen
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Subtitles
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
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
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.viewmodel.compose.viewModel
import com.javboss.phone.data.EngineMode
import com.javboss.phone.ui.components.formatDuration
import kotlinx.coroutines.delay
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * 手机播放页：保留现有双引擎与鉴权代理，只使用自绘触控层。
 * 左上始终可返回，左中打开设置，右中锁定；锁定时只保留返回与解锁。
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
        Modifier.fillMaxSize().background(Color.Black),
        contentAlignment = Alignment.Center,
    ) {
        when {
            state.loading -> Text("加载播放源…", color = Color.White)
            state.error != null -> Text("无法播放：${state.error}", color = MaterialTheme.colorScheme.error)
            else -> UnifiedPlayerStage(
                urls = state.urls,
                engineMode = state.engineMode,
                activeEngine = state.activeEngine,
                autoFallback = state.engineMode == EngineMode.AUTO,
                startPositionMs = state.fallbackPositionMs,
                cookieHeader = viewModel.cookieHeader,
                proxyUrl = viewModel::proxyUrl,
                onSwitchToVlc = viewModel::switchToVlc,
                onEngineModeChange = viewModel::selectEngineMode,
                onAllSourcesFailed = { viewModel.failPlayback("所有播放源均播放失败") },
                onBack = onBack,
            )
        }
    }
}

@Composable
private fun UnifiedPlayerStage(
    urls: List<String>,
    engineMode: EngineMode,
    activeEngine: EngineMode,
    autoFallback: Boolean,
    startPositionMs: Long,
    cookieHeader: String,
    proxyUrl: (String) -> String,
    onSwitchToVlc: (Long) -> Unit,
    onEngineModeChange: (EngineMode, Long) -> Unit,
    onAllSourcesFailed: () -> Unit,
    onBack: () -> Unit,
) {
    val context = LocalContext.current
    val activity = context as? Activity
    val window = activity?.window
    val density = LocalDensity.current
    val cutoutStartPadding = with(density) {
        val inset = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window?.decorView?.rootWindowInsets?.displayCutout?.safeInsetLeft ?: 0
        } else 0
        inset.toDp()
    }
    val audioManager = remember(context) {
        context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    }
    val engine = remember(activeEngine) {
        when (activeEngine) {
            EngineMode.VLC -> VlcPlayerEngine(context)
            else -> ExoPlayerEngine(context, cookieHeader)
        }
    }
    var surfaceReady by remember(activeEngine) { mutableStateOf(activeEngine != EngineMode.VLC) }
    var sourceIndex by remember(activeEngine) { mutableIntStateOf(0) }
    var resumePositionMs by remember(activeEngine) { mutableLongStateOf(startPositionMs) }
    var controlsVisible by remember { mutableStateOf(false) }
    var settingsVisible by remember { mutableStateOf(false) }
    var locked by remember { mutableStateOf(false) }
    var isPlaying by remember { mutableStateOf(false) }
    var isBuffering by remember { mutableStateOf(true) }
    var positionMs by remember { mutableLongStateOf(0L) }
    var durationMs by remember { mutableLongStateOf(0L) }
    var subtitlesAvailable by remember { mutableStateOf(false) }
    var subtitlesEnabled by remember { mutableStateOf(false) }
    var gestureHint by remember { mutableStateOf<String?>(null) }
    var gestureSeekTarget by remember { mutableLongStateOf(0L) }
    var brightness by remember { mutableStateOf(window?.screenBrightness().orDefaultBrightness()) }
    var volume by remember { mutableIntStateOf(audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)) }
    // 手势协程不能随轮询进度、亮度或音量更新而重启；通过这些状态引用读取最新值。
    val currentEngine by rememberUpdatedState(engine)
    val currentPositionMs by rememberUpdatedState(positionMs)
    val currentDurationMs by rememberUpdatedState(durationMs)
    val currentBrightness by rememberUpdatedState(brightness)

    DisposableEffect(window) {
        val previousBrightness = window?.screenBrightness()
        onDispose {
            if (window != null && previousBrightness != null) window.setBrightness(previousBrightness)
        }
    }

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

    LaunchedEffect(urls, sourceIndex, activeEngine, surfaceReady) {
        if (surfaceReady && sourceIndex < urls.size) {
            val raw = urls[sourceIndex]
            engine.play(if (activeEngine == EngineMode.VLC) proxyUrl(raw) else raw, resumePositionMs)
        }
    }

    LaunchedEffect(activeEngine) {
        while (true) {
            isPlaying = engine.isPlaying
            isBuffering = engine.isBuffering
            positionMs = engine.positionMs
            durationMs = engine.durationMs
            subtitlesAvailable = engine.subtitlesAvailable
            subtitlesEnabled = engine.subtitlesEnabled
            if (isPlaying && positionMs > 0) resumePositionMs = positionMs
            delay(500)
        }
    }

    LaunchedEffect(gestureHint) {
        if (gestureHint != null) {
            delay(900)
            gestureHint = null
        }
    }

    val gestureModifier = if (locked) Modifier else Modifier
        .pointerInput(Unit) {
            var mode: GestureMode? = null
            var totalX = 0f
            var totalY = 0f
            var seekStartPositionMs = 0L
            var brightnessStart = currentBrightness
            var volumeStart = volume
            detectDragGestures(
                onDragStart = {
                    mode = null
                    totalX = 0f
                    totalY = 0f
                    seekStartPositionMs = currentPositionMs
                    brightnessStart = currentBrightness
                    volumeStart = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
                },
                onDrag = { change, amount ->
                    totalX += amount.x
                    totalY += amount.y
                    if (mode == null && maxOf(abs(totalX), abs(totalY)) > 18f) {
                        mode = if (abs(totalX) > abs(totalY)) GestureMode.SEEK
                        else if (change.position.x < size.width / 2f) GestureMode.BRIGHTNESS
                        else GestureMode.VOLUME
                    }
                    when (mode) {
                        GestureMode.SEEK -> if (currentDurationMs > 0) {
                            gestureSeekTarget = (seekStartPositionMs + currentDurationMs * totalX / size.width)
                                .toLong().coerceIn(0, currentDurationMs)
                            gestureHint = "进度  ${formatDuration(gestureSeekTarget / 1000)}"
                        }
                        GestureMode.BRIGHTNESS -> {
                            brightness = (brightnessStart - totalY / size.height).coerceIn(0.05f, 1f)
                            window?.setBrightness(brightness)
                            gestureHint = "亮度 ${(brightness * 100).roundToInt()}%"
                        }
                        GestureMode.VOLUME -> {
                            val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                            volume = (volumeStart - totalY / size.height * maxVolume)
                                .roundToInt().coerceIn(0, maxVolume)
                            audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, volume, 0)
                            gestureHint = "音量 ${(volume * 100f / maxVolume).roundToInt()}%"
                        }
                        null -> Unit
                    }
                    if (mode != null) change.consume()
                },
                onDragEnd = {
                    if (mode == GestureMode.SEEK && currentDurationMs > 0) currentEngine.seekTo(gestureSeekTarget)
                },
            )
        }
        .pointerInput(Unit) {
            detectTapGestures { controlsVisible = !controlsVisible }
        }

    Box(Modifier.fillMaxSize().then(gestureModifier)) {
        key(activeEngine) {
            AndroidView(
                factory = { ctx ->
                    engine.createView(ctx).also { view ->
                        if (activeEngine == EngineMode.VLC) {
                            findSurfaceView(view)?.holder?.addCallback(object : SurfaceHolder.Callback {
                                override fun surfaceCreated(holder: SurfaceHolder) { surfaceReady = true }
                                override fun surfaceChanged(holder: SurfaceHolder, f: Int, w: Int, h: Int) = Unit
                                override fun surfaceDestroyed(holder: SurfaceHolder) = Unit
                            })
                        }
                    }
                },
                modifier = Modifier.fillMaxSize(),
            )
        }

        if (isBuffering && !controlsVisible) {
            Text("加载中…", color = Color.White, modifier = Modifier.align(Alignment.Center))
        }
        gestureHint?.let { hint ->
            Surface(
                color = Color.Black.copy(alpha = 0.72f),
                shape = MaterialTheme.shapes.medium,
                modifier = Modifier.align(Alignment.Center),
            ) {
                Text(hint, color = Color.White, modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp))
            }
        }

        IconButton(
            onClick = { engine.stop(); onBack() },
            modifier = Modifier
                .align(Alignment.TopStart)
                .padding(start = cutoutStartPadding + 12.dp, top = 12.dp, end = 12.dp, bottom = 12.dp),
        ) {
            Icon(Icons.AutoMirrored.Filled.ArrowBack, "返回", tint = Color.White)
        }

        if (!locked) {
            IconButton(
                onClick = { settingsVisible = !settingsVisible },
                modifier = Modifier
                    .align(Alignment.CenterStart)
                    .padding(start = cutoutStartPadding + 12.dp, top = 12.dp, end = 12.dp, bottom = 12.dp),
            ) {
                Icon(Icons.Filled.Settings, "播放设置", tint = Color.White)
            }
        }
        IconButton(
            onClick = {
                locked = !locked
                if (locked) {
                    controlsVisible = false
                    settingsVisible = false
                    gestureHint = "已锁定"
                } else {
                    gestureHint = "已解锁"
                }
            },
            modifier = Modifier.align(Alignment.CenterEnd).padding(12.dp),
        ) {
            Icon(
                if (locked) Icons.Filled.Lock else Icons.Filled.LockOpen,
                if (locked) "锁定" else "解锁",
                tint = Color.White,
            )
        }

        // 设置面板外的点击直接关闭面板；面板作为后绘制的子项优先消费自己的交互。
        if (settingsVisible && !locked) {
            Box(
                Modifier
                    .fillMaxSize()
                    .pointerInput(Unit) { detectTapGestures { settingsVisible = false } },
            )
        }

        AnimatedVisibility(
            visible = settingsVisible && !locked,
            enter = slideInHorizontally { -it } + fadeIn(),
            exit = slideOutHorizontally { -it } + fadeOut(),
            modifier = Modifier.align(Alignment.CenterStart).padding(start = 56.dp),
        ) {
            PlayerSettingsPanel(
                engineMode = engineMode,
                activeEngine = activeEngine,
                decoderStatus = engine.decoderStatus,
                subtitlesAvailable = subtitlesAvailable,
                subtitlesEnabled = subtitlesEnabled,
                onEngineModeChange = { mode ->
                    settingsVisible = false
                    onEngineModeChange(mode, positionMs)
                },
                onSubtitleChange = engine::setSubtitlesEnabled,
            )
        }

        if (controlsVisible && !locked) {
            PlaybackControls(
                isPlaying = isPlaying,
                positionMs = positionMs,
                durationMs = durationMs,
                activeEngine = activeEngine,
                onPlayingChange = engine::setPlaying,
                onSeek = engine::seekTo,
                modifier = Modifier.align(Alignment.BottomCenter),
            )
        }
    }
}

@Composable
private fun PlayerSettingsPanel(
    engineMode: EngineMode,
    activeEngine: EngineMode,
    decoderStatus: String,
    subtitlesAvailable: Boolean,
    subtitlesEnabled: Boolean,
    onEngineModeChange: (EngineMode) -> Unit,
    onSubtitleChange: (Boolean) -> Unit,
) {
    Surface(color = Color.Black.copy(alpha = 0.78f), shape = MaterialTheme.shapes.large, modifier = Modifier.width(270.dp)) {
        Column(Modifier.padding(16.dp)) {
            Text("播放设置", color = Color.White, style = MaterialTheme.typography.titleMedium)
            EngineMode.entries.forEach { mode ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    RadioButton(selected = engineMode == mode, onClick = { onEngineModeChange(mode) })
                    Text(mode.label, color = Color.White, modifier = Modifier.padding(start = 6.dp))
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 8.dp)) {
                Icon(Icons.Filled.Subtitles, null, tint = Color.White)
                Text("显示字幕", color = Color.White, modifier = Modifier.weight(1f).padding(start = 8.dp))
                Switch(
                    checked = subtitlesEnabled,
                    onCheckedChange = onSubtitleChange,
                    enabled = subtitlesAvailable,
                )
            }
            if (!subtitlesAvailable) {
                Text("当前视频没有可用字幕轨", color = Color.White.copy(alpha = 0.6f), style = MaterialTheme.typography.labelSmall)
            }
            Text(
                "当前：${if (activeEngine == EngineMode.VLC) "libVLC" else "ExoPlayer"}\n解码：$decoderStatus",
                color = Color.White.copy(alpha = 0.8f),
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.padding(top = 12.dp),
            )
        }
    }
}

@Composable
private fun PlaybackControls(
    isPlaying: Boolean,
    positionMs: Long,
    durationMs: Long,
    activeEngine: EngineMode,
    onPlayingChange: (Boolean) -> Unit,
    onSeek: (Long) -> Unit,
    modifier: Modifier = Modifier,
) {
    Surface(color = Color.Black.copy(alpha = 0.65f), modifier = modifier.fillMaxWidth()) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(horizontal = 8.dp)) {
            IconButton(onClick = { onPlayingChange(!isPlaying) }) {
                Icon(if (isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow, if (isPlaying) "暂停" else "播放", tint = Color.White)
            }
            Text(formatDuration(positionMs / 1000).ifEmpty { "0:00" }, color = Color.White, style = MaterialTheme.typography.labelMedium)
            Slider(
                value = if (durationMs > 0) positionMs.toFloat() / durationMs else 0f,
                onValueChange = { if (durationMs > 0) onSeek((it * durationMs).toLong()) },
                modifier = Modifier.weight(1f).padding(horizontal = 8.dp),
            )
            Text(formatDuration(durationMs / 1000).ifEmpty { "--:--" }, color = Color.White, style = MaterialTheme.typography.labelMedium)
            Text(if (activeEngine == EngineMode.VLC) "libVLC" else "ExoPlayer", color = Color.White.copy(alpha = 0.6f), style = MaterialTheme.typography.labelSmall, modifier = Modifier.padding(start = 8.dp))
        }
    }
}

private enum class GestureMode { SEEK, BRIGHTNESS, VOLUME }

private fun Window.screenBrightness(): Float = attributes.screenBrightness

private fun Window.setBrightness(value: Float) {
    attributes = attributes.apply { screenBrightness = value }
}

private fun Float?.orDefaultBrightness(): Float = this?.takeIf { it >= 0f } ?: 0.5f

private fun findSurfaceView(view: View): SurfaceView? = when (view) {
    is SurfaceView -> view
    is ViewGroup -> (0 until view.childCount).asSequence().mapNotNull { findSurfaceView(view.getChildAt(it)) }.firstOrNull()
    else -> null
}
