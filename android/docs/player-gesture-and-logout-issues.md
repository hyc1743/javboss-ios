# ISSUE：播放手势增强 & 退出按钮无响应（javboss-phone）

排查日期：2026-08-08。状态：已全部修复（2026-08-08，`assembleDebug` 通过）。

涉及代码位置（以下均为 `app/src/main/java/com/javboss/phone/` 下相对路径）：

- 播放页手势/控制条：`ui/player/PlayerScreen.kt`
- 播放引擎接口与实现：`ui/player/PlayerEngine.kt`、`ExoPlayerEngine.kt`、`VlcPlayerEngine.kt`
- 设置存储：`data/SettingsManager.kt`
- 登出链路：`ui/main/MainScreen.kt`、`navigation/NavGraph.kt`、`data/AuthRepository.kt`

---

## Issue 1：播放器手势增强 + 拖动灵敏度

### 需求

1. 可配置的全屏拖动 seek 灵敏度
2. 双击手势：左半屏后退 10s / 右半屏前进 10s / 中间暂停（或恢复）
3. 长按加速播放（按住 2x 之类，松开恢复原速）

### 现状排查

现有手势集中在 `PlayerScreen.kt:244-298` 的 `gestureModifier`，仅两类：

- **单击** → 切换控制条显隐（`:296-298`），无自动隐藏定时器
- **拖动三合一**（`:252-294`，`detectDragGestures`）：
  - 方向判定阈值 18px（`:264`）：横向 → SEEK；纵向按按下点分：左半屏 → 亮度、右半屏 → 音量（`:265-267`）
  - SEEK 为"预览 + 松手才生效"：`gestureSeekTarget = seekStartPositionMs + durationMs * totalX / 屏宽`（`:271`），拖动中只更新提示文案，`onDragEnd` 里才真正 `seekTo`（`:291-293`）
  - 亮度/音量直接生效（`:275-286`）
- 底部控制条用 Material3 `Slider`（`:470-474`），拖动每帧直接 `engine::seekTo`
- 锁定开关（`:350-368`）锁定时 `gestureModifier = Modifier`，全部手势禁用
- **无双击、无长按**

拖动灵敏度硬编码：划满整屏 = 走完整个视频时长（`:271`），无参数可调。

### 改动方案

| 需求 | 方案 | 涉及位置 |
|---|---|---|
| 双击 ±10s / 暂停 | `detectTapGestures` 自带 `onDoubleTap`，按落点 x 坐标的 1/3、2/3 分三屏。`seekBy` 无需改接口，UI 层 `seekTo((positionMs + delta).coerceIn(0, durationMs))` 即可 | `PlayerScreen.kt:296` |
| 长按加速 | `PlayerEngine` 接口（`PlayerEngine.kt:28-47`）无调速方法，需新增 `setPlaybackSpeed(speed: Float)`；ExoPlayer 用 `player.setPlaybackSpeed`，libVLC 用 `mediaPlayer.setRate`。手势侧 `onLongPress` 只在抬起时回调一次，"按住加速、松开恢复"需用 `awaitLongPressOrCancellation` 自定义，并决定长按中手指移动转 seek 时取消加速 | `PlayerEngine.kt`、两个引擎实现、`PlayerScreen.kt` |
| 拖动灵敏度 | 给 `:271` 公式乘系数。`SettingsManager` 目前仅 `engine_mode` 一项（`stringPreferencesKey` + `@Volatile` + `restore()` 模式），照此加新 key；UI 入口放播放页内 `PlayerSettingsPanel`（`:413-452`，注意 AGENTS.md 提到的 `ui/settings/` 设置页实际不存在，文档滞后） | `data/SettingsManager.kt`、`PlayerScreen.kt:271,423-449` |

### 注意点（实现时必读）

