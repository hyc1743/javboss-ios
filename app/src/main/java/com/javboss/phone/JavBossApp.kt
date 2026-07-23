package com.javboss.phone

import android.app.Application
import coil3.ImageLoader
import coil3.PlatformContext
import coil3.SingletonImageLoader
import coil3.network.okhttp.OkHttpNetworkFetcherFactory
import com.javboss.phone.data.AuthRepository
import com.javboss.phone.data.FavoriteRepository
import com.javboss.phone.data.SessionManager
import com.javboss.phone.data.VideoRepository
import com.javboss.phone.data.api.ApiClient
import com.javboss.phone.data.api.SessionCookieJar
import com.javboss.phone.data.localproxy.AuthProxy
import kotlinx.coroutines.runBlocking

/**
 * 手动 DI 容器：学习项目先不用 Hilt，看清依赖组装过程更有价值。
 */
class AppContainer(context: Application) {
    val session = SessionManager(context)
    val cookieJar = SessionCookieJar(session)
    val apiClient = ApiClient(session, cookieJar)
    val authRepository = AuthRepository(session, apiClient)
    val videoRepository = VideoRepository(apiClient)
    val favoriteRepository = FavoriteRepository(apiClient)
    // 本地鉴权代理：libVLC 播放时经它转发请求并附加会话 Cookie（懒启动）
    val authProxy = AuthProxy(apiClient.okHttpClient, apiClient::absoluteUrl)
}

class JavBossApp : Application(), SingletonImageLoader.Factory {

    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
        // 恢复上次会话（服务器地址 + Cookie），字节级数据，阻塞读可接受
        runBlocking {
            container.session.restore()
            container.cookieJar.restoreFromSession()
        }
    }

    /** Coil 复用同一个 OkHttpClient，封面图请求自动带上登录 Cookie */
    override fun newImageLoader(context: PlatformContext): ImageLoader =
        ImageLoader.Builder(context)
            .components {
                add(OkHttpNetworkFetcherFactory(callFactory = { container.apiClient.okHttpClient }))
            }
            .build()
}
