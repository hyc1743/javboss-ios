package com.javboss.phone.ui.theme

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color

private val DarkColors = darkColorScheme(
    primary = Color(0xFFE57373),
    background = Color(0xFF121212),
    surface = Color(0xFF1E1E1E),
    surfaceVariant = Color(0xFF2A2A2A),
)

@Composable
fun JavBossTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = DarkColors,
    ) {
        // 必须包 Surface：否则根布局 LocalContentColor 默认黑色，
        // 不显式传 color 的 Text 在深底上直接隐身
        Surface(
            modifier = Modifier.fillMaxSize(),
            color = MaterialTheme.colorScheme.background,
            content = content,
        )
    }
}
