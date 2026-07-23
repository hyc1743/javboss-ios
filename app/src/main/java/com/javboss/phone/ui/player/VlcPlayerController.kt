package com.javboss.phone.ui.player

import android.content.Context
import android.os.Handler
import android.os.Looper
import org.videolan.libvlc.LibVLC
import org.videolan.libvlc.Media
import org.videolan.libvlc.MediaPlayer
import org.videolan.libvlc.util.VLCVideoLayout

/**
 * libVLC 封装：ExoPlayer 全部源失败后的兜底引擎。
 * 自带完整 ffmpeg 解封装+解码（wmv/rmvb/flv/avi 等冷门格式软解；
 * h264/h265/vp9/av1 默认走 MediaCodec 硬解，无需配置）。
 *
 * 事件从 native 线程回调，统一 post 到主线程再通知 UI。
 */
class VlcPlayerController(context: Context) {

    private val mainHandler = Handler(Looper.getMainLooper())
    private val libVlc = LibVLC(context, arrayListOf("--no-stats"))
    val mediaPlayer = MediaPlayer(libVlc)

    /** 播放出错回调（主线程）。赋值后再 play() */
    var onError: () -> Unit = {}

    private var pendingSeekMs = -1L

    init {
        mediaPlayer.setEventListener { event ->
            when (event.type) {
                MediaPlayer.Event.Playing -> if (pendingSeekMs > 0) {
                    mediaPlayer.time = pendingSeekMs
                    pendingSeekMs = -1L
                }
                MediaPlayer.Event.EncounteredError ->
                    mainHandler.post { onError() }
                else -> {}
            }
        }
    }

    fun attach(layout: VLCVideoLayout) {
        mediaPlayer.attachViews(layout, null, false, false)
    }

    fun play(url: String, startPositionMs: Long = 0) {
        pendingSeekMs = startPositionMs
        val media = Media(libVlc, android.net.Uri.parse(url))
        mediaPlayer.media = media
        media.release()
        mediaPlayer.play()
    }

    fun release() {
        runCatching {
            mediaPlayer.stop()
            mediaPlayer.detachViews()
            mediaPlayer.release()
            libVlc.release()
        }
    }
}
