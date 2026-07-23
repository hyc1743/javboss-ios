package com.javboss.phone.data.localproxy

import fi.iki.elonen.NanoHTTPD
import okhttp3.OkHttpClient
import okhttp3.Request
import java.net.URLEncoder

/**
 * 本地鉴权代理：libVLC 的 HTTP 模块无法注入自定义 Cookie 头，
 * 所以让 libVLC 播放 http://127.0.0.1:{port}/... 地址，
 * 由本代理用共享 OkHttpClient（带会话 CookieJar）转发到 JavBoss 服务端。
 *
 * 两种地址形式：
 * - `/?url={urlencoded 上游绝对地址}`：proxyUrl() 生成的显式形式
 * - 任意路径（如 /videos/2/stream.m3u8/0.ts）：HLS 分片相对地址被 VLC
 *   按代理 base 解析后自然回落到代理，按服务端相对路径处理
 *
 * 流式透传（不缓冲整个 body），Range/206 头原样转发，大文件拖动依赖于此。
 */
class AuthProxy(
    private val okHttpClient: OkHttpClient,
    private val absoluteUrl: (String) -> String,
) {

    @Volatile
    private var server: ProxyServer? = null

    val baseUrl: String
        get() {
            start()
            return "http://127.0.0.1:${server!!.listeningPort}"
        }

    @Synchronized
    fun start() {
        if (server == null) {
            server = ProxyServer().apply { start(NanoHTTPD.SOCKET_READ_TIMEOUT, true) }
        }
    }

    fun proxyUrl(upstreamAbsoluteUrl: String): String =
        "$baseUrl/?url=" + URLEncoder.encode(upstreamAbsoluteUrl, "UTF-8")

    private inner class ProxyServer : NanoHTTPD("127.0.0.1", 0) {

        override fun serve(session: IHTTPSession): Response {
            val explicit = session.parms["url"]
            val upstream = explicit ?: run {
                val query = session.queryParameterString
                absoluteUrl(session.uri + (query?.let { "?$it" } ?: ""))
            }

            val request = Request.Builder()
                .url(upstream)
                .header("Accept-Encoding", "identity")
                .header("User-Agent", "JavBossPhone/0.1")
                .apply {
                    session.headers["range"]?.let { header("Range", it) }
                }
                .build()

            val upstreamResp = try {
                okHttpClient.newCall(request).execute()
            } catch (e: Exception) {
                return newFixedLengthResponse(
                    Response.Status.INTERNAL_ERROR, "text/plain",
                    "proxy upstream error: ${e.message}",
                )
            }

            // 不能在这里关闭上游 Response：流由 NanoHTTPD 的发送线程异步消费。
            // NanoHTTPD 发送完毕/连接断开时会 close 返回的 InputStream，
            // 即 OkHttp body 的 byteStream，关闭它会连带释放整个上游 Response。
            val body = upstreamResp.body ?: return newFixedLengthResponse(
                Response.Status.INTERNAL_ERROR, "text/plain", "empty upstream body",
            )
            val stream = body.byteStream()
            val status = Response.Status.lookup(upstreamResp.code) ?: Response.Status.INTERNAL_ERROR
            val mime = upstreamResp.header("Content-Type") ?: "application/octet-stream"
            val length = body.contentLength()
            val out = if (length >= 0) {
                newFixedLengthResponse(status, mime, stream, length)
            } else {
                newChunkedResponse(status, mime, stream)
            }
            upstreamResp.header("Content-Range")?.let { out.addHeader("Content-Range", it) }
            upstreamResp.header("Accept-Ranges")?.let { out.addHeader("Accept-Ranges", it) }
            return out
        }
    }
}
