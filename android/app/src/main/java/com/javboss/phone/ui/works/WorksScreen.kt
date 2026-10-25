package com.javboss.phone.ui.works

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.javboss.phone.data.api.dto.JavDto
import com.javboss.phone.ui.components.CenterMessage
import com.javboss.phone.ui.components.EntityCard
import com.javboss.phone.ui.components.GridFooter
import com.javboss.phone.ui.components.WorkCard

/**
 * 作品库 tab：作品/女优/片商/系列四个卡片墙视角。
 * 顶栏为四个视角按钮 + 搜索图标按钮（点开才显示搜索框）+ 筛选图标（仅作品视角）。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WorksScreen(
    onOpenDetail: (videoId: Long, code: String?) -> Unit,
    onOpenJavList: (title: String, idolIds: String, tagIds: String, studioId: Long, seriesId: Long) -> Unit,
    onSessionExpired: () -> Unit,
    viewModel: WorksViewModel = viewModel(),
) {
    val state = viewModel.uiState
    val gridState = rememberLazyStaggeredGridState()
    var searchOpen by rememberSaveable { mutableStateOf(false) }
    var showFilter by remember { mutableStateOf(false) }
    // 一部作品有多个视频文件时，先弹选择框
    var pickerTarget by remember { mutableStateOf<JavDto?>(null) }

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

    Column(Modifier.fillMaxSize()) {
        // 顶栏：四个视角按钮 + 搜索图标 + 筛选图标（仅作品视角）
        Row(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            LibraryTab.entries.forEach { tab ->
                FilterChip(
                    selected = state.tab == tab,
                    onClick = { viewModel.onTabChange(tab) },
                    label = { Text(tab.label) },
                )
            }
            Spacer(Modifier.weight(1f))
            IconButton(onClick = {
                searchOpen = !searchOpen
                if (!searchOpen && state.search.isNotEmpty()) viewModel.onSearchChange("")
            }) {
                Icon(
                    if (searchOpen) Icons.Filled.Close else Icons.Filled.Search,
                    contentDescription = if (searchOpen) "收起搜索" else "搜索",
                )
            }
            if (state.tab == LibraryTab.WORKS) {
                IconButton(onClick = {
                    viewModel.loadFilterOptions()
                    showFilter = true
                }) {
                    Icon(Icons.Filled.FilterList, contentDescription = "筛选")
                }
            }
        }

        // 搜索框：点搜索图标才展开
        if (searchOpen) {
            OutlinedTextField(
                value = state.search,
                onValueChange = viewModel::onSearchChange,
                placeholder = {
                    Text(
                        when (state.tab) {
                            LibraryTab.WORKS -> "搜索番号 / 标题"
                            LibraryTab.IDOLS -> "搜索女优"
                            LibraryTab.STUDIOS -> "搜索片商"
                            LibraryTab.SERIES -> "搜索系列"
                        },
                    )
                },
                leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
                singleLine = true,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp)
                    .padding(bottom = 8.dp),
            )
        }

        PullToRefreshBox(
            isRefreshing = when (state.tab) {
                LibraryTab.WORKS -> state.loading && state.items.isNotEmpty()
                LibraryTab.IDOLS -> state.idols.loading && state.idols.items.isNotEmpty()
                LibraryTab.STUDIOS -> state.studios.loading && state.studios.items.isNotEmpty()
                LibraryTab.SERIES -> state.series.loading && state.series.items.isNotEmpty()
            },
            onRefresh = viewModel::refreshCurrent,
            modifier = Modifier.fillMaxSize(),
        ) {
            LazyVerticalStaggeredGrid(
                columns = StaggeredGridCells.Fixed(2),
                state = gridState,
                contentPadding = PaddingValues(8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalItemSpacing = 8.dp,
                modifier = Modifier.fillMaxSize(),
            ) {
                when (state.tab) {
                    LibraryTab.WORKS -> {
                        if (state.items.isEmpty() && !state.loading) {
                            item(span = StaggeredGridItemSpan.FullLine) {
                                CenterMessage(
                                    if (state.error != null) state.error
                                    else if (state.loading) "加载中…" else "没有作品",
                                )
                            }
                        }
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
                    LibraryTab.IDOLS -> {
                        if (state.idols.items.isEmpty() && !state.idols.loading) {
                            item(span = StaggeredGridItemSpan.FullLine) { CenterMessage("没有女优") }
                        }
                        items(state.idols.items, key = { it.id }) { idol ->
                            EntityCard(
                                coverUrl = viewModel.idolCoverUrl(idol),
                                name = idol.displayName,
                                subtitle = "${idol.workCount} 部作品",
                                onClick = {
                                    onOpenJavList("演员：${idol.displayName}", idol.id.toString(), "", 0, 0)
                                },
                            )
                        }
                        item(span = StaggeredGridItemSpan.FullLine) {
                            GridFooter(state.idols.loadingMore, state.idols.endReached, state.idols.total)
                        }
                    }
                    LibraryTab.STUDIOS -> {
                        if (state.studios.items.isEmpty() && !state.studios.loading) {
                            item(span = StaggeredGridItemSpan.FullLine) { CenterMessage("没有片商") }
                        }
                        items(state.studios.items, key = { it.id }) { studio ->
                            EntityCard(
                                coverUrl = viewModel.sampleCoverUrl(studio.sampleCode),
                                name = studio.name,
                                subtitle = "${studio.workCount} 部作品",
                                onClick = {
                                    onOpenJavList("片商：${studio.name}", "", "", studio.id, 0)
                                },
                            )
                        }
                        item(span = StaggeredGridItemSpan.FullLine) {
                            GridFooter(state.studios.loadingMore, state.studios.endReached, state.studios.total)
                        }
                    }
                    LibraryTab.SERIES -> {
                        if (state.series.items.isEmpty() && !state.series.loading) {
                            item(span = StaggeredGridItemSpan.FullLine) { CenterMessage("没有系列") }
                        }
                        items(state.series.items, key = { it.id }) { series ->
                            EntityCard(
                                coverUrl = viewModel.sampleCoverUrl(series.sampleCode),
                                name = series.name,
                                subtitle = "${series.workCount} 部作品",
                                onClick = {
                                    onOpenJavList("系列：${series.name}", "", "", 0, series.id)
                                },
                            )
                        }
                        item(span = StaggeredGridItemSpan.FullLine) {
                            GridFooter(state.series.loadingMore, state.series.endReached, state.series.total)
                        }
                    }
                }
            }
        }
    }

    if (showFilter) {
        ModalBottomSheet(onDismissRequest = { showFilter = false }) {
            FilterSheet(
                state = state,
                onSortClick = viewModel::onSortClick,
                onPrefixChange = viewModel::onPrefixChange,
                onTagToggle = viewModel::onTagToggle,
                onSoloChange = viewModel::onSoloChange,
                onRandomChange = viewModel::onRandomChange,
                onClear = viewModel::clearFilters,
            )
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

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun FilterSheet(
    state: WorksUiState,
    onSortClick: (JavSortBase) -> Unit,
    onPrefixChange: (String) -> Unit,
    onTagToggle: (Long) -> Unit,
    onSoloChange: (Boolean) -> Unit,
    onRandomChange: (Boolean) -> Unit,
    onClear: () -> Unit,
) {
    // 番号前缀/标签列表一次只展开一个，避免面板过长
    var openSection by remember { mutableStateOf<String?>(null) }

    Column(
        Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp)
            .padding(bottom = 32.dp),
    ) {
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("筛选", style = MaterialTheme.typography.titleMedium)
            TextButton(onClick = onClear) { Text("清空") }
        }

        Text("排序", style = MaterialTheme.typography.labelLarge)
        Spacer(Modifier.height(8.dp))
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            JavSortBase.entries.forEach { base ->
                val selected = !state.random && state.sort == base
                FilterChip(
                    selected = selected,
                    onClick = { onSortClick(base) },
                    label = {
                        Text(
                            if (selected)
                                "${base.label} ${if (state.sortAsc) base.ascLabel else base.descLabel}"
                            else base.label,
                        )
                    },
                )
            }
        }

        Spacer(Modifier.height(16.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(
                selected = openSection == "prefix",
                onClick = { openSection = if (openSection == "prefix") null else "prefix" },
                label = {
                    Text(
                        "番号前缀" + if (state.prefix.isNotEmpty()) "（${state.prefix}）" else "",
                    )
                },
            )
            FilterChip(
                selected = openSection == "tags",
                onClick = { openSection = if (openSection == "tags") null else "tags" },
                label = {
                    Text(
                        "标签" + if (state.tagIds.isNotEmpty()) "（已选 ${state.tagIds.size}）" else "",
                    )
                },
            )
        }

        when (openSection) {
            "prefix" -> {
                Spacer(Modifier.height(8.dp))
                if (state.allPrefixes.isEmpty()) {
                    Text("没有可选前缀", style = MaterialTheme.typography.bodySmall)
                }
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(
                        selected = state.prefix.isEmpty(),
                        onClick = { onPrefixChange("") },
                        label = { Text("全部") },
                    )
                    state.allPrefixes.forEach { p ->
                        FilterChip(
                            selected = state.prefix == p.prefix,
                            onClick = { onPrefixChange(p.prefix) },
                            label = { Text("${p.prefix} (${p.workCount})") },
                        )
                    }
                }
            }
            "tags" -> {
                Spacer(Modifier.height(8.dp))
                if (state.allTags.isEmpty()) {
                    Text("没有标签", style = MaterialTheme.typography.bodySmall)
                }
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    state.allTags.forEach { tag ->
                        FilterChip(
                            selected = tag.id in state.tagIds,
                            onClick = { onTagToggle(tag.id) },
                            label = { Text("${tag.name} (${tag.count})") },
                        )
                    }
                }
            }
        }

        Spacer(Modifier.height(16.dp))
        HorizontalDivider()
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("仅单体作品")
            Switch(checked = state.solo, onCheckedChange = onSoloChange)
        }
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("随机排序")
            Switch(checked = state.random, onCheckedChange = onRandomChange)
        }
    }
}
