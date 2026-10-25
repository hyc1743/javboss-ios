# PLAN：全格式播放实施步骤（javboss-phone）

对应 spec：`docs/vlc-fallback-player-spec.md`

## 步骤

### 1. 依赖与构建配置

- `gradle/libs.versions.toml`：新增
  - `libvlc = "3.6.5"` → `org.videolan.android:libvlc-all`
  - `nanohttpd = "2.3.1"` → `org.nanohttpd:nanohttpd`
- `app/build.gradle.kts`：
  - dependencies 加两个库
  - release 加 ABI 分包：`splits { abi { isEnable = true; reset(); include("arm64-v8a", "armeabi-v7a", "x86_64"); isUniversalApk = true } }`（debug 不拆，避免拖慢编译）

### 2. AuthProxy（本地鉴权代理）

新增 `app/src/main/java/com/javboss/phone/data/localproxy/AuthProxy.kt`：

- 构造：`(okHttpClient: OkHttpClient)`；`start()` 绑 `127.0.0.1:0`（NanoHTTPD 子类）；`val baseUrl: String`
- `fun proxyUrl(upstreamAbsoluteUrl: String): String` → `http://127.0.0.1:{port}/?url={encode(upstream)}`
- `serve(session)`：解析 `url` 参数 → 构建上游请求（复制 `Range` 头、UA 置 `JavBossPhone/0.1`、`Accept-Encoding: identity`）→ `okHttpClient.newCall().execute()` → NanoHTTPD `newChunkedResponse`/固定流响应包装 `body.byteStream()`，状态码、Content-Type、Content-Length、Content-Range、Accept-Ranges 透传
- 上游非 2xx：把状态码原样返回给 VLC（让 VLC 判失败 → 触发源切换）
- 注意：响应流关闭时要连带关闭上游 Response（NanoHTTPD 会在流读完/连接断开时 close InputStream，包一层 `body.byteStream()` 的 close → `response.close()`）
- 挂到 `AppContainer`：`val authProxy = AuthProxy(apiClient.okHttpClient)`，首次播放时 `start()`（幂等）

### 3. 方案 B：resolvePlayUrls 改造

`data/VideoRepository.kt` 的 `resolvePlayUrls()`：

- direct 源取服务端给的；没有则自拼 `videos/{id}/stream`
- 顺序：`[direct] + [hls...]`，全部转绝对 URL

### 4. libVLC 封装

新增 `app/src/main/java/com/javboss/phone/ui/player/VlcPlayerController.kt`：

- 持有 `LibVLC`（参数 `--no-stats`）与 `MediaPlayer`
- `attach(layout: VLCVideoLayout)` / `play(url: String, startPositionMs: Long)` / `release()`
- 事件回调：`onError`（切下一个源）、`onPlaying`（首次 Playing 且 startPositionMs>0 时 `time = startPositionMs`）、`onEndReached`
- 位置/时长/播放中 状态暴露给控制条（轮询或 TimeChanged 事件）

### 5. PlayerScreen / PlayerViewModel 双引擎改造

`PlayerViewModel`：
- `PlayerUiState` 增加 `engine: Engine`（`EXO` / `VLC`）、`proxyUrlFor(url)` 透传 container.authProxy
- 新增 `onEngineFailed(fallbackPositionMs)`：EXO → VLC 切换（记录进度），VLC 全部失败 → `error` 文案

`PlayerScreen`：
- `engine == EXO`：现有 PlayerView 路径不动；ExoPlayer 所有源耗尽时改调 `viewModel.onEngineFailed(player.currentPosition)`（不再静默停住）
- `engine == VLC`：`AndroidView { VLCVideoLayout }` + VlcPlayerController，urls 经 `authProxy.proxyUrl()` 转换后逐个尝试；自绘简易控制条（点按显隐：播放/暂停按钮 + Slider 进度 + 时间文本）
- `DisposableEffect` release 两个播放器

### 6. 编译与模拟器实测

- `gradlew.bat assembleDebug`（JAVA_HOME 指向 JBR）
- `adb install -r` → 启动 → 登录 `http://10.0.2.2:8655` / admin（登录页默认密码已预填 admin，地址需改）
- 视频墙点 IDBD-747 → 播放：
  - 预期：ExoPlayer 两源失败 → 自动切 libVLC → 代理日志出现 GET → 出画面
  - logcat 观察：`okhttp.OkHttpClient`（代理转发）、`VLC`/`LibVLC` 输出
- `adb exec-out screencap` 截图确认画面
- 再验证一个 mp4 仍走 ExoPlayer（logcat 无 VLC 输出）

### 7. 文档收尾

- 更新 `README.md`（播放能力说明）、`AGENTS.md`（新增 localproxy、双引擎播放页、新依赖）

## 风险点

- NanoHTTPD 流式响应在上游慢/大文件时的线程模型（每连接一线程，可接受）
- libVLC 首次解码 wmv 软解 CPU 占用高，模拟器上可能卡顿（真机正常）；验收以"能出画面声音、进度可走"为准
- VLC 对 10GB+ 大文件的 seek 通过 Range 请求完成，代理必须正确透传 Range/206