- 加 `onDoubleTap` 后，单击显隐控制条会延迟 ~300ms（等确认无双击），属标准行为
- 手势协程稳定性约定：传入手势闭包的任何新参数必须走 `rememberUpdatedState`（`PlayerScreen.kt:185` 注释已有明确要求），避免轮询刷新重启手势协程
- 双击与拖动天然互斥；与 Slider/按钮/设置面板遮罩（`:371-377`）均不冲突
- seek 完全在 UI 层直调引擎，ViewModel 无 seek 相关函数；引擎接口签名 `fun seekTo(positionMs: Long)`（`PlayerEngine.kt:43`）

---

## Bug 1：服务器不可达时点击"退出"无反应

### 现象

服务器连不上时，主页底部导航"退出"→ 确认弹窗点"退出"后，界面长时间（10~30 秒）无任何反应。

### 根因

登出流程被服务端请求阻塞，且全程无 UI 反馈。调用链：

1. `ui/main/MainScreen.kt:101-104` — 确认按钮点击后弹窗立即消失，之后没有任何加载态：
   ```kotlin
   TextButton(onClick = {
       showLogoutConfirm = false
       onLogout()
   }) { Text("退出") }
   ```
2. `navigation/NavGraph.kt:62-67` — `doLogout` 协程内**先等网络请求、再跳登录页**：
   ```kotlin
   scope.launch {
       app.container.authRepository.logout()  // ← 阻塞点
       goLogin()
   }
   ```
3. `data/AuthRepository.kt:25-29` — logout 第一步是 `POST auth/logout`；服务器不可达时挂到 OkHttp 超时（connect 10s / read 30s，`data/api/ApiClient.kt:186-187`，DNS 多 IP 时 `retryOnConnectionFailure` 逐路由重试，等待更久）。异常被 `runCatching` 吞掉，最终仍会清会话跳转——但这 10~30 秒里界面纹丝不动，重复点击还会叠加多个 logout 协程。

### 修复方案

本地先行：点击确认后立即 `cookieJar.clear()` + `session.clear()` + 跳登录页，服务端 `POST auth/logout` 改为后台 fire-and-forget。改动小，只涉及 `NavGraph.kt:62-67` 和 `AuthRepository.kt:25-29` 的顺序。

### 已排除的疑点

- **BackHandler 吞返回**：全 app 仅 `PlayerScreen.kt:212-214` 有 BackHandler（退出播放器用），与本 bug 无关；`MainActivity.kt` 无自定义返回处理
- **sessionExpired 循环导航**：401 → `AuthExpiredException`（`ApiClient.kt:193`）→ 各 Screen 跳登录页，无循环弹回
- **网络错误误跳登录**：`IOException` 只置 error 文案，不会误触发 sessionExpired，逻辑正确
- **本地清理本身**：`SessionManager.clear()`（纯 DataStore 写）、`SessionCookieJar.clear()`（纯内存）都不依赖网络，问题只在它们排在网络请求之后

### "退出"相关代码清单

| 位置 | 内容 |
|---|---|
| `ui/main/MainScreen.kt:66-72` | 底部导航第 4 项"退出"，点击弹确认框 |
| `ui/main/MainScreen.kt:95-110` | 确认 AlertDialog，确认键调 `onLogout()` |
| `navigation/NavGraph.kt:59-67` | `doLogout`：先 `authRepository.logout()` 再 `goLogin()` |
| `navigation/NavGraph.kt:53-57` | `goLogin`：navigate(LOGIN) + popUpTo(0) inclusive |
| `data/AuthRepository.kt:25-29` | `logout()`：`runCatching { POST auth/logout }` → 清 Cookie → 清会话 |
| `data/api/ApiClient.kt:56-57` | Retrofit `@POST("auth/logout")` |
| `data/api/ApiClient.kt:184-196` | OkHttp 超时配置 + 401 拦截器 |
| `data/SessionManager.kt:52-59` | `clear()`：清 DataStore |
| `data/api/SessionCookieJar.kt:30` | `clear()`：清内存 Cookie |
