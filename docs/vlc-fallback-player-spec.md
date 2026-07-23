# SPEC：全格式播放（ExoPlayer 直连 + libVLC 兜底）

状态：已确认 | 适用范围：javboss-phone（先行），验证通过后同步 javboss-tv

## 背景与问题

- 客户端播放源来自服务端 `GET /videos/{id}/streams`，返回 direct（原文件直发）与 hls（服务端 ffmpeg 转码）两类 source。
- 服务端按**浏览器兼容标准**决定是否列出 direct 源（`mp4+h264+aac/mp3`、`webm+vp8/vp9` 才列），mkv/wmv/h265 等格式只给 HLS。
- HLS 依赖服务端安装 ffmpeg；开源发布不能要求用户装。已实测：Windows 服务端无 ffmpeg 时，wmv 视频（IDBD-747）客户端无法播放（HLS 分片返回 500 `ffmpeg not found`）。
- 已实测：direct 接口 `/videos/{id}/stream` 本身无格式限制（wmv 也返回 206 + Range），只是没被列入 sources。

## 目标

1. 客户端在服务端**不装 ffmpeg** 的前提下，能播放尽可能多格式（mkv/h265/ac3 等靠 ExoPlayer 硬解直连；wmv/rmvb/flv/avi 等靠 libVLC 软解兜底）。
2. 播放请求全程带会话 Cookie 鉴权。
3. 常见格式（mp4/mkv/ts）保持现有 ExoPlayer 体验（硬解、控制条），不被 libVLC 替换。
4. 支持硬解优先：h264/h265/vp9/av1 必须走 MediaCodec 硬解。

## 非目标

- 不修改服务端（客户端兼容原版 JavBoss）。
- 不追求 wmv 等冷门格式的硬解（无硬解器存在，任何内核都只能软解）。
- 本阶段不改 TV 版。

## 方案概述

### 1. 播放源策略（方案 B）

`VideoRepository.resolvePlayUrls()` 改为：**direct 永远排最前**，服务端未列出 direct 源时按固定格式自拼 `/videos/{id}/stream` 追加；HLS 排最后兜底。

### 2. 双播放器状态机

```
EXO 引擎：按序尝试 urls[0..n]（现有逻辑）
  → 全部失败 → 记录当前进度，切换 VLC 引擎
VLC 引擎：同样的 urls（经本地代理），seek 续播，逐个尝试
  → 全部失败 → 显示错误文案
```

### 3. libVLC 集成

- 依赖 `org.videolan.android:libvlc-all:3.6.5`（Maven Central，VideoLAN 官方，LGPL-2.1 动态链接合规）。
- 硬解：libVLC 默认启用 MediaCodec，无需额外配置。
- 渲染：`VLCVideoLayout`（AndroidView 封装）+ 自绘简易控制条（点按显隐：播放/暂停、进度条拖动、时间显示），VLC 阶段不使用 media3 PlayerView。

### 4. 本地鉴权代理（AuthProxy）

libVLC 的 HTTP 模块无法注入自定义 Cookie 头（已读 VLC 3.x 源码确认：仅支持改 User-Agent/Referer，cookie jar 不暴露公开 API）。因此：

- App 内启动一个微型本地 HTTP 代理（`org.nanohttpd:nanohttpd`），绑定 `127.0.0.1:随机端口`。
- libVLC 播放地址为 `http://127.0.0.1:{port}/?url={urlencoded 上游绝对地址}`。
- 代理解析出上游地址，用共享 OkHttpClient 转发（自动带 CookieJar 中的会话 Cookie），流式回传（不缓冲整个 body），透传 `Range`/`Content-Range`/`Content-Length`/`Content-Type`/`Accept-Ranges`。
- HLS 的 m3u8 与分片走同一代理（m3u8 内分片为相对地址，VLC 会基于代理 URL 解析，自然回到代理）。
- 上游请求强制 `Accept-Encoding: identity`，避免 gzip 导致 Content-Length 不一致。
- 生命周期：随 AppContainer 创建（懒启动），进程结束自然回收；仅监听 loopback，无安全风险。

### 5. APK 体积

libvlc-all 每个 ABI 约 30MB 原生库。release 构建启用 ABI 分包（arm64-v8a / armeabi-v7a / x86_64 独立 APK），单包增量控制在 ~30MB。

## 验收标准

1. Windows 服务端**无 ffmpeg** 环境下：
   - wmv（IDBD-747）可播放（libVLC 阶段，软解），有声音有画面，可拖动进度。
   - mp4（h264）仍走 ExoPlayer direct 直连播放（logcat 无 libVLC 输出、代理无请求）。
2. 服务端有 ffmpeg 时行为不回退：常见格式仍 direct 优先。
3. 播放中切引擎时进度不丢失（从 ExoPlayer 失败位置续播）。
4. `gradlew.bat assembleDebug` 通过；模拟器（AVD → 10.0.2.2:8655 访问宿主机服务）实测通过。
