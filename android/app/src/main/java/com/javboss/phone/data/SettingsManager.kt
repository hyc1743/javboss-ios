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

/** 全屏拖动 seek 灵敏度：划满全屏对应的 seek 幅度 = factor × 视频时长 */
enum class SeekSensitivity(val label: String, val factor: Float) {
    LOW("低", 0.25f),
    MEDIUM("中", 1f),
    HIGH("高", 2f),
}

/** 应用设置持久化（播放引擎偏好、拖动 seek 灵敏度） */
class SettingsManager(private val context: Context) {

    private val keyEngineMode = stringPreferencesKey("engine_mode")
    private val keySeekSensitivity = stringPreferencesKey("seek_sensitivity")

    @Volatile
    var engineMode: EngineMode = EngineMode.AUTO
        private set

    @Volatile
    var seekSensitivity: SeekSensitivity = SeekSensitivity.MEDIUM
        private set

    suspend fun restore() {
        val prefs = context.settingsDataStore.data.first()
        engineMode = prefs[keyEngineMode]
            ?.let { runCatching { EngineMode.valueOf(it) }.getOrNull() }
            ?: EngineMode.AUTO
        seekSensitivity = prefs[keySeekSensitivity]
            ?.let { runCatching { SeekSensitivity.valueOf(it) }.getOrNull() }
            ?: SeekSensitivity.MEDIUM
    }

    suspend fun saveEngineMode(mode: EngineMode) {
        engineMode = mode
        context.settingsDataStore.edit { it[keyEngineMode] = mode.name }
    }

    suspend fun saveSeekSensitivity(value: SeekSensitivity) {
        seekSensitivity = value
        context.settingsDataStore.edit { it[keySeekSensitivity] = value.name }
    }
}
