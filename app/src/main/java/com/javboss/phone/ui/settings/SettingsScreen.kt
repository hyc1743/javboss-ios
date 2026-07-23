package com.javboss.phone.ui.settings

import android.app.Application
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.javboss.phone.JavBossApp
import com.javboss.phone.data.EngineMode
import kotlinx.coroutines.launch

class SettingsViewModel(app: Application) : AndroidViewModel(app) {
    private val settings = (app as JavBossApp).container.settings

    var engineMode by mutableStateOf(settings.engineMode)
        private set

    fun selectEngineMode(mode: EngineMode) {
        engineMode = mode
        viewModelScope.launch { settings.saveEngineMode(mode) }
    }
}

/** 设置 tab：播放引擎偏好（即时生效，下次进入播放页使用） */
@Composable
fun SettingsScreen(
    viewModel: SettingsViewModel = viewModel(),
) {
    Column(Modifier.fillMaxSize().padding(16.dp)) {
        Text(
            "播放引擎",
            style = MaterialTheme.typography.titleMedium,
            modifier = Modifier.padding(bottom = 8.dp),
        )
        EngineMode.entries.forEach { mode ->
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { viewModel.selectEngineMode(mode) }
                    .padding(vertical = 4.dp),
            ) {
                RadioButton(
                    selected = viewModel.engineMode == mode,
                    onClick = { viewModel.selectEngineMode(mode) },
                )
                Column(Modifier.padding(start = 8.dp)) {
                    Text(mode.label, style = MaterialTheme.typography.bodyLarge)
                    Text(
                        mode.desc,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            if (mode != EngineMode.entries.last()) HorizontalDivider()
        }
    }
}
