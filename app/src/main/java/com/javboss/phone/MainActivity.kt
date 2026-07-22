package com.javboss.phone

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import com.javboss.phone.navigation.JavBossNavGraph
import com.javboss.phone.ui.theme.JavBossTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val startWithSession = (application as JavBossApp).container.session.hasSession
        setContent {
            JavBossTheme {
                JavBossNavGraph(startWithSession = startWithSession)
            }
        }
    }
}
