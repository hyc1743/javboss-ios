package com.javboss.phone.data

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.first

private val Context.settingsDataStore by preferencesDataStore(name = "settings")

/** 播放引擎偏好 */
enum class EngineMode(val label: String, val desc: String) {
    AUTO("自动（推荐）", "ExoPlayer 优先，失败自动切 libVLC 兜底"),
    EXO("ExoPlayer", "硬解体验最好，但无法播放 wmv 等冷门格式"),
    VLC("libVLC", "全格式通吃，冷门格式软解较耗性能"),
}

/** 应用设置持久化（目前只有播放引擎偏好） */
class SettingsManager(private val context: Context) {

    private val keyEngineMode = stringPreferencesKey("engine_mode")

    @Volatile
    var engineMode: EngineMode = EngineMode.AUTO
        private set

    suspend fun restore() {
        val prefs = context.settingsDataStore.data.first()
        engineMode = prefs[keyEngineMode]
            ?.let { runCatching { EngineMode.valueOf(it) }.getOrNull() }
            ?: EngineMode.AUTO
    }

    suspend fun saveEngineMode(mode: EngineMode) {
        engineMode = mode
        context.settingsDataStore.edit { it[keyEngineMode] = mode.name }
    }
}
