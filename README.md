# JavBoss Phone

[JavBoss](https://github.com/Solr159/JavBoss) 的第三方 Android 手机客户端（学习项目）。
通过 JavBoss 服务端的 REST API 获取数据，以手机触摸交互呈现。

> 本项目与 JavBoss 官方无关，仅调用其自托管服务端的 HTTP API。

## 功能

- **登录**：服务器地址 + 密码，会话 Cookie 本地持久化（服务端会话 14 天有效）；
  地址可省略协议头（自动补 `http://`）；底部导航"退出"可主动登出
  （通知服务端销毁会话并清空本地 Cookie）
- **底部四 tab**
  - **视频**：原始视频列表，16:9 缩略图两列瀑布流，无限加载、搜索、排序、下拉刷新
  - **作品**：JAV 作品库，四个卡片墙视角（作品/女优/片商/系列），两列瀑布流、
    无限加载、搜索（点搜索图标展开）；作品视角带筛选底部弹层
    （排序/番号前缀/标签多选/仅单体/随机）；点女优/片商/系列卡片跳对应过滤作品列表
  - **收藏夹**：作品收藏夹列表（新建/重命名/删除），点进查看条目，长按移除
  - **设置**：播放引擎选择（自动 / 仅 ExoPlayer / 仅 libVLC），本地持久化
- **详情页**：封面、番号、发行日期、时长、片商、系列、演员、标签、视频截图；
  片商/系列/演员/标签均可点击跳转到对应过滤作品列表；外部链接直达 JavDB；
  操作栏含播放、收藏（勾选收藏夹 + 新建收藏夹）、编辑（标题/发行日期/时长/片商/系列/演员/标签，支持新建标签）
- **播放**：统一播放页 + 双引擎（引擎只负责解码渲染，页面和控制条只有一套，
  自绘控制条点按显隐：播放/暂停、进度拖动、时间、当前引擎标识、缓冲指示），
  进入自动横屏 + 沉浸模式
  - 首选 Media3 ExoPlayer：direct 直流优先（支持 Range 拖动；服务端按浏览器
    标准未列出 direct 源时客户端自拼 `/videos/{id}/stream` 补上），失败自动
    fallback 到 HLS 转码流
  - ExoPlayer 全部源失败自动切换 libVLC（内置完整 ffmpeg，wmv/rmvb/flv/avi
    等冷门格式软解兜底），从失败进度续播；libVLC 无法注入 Cookie，
    播放请求经 App 内本地代理（127.0.0.1）转发并附加会话 Cookie

## 使用

### 服务端准备：让 Windows 桌面版允许局域网访问

JavBoss 电脑版默认只监听 `127.0.0.1`（仅本机浏览器可访问），手机无法连接。
启动时加 `-addr 0.0.0.0:8655` 参数即可放行局域网访问：

1. **打开 cmd**：在 javboss.exe 所在文件夹的地址栏输入 `cmd` 回车，
   会直接以该目录为工作目录打开命令行窗口
   （也可以 `Win+R` 输入 `cmd` 后用 `cd /d 目录路径` 切换过去）
2. **输入启动命令**：

   ```
   javboss.exe -addr 0.0.0.0:8655
   ```

   技巧：把 javboss.exe 直接拖进 cmd 窗口会自动填入完整路径，
   再在末尾补上参数回车即可，例如：

   ```
   C:\Apps\JavBoss\javboss.exe -addr 0.0.0.0:8655
   ```

3. **放行防火墙**：首次启动若弹出 Windows 防火墙提示，勾选"专用网络"并允许访问；
   若没有弹窗，手动添加：设置 → Windows Defender 防火墙 → 高级设置 →
   入站规则 → 新建规则 → 端口 → TCP 8655 → 允许连接
4. **查看电脑 IP**:cmd 里运行 `ipconfig`，找到"IPv4 地址"（如 `192.168.1.10`）
5. **登录客户端**：手机与电脑连同一局域网，在登录页填服务器地址
   `http://192.168.1.10:8655` 和网页版登录密码

注意事项：

- cmd 窗口需保持打开，关闭窗口即停止服务；如需常驻可建一个快捷方式，
  把参数写进快捷方式的"目标"栏，再配任务计划程序开机启动
- 端口以 JavBoss 的 `config.toml` 里的 `port` 为准（默认 8655）；
  `-addr` 参数只决定监听地址，改过 `config.toml` 端口的话登录地址也要对应改
- 播放走的是服务端 HTTP 流（direct / HLS），与电脑上的 mpv 无关，
  不影响网页版继续用 mpv 播放
- 服务暴露到局域网后，知道密码的人才能访问，请设置强密码

## 构建

```bash
# debug
gradlew.bat assembleDebug

# release（需要 keystore.properties + keystore/release.jks）
gradlew.bat assembleRelease
```

产物在 `app/build/outputs/apk/`。release 按 ABI 分包
（arm64-v8a / armeabi-v7a / x86_64 + universal；libvlc 原生库每 ABI 约 30MB，
按设备安装对应包即可）。applicationId 为 `com.javboss.phone`，
可与 TV 版（`com.javboss.tv`）共存安装。

## License

GPL-3.0
