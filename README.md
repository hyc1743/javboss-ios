# JavBoss Phone

[JavBoss](https://github.com/Solr159/JavBoss) 的第三方 Android 手机客户端（学习项目）。
通过 JavBoss 服务端的 REST API 获取数据，以手机触摸交互呈现。

> 本项目与 JavBoss 官方无关，仅调用其自托管服务端的 HTTP API。

## 功能

- **登录**：服务器地址 + 密码，会话 Cookie 本地持久化（服务端会话 14 天有效）；
  地址可省略协议头（自动补 `http://`）
- **底部三 tab**
  - **视频**：原始视频列表，16:9 缩略图两列瀑布流，无限加载、搜索、排序、下拉刷新
  - **作品**：JAV 作品库，四个卡片墙视角（作品/女优/片商/系列），两列瀑布流、
    无限加载、搜索（点搜索图标展开）；作品视角带筛选底部弹层
    （排序/番号前缀/标签多选/仅单体/随机）；点女优/片商/系列卡片跳对应过滤作品列表
  - **收藏夹**：作品收藏夹列表（新建/重命名/删除），点进查看条目，长按移除
- **详情页**：封面、番号、发行日期、时长、片商、系列、演员、标签、视频截图；
  片商/系列/演员/标签均可点击跳转到对应过滤作品列表；外部链接直达 JavDB；
  操作栏含播放、收藏（勾选收藏夹 + 新建收藏夹）、编辑（标题/发行日期/时长/片商/系列/演员/标签，支持新建标签）
- **播放**：Media3 ExoPlayer，优先服务端 preferred 源（direct 直流，支持
  Range 拖动），播放失败自动 fallback 到 HLS 转码流；进入自动横屏 + 沉浸模式

## 构建

```bash
# debug
gradlew.bat assembleDebug

# release（需要 keystore.properties + keystore/release.jks）
gradlew.bat assembleRelease
```

产物在 `app/build/outputs/apk/`。applicationId 为 `com.javboss.phone`，
可与 TV 版（`com.javboss.tv`）共存安装。

## License

GPL-3.0
