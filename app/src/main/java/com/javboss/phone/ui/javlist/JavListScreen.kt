package com.javboss.phone.ui.javlist

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.staggeredgrid.LazyVerticalStaggeredGrid
import androidx.compose.foundation.lazy.staggeredgrid.StaggeredGridCells
import androidx.compose.foundation.lazy.staggeredgrid.StaggeredGridItemSpan
import androidx.compose.foundation.lazy.staggeredgrid.items
import androidx.compose.foundation.lazy.staggeredgrid.rememberLazyStaggeredGridState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.javboss.phone.data.api.dto.JavDto
import com.javboss.phone.ui.components.CenterMessage
import com.javboss.phone.ui.components.GridFooter
import com.javboss.phone.ui.components.WorkCard

/** 演员/标签/片商/系列点击落地页：对应过滤条件的作品瀑布流 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun JavListScreen(
    title: String,
    idolIds: String,
    tagIds: String,
    studioId: Long,
    seriesId: Long,
    onOpenDetail: (videoId: Long, code: String?) -> Unit,
    onBack: () -> Unit,
    onSessionExpired: () -> Unit,
    viewModel: JavListViewModel = viewModel(),
) {
    val state = viewModel.uiState
    val gridState = rememberLazyStaggeredGridState()
    var pickerTarget by remember { mutableStateOf<JavDto?>(null) }

    LaunchedEffect(Unit) { viewModel.start(idolIds, tagIds, studioId, seriesId) }
    LaunchedEffect(state.sessionExpired) {
        if (state.sessionExpired) onSessionExpired()
    }
    LaunchedEffect(gridState) {
        snapshotFlow { gridState.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: -1 }
            .collect { lastIndex ->
                val total = gridState.layoutInfo.totalItemsCount
                if (total > 0 && lastIndex >= total - 4) viewModel.loadMore()
            }
    }

    val onWorkClick: (JavDto) -> Unit = { jav ->
        when {
            jav.videos.isEmpty() -> onOpenDetail(0, jav.code)
            jav.videos.size == 1 -> onOpenDetail(jav.videos.first().id, jav.code)
            else -> pickerTarget = jav
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(title, maxLines = 1) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回")
                    }
                },
            )
        },
    ) { padding ->
        Box(
            Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            when {
                state.items.isEmpty() && state.loading -> CenterMessage("加载中…")
                state.items.isEmpty() && state.error != null -> CenterMessage(state.error)
                state.items.isEmpty() && !state.loading -> CenterMessage("没有作品")
                else -> LazyVerticalStaggeredGrid(
                    columns = StaggeredGridCells.Fixed(2),
                    state = gridState,
                    contentPadding = PaddingValues(8.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalItemSpacing = 8.dp,
                    modifier = Modifier.fillMaxSize(),
                ) {
                    items(state.items, key = { it.id }) { jav ->
                        WorkCard(
                            coverUrl = viewModel.coverUrl(jav.code),
                            code = jav.code,
                            title = jav.title,
                            onClick = { onWorkClick(jav) },
                        )
                    }
                    item(span = StaggeredGridItemSpan.FullLine) {
                        GridFooter(state.loadingMore, state.endReached, state.total)
                    }
                }
            }
        }
    }

    pickerTarget?.let { jav ->
        AlertDialog(
            onDismissRequest = { pickerTarget = null },
            title = { Text(jav.code) },
            text = {
                Column {
                    Text("选择要查看的视频文件", style = MaterialTheme.typography.bodySmall)
                    Spacer(Modifier.height(8.dp))
                    jav.videos.forEach { video ->
                        TextButton(
                            onClick = {
                                pickerTarget = null
                                onOpenDetail(video.id, jav.code)
                            },
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Text(video.filename, maxLines = 1)
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { pickerTarget = null }) { Text("取消") }
            },
        )
    }
}
