package com.javboss.phone.navigation

import androidx.compose.runtime.Composable
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.javboss.phone.ui.detail.DetailScreen
import com.javboss.phone.ui.favorites.FavGroupScreen
import com.javboss.phone.ui.javlist.JavListScreen
import com.javboss.phone.ui.login.LoginScreen
import com.javboss.phone.ui.main.MainScreen
import com.javboss.phone.ui.player.PlayerScreen

object Routes {
    const val LOGIN = "login"
    const val MAIN = "main"
    const val DETAIL = "detail/{videoId}?code={code}"
    const val PLAYER = "player/{videoId}"
    const val JAVLIST =
        "javlist?title={title}&idolIds={idolIds}&tagIds={tagIds}&studioId={studioId}&seriesId={seriesId}"
    const val FAVGROUP = "favgroup/{groupId}?name={name}"

    /** videoId <= 0 表示纯元数据详情（作品没有关联视频），此时必须带 code */
    fun detail(videoId: Long, code: String? = null) =
        "detail/$videoId" + (code?.takeIf { it.isNotBlank() }
            ?.let { "?code=${android.net.Uri.encode(it)}" } ?: "")

    fun player(videoId: Long) = "player/$videoId"

    fun javList(
        title: String,
        idolIds: String = "",
        tagIds: String = "",
        studioId: Long = 0,
        seriesId: Long = 0,
    ) = "javlist?title=${android.net.Uri.encode(title)}" +
        "&idolIds=$idolIds&tagIds=$tagIds&studioId=$studioId&seriesId=$seriesId"

    fun favGroup(groupId: Long, name: String) =
        "favgroup/$groupId?name=${android.net.Uri.encode(name)}"
}

@Composable
fun JavBossNavGraph(startWithSession: Boolean) {
    val navController = rememberNavController()

    val goLogin = {
        navController.navigate(Routes.LOGIN) {
            popUpTo(0) { inclusive = true }
        }
    }

    NavHost(
        navController = navController,
        startDestination = if (startWithSession) Routes.MAIN else Routes.LOGIN,
    ) {
        composable(Routes.LOGIN) {
            LoginScreen(
                onLoginSuccess = {
                    navController.navigate(Routes.MAIN) {
                        popUpTo(Routes.LOGIN) { inclusive = true }
                    }
                },
            )
        }
        composable(Routes.MAIN) {
            MainScreen(
                onOpenDetail = { videoId, code -> navController.navigate(Routes.detail(videoId, code)) },
                onOpenJavList = { title, idolIds, tagIds, studioId, seriesId ->
                    navController.navigate(Routes.javList(title, idolIds, tagIds, studioId, seriesId))
                },
                onFavGroupClick = { id, name -> navController.navigate(Routes.favGroup(id, name)) },
                onSessionExpired = goLogin,
            )
        }
        composable(
            route = Routes.DETAIL,
            arguments = listOf(
                navArgument("videoId") { type = NavType.LongType },
                navArgument("code") {
                    type = NavType.StringType
                    nullable = true
                    defaultValue = null
                },
            ),
        ) { entry ->
            val videoId = entry.arguments?.getLong("videoId") ?: return@composable
            DetailScreen(
                videoId = videoId,
                javCode = entry.arguments?.getString("code"),
                onPlay = { navController.navigate(Routes.player(videoId)) },
                onOpenJavList = { title, idolIds, tagIds, studioId, seriesId ->
                    navController.navigate(Routes.javList(title, idolIds, tagIds, studioId, seriesId))
                },
                onBack = { navController.popBackStack() },
                onSessionExpired = goLogin,
            )
        }
        composable(
            route = Routes.JAVLIST,
            arguments = listOf(
                navArgument("title") { type = NavType.StringType; defaultValue = "" },
                navArgument("idolIds") { type = NavType.StringType; defaultValue = "" },
                navArgument("tagIds") { type = NavType.StringType; defaultValue = "" },
                navArgument("studioId") { type = NavType.LongType; defaultValue = 0L },
                navArgument("seriesId") { type = NavType.LongType; defaultValue = 0L },
            ),
        ) { entry ->
            val args = entry.arguments ?: return@composable
            JavListScreen(
                title = args.getString("title").orEmpty(),
                idolIds = args.getString("idolIds").orEmpty(),
                tagIds = args.getString("tagIds").orEmpty(),
                studioId = args.getLong("studioId"),
                seriesId = args.getLong("seriesId"),
                onOpenDetail = { videoId, code -> navController.navigate(Routes.detail(videoId, code)) },
                onBack = { navController.popBackStack() },
                onSessionExpired = goLogin,
            )
        }
        composable(
            route = Routes.FAVGROUP,
            arguments = listOf(
                navArgument("groupId") { type = NavType.LongType },
                navArgument("name") { type = NavType.StringType; defaultValue = "" },
            ),
        ) { entry ->
            val groupId = entry.arguments?.getLong("groupId") ?: return@composable
            FavGroupScreen(
                groupId = groupId,
                groupName = entry.arguments?.getString("name").orEmpty(),
                onOpenDetail = { videoId, code -> navController.navigate(Routes.detail(videoId, code)) },
                onBack = { navController.popBackStack() },
                onSessionExpired = goLogin,
            )
        }
        composable(
            route = Routes.PLAYER,
            arguments = listOf(navArgument("videoId") { type = NavType.LongType }),
        ) { entry ->
            val videoId = entry.arguments?.getLong("videoId") ?: return@composable
            PlayerScreen(
                videoId = videoId,
                onBack = { navController.popBackStack() },
            )
        }
    }
}
