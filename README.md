# JavBoss iOS

[JavBoss](https://github.com/Solr159/JavBoss) 的 iOS 客户端实现。
本项目参照上游 JavBoss 的服务端 API、Web 功能和播放协议，使用 SwiftUI
实现移动端界面，并通过 GitHub Actions 自动构建 IPA。

上游项目负责服务端、Web 客户端和 API；本仓库负责 iOS 客户端实现，
不会修改上游服务端。`android/` 目录保留了 Android 客户端代码，作为移动端实现参考。

## 功能覆盖

参照上游 JavBoss 服务端 API 和 Web 客户端能力，覆盖主要移动端功能：

| 模块 | 功能 |
| --- | --- |
| 登录 | 服务器地址 + 密码、会话 Cookie 持久化（14 天自动续期）、登出销毁会话 |
| 视频 | 双列网格、无限加载、搜索/排序/随机、标签筛选、隐藏已关联作品；详情页含截图（设封面/删除/查看）、标签编辑、多位置管理（重命名/删除）、关联 JAV 作品（候选番号/在线查询/手动填写）、播放次数、观看进度 |
| 作品 | 作品/女优/片商/系列四视角卡片墙，搜索、排序、筛选（番号前缀/标签/女优/片商/系列/仅单体/收藏夹/喜爱度范围/随机种子）；作品详情：封面、元数据、演员、标签、预览图（抓取/查看）、关联视频、喜爱度、收藏夹、标题翻译、编辑、JavDB/Avsox 外链；女优：档案（身高/三围/生日/别名）、封面选择、编辑；片商：别名/番号前缀/系列、编辑；系列：译名编辑、名称翻译 |
| 收藏 | 作品/女优/片商/系列四类收藏夹：新建/重命名/删除/拖动排序、条目移除/排序、批量搜索添加作品 |
| 目录 | 目录列表（扫描进度）、添加（含服务器文件系统浏览器）、立即扫描/处理、停用/自动扫描/周期设置、删除 |
| 下载 | 下载任务列表（进度/重试/取消/删除）、新建磁力任务、下载器设置（本地目录/并发/最小体积、CloudDrive2 配置与连接测试） |
| 标签 | 作品标签 + 视频标签两套体系：增删改、分类 CRUD、批量归类、JavBus 分类导入 |
| 更多 | 修改密码、扩展 API 令牌（增删/轮换/复制）、服务器状态（资源监控、FFmpeg 工具下载、数据源可用性检测、完整配置 JSON）、服务器 LAN 访问开关 |
| 播放 | 全屏横屏、KSPlayer/FFmpeg 解码、Cookie/HTTP Header 鉴权、direct/HLS 多源切换、播放失败回退、字幕和手势控制；播放列表连续播放、断点续播、观看时长上报和实时进度同步 |

### 与上游 Web / Android 客户端的关系

- iOS 播放使用 KSPlayer 和 FFmpeg，沿用上游 `/videos/{id}/streams`、
  `location_id`、direct/HLS 和 playback session 协议。
- iOS、Android 和 Web 共享上游服务端数据和播放接口，界面与播放器实现根据各平台能力分别适配。
- 桌面端专属功能（mpv 播放器热键、浏览器集成等）不属于移动客户端范畴，
  通过扩展 API 令牌模块与浏览器扩展联动。

## 服务端准备

1. 在电脑上运行 [JavBoss](https://github.com/Solr159/JavBoss)（v1.9.0+）。
2. 进入「全局设置」开启「允许局域网访问」，按提示重启。
3. 首次启动若弹出 Windows 防火墙提示，勾选「专用网络」并允许访问。

## 构建 IPA（云端）

推送或手动触发 `.github/workflows/build-ipa.yml`（macOS runner）：

- **直接下载（推荐）**：每次构建成功后自动发布为 GitHub Release
  （滚动 tag `ios-latest`，Prerelease）：
  https://github.com/hyc1743/javboss-ios/releases/tag/ios-latest
  Release 附件 `JavBoss-unsigned.ipa` 未签名，需侧载工具用你自己的
  Apple ID 重签后安装（AltStore / Sideloadly / Esign）。
- 构建产物同时存于 Actions Artifact（90 天有效）。
- **可选签名构建**：在仓库 Settings → Secrets and variables → Actions 中配置
  `IOS_P12_BASE64`（证书 p12 base64）、`IOS_P12_PASSWORD`、`IOS_MOBILEPROVISION_BASE64`、
  `IOS_SIGNING_IDENTITY`（证书名）、`IOS_DEVELOPMENT_TEAM`（Team ID），
  已签名 IPA 会自动追加到同一个 Release，可直接安装到配置文件包含的设备。

### 本地构建

```bash
brew install xcodegen
cd ios
xcodegen generate
open JavBoss.xcodeproj   # Xcode 中直接运行（需自选签名团队）
```

## 目录结构

```
android/   Android 客户端代码（移动端参考实现）
ios/       参照上游 JavBoss 实现的 SwiftUI iOS 客户端（XcodeGen 工程）
  JavBoss/
    App/        入口、会话根视图、屏幕方向控制
    Core/       会话/Cookie/API 客户端/模型/通用组件
    Features/   登录、视频、作品、收藏、目录、下载、标签、更多、播放器
.github/workflows/build-ipa.yml   云端构建 IPA
```

## 许可

遵循上游许可（GPL-3.0，见 `android/LICENSE`）。本项目代码在相同许可下分发。
