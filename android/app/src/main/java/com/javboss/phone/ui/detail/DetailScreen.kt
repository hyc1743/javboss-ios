package com.javboss.phone.ui.detail

import android.content.Intent
import android.widget.Toast
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.core.net.toUri
import androidx.lifecycle.viewmodel.compose.viewModel
import coil3.compose.AsyncImage
import com.javboss.phone.data.api.dto.FavoriteGroupDto
import com.javboss.phone.ui.components.CenterMessage
import com.javboss.phone.ui.components.LabeledValue
import com.javboss.phone.ui.components.formatDuration
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

private val DATE_FORMAT: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd")

private fun formatReleaseDate(releaseUnix: Long): String =
    if (releaseUnix <= 0) ""
    else Instant.ofEpochSecond(releaseUnix).atZone(ZoneId.systemDefault()).toLocalDate().format(DATE_FORMAT)

/** 详情页：封面 + 元数据 + 可点击的片商/系列/演员/标签 + 外部链接 + 收藏/编辑 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun DetailScreen(
    videoId: Long,
    javCode: String?,
    onPlay: (Long) -> Unit,
    onOpenJavList: (title: String, idolIds: String, tagIds: String, studioId: Long, seriesId: Long) -> Unit,
    onBack: () -> Unit,
    onSessionExpired: () -> Unit,
    viewModel: DetailViewModel = viewModel(),
) {
    val state = viewModel.uiState
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var showFavorite by remember { mutableStateOf(false) }
    var showEdit by remember { mutableStateOf(false) }

    LaunchedEffect(videoId, javCode) { viewModel.load(videoId, javCode) }
    LaunchedEffect(state.sessionExpired) {
        if (state.sessionExpired) onSessionExpired()
    }
    LaunchedEffect(state.notice) {
        state.notice?.let {
            Toast.makeText(context, it, Toast.LENGTH_SHORT).show()
            viewModel.consumeNotice()
        }
    }

    val jav = state.javMeta
    val video = state.video
    val title = jav?.let { "${it.code} ${it.title}" }?.trim()?.takeIf { it.isNotBlank() }
        ?: video?.filename ?: javCode ?: "详情"

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回")
                    }
                },
            )
        },
    ) { padding ->
        when {
            state.loading -> CenterMessage("加载中…", Modifier.padding(padding))
            state.error != null -> CenterMessage(state.error, Modifier.padding(padding))
            else -> Column(
                Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .verticalScroll(rememberScrollState())
                    .padding(16.dp),
            ) {
                // 封面 + 基本信息
                Row(Modifier.fillMaxWidth()) {
                    AsyncImage(
                        model = viewModel.coverUrl(),
                        contentDescription = title,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier
                            .width(140.dp)
                            .aspectRatio(2f / 3f),
                    )
                    Spacer(Modifier.width(16.dp))
                    Column {
                        jav?.let {
                            Text(it.code, style = MaterialTheme.typography.titleMedium)
                            if (it.title.isNotBlank()) {
                                Spacer(Modifier.height(4.dp))
                                Text(it.title, style = MaterialTheme.typography.bodyMedium)
                            }
                            Spacer(Modifier.height(8.dp))
                            formatReleaseDate(it.releaseUnix).takeIf { d -> d.isNotEmpty() }?.let { d ->
                                LabeledValue("发行日期", d)
                            }
                            if (it.durationMin > 0) LabeledValue("时长", "${it.durationMin} 分钟")
                            if (it.favoriteCount > 0) LabeledValue("被收藏", "${it.favoriteCount} 次")
                        }
                        video?.let {
                            Spacer(Modifier.height(4.dp))
                            LabeledValue("文件", it.filename)
                            if (it.durationSec > 0) LabeledValue("视频时长", formatDuration(it.durationSec))
                            LabeledValue("播放次数", "${it.playCount}")
                        }
                    }
                }

                // 操作栏：播放 / 收藏 / 编辑
                Spacer(Modifier.height(16.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Button(
                        onClick = { video?.let { onPlay(it.id) } },
                        enabled = video != null,
                    ) {
                        Icon(Icons.Filled.PlayArrow, contentDescription = null)
                        Spacer(Modifier.width(4.dp))
                        Text("播放")
                    }
                    OutlinedButton(
                        onClick = { showFavorite = true },
                        enabled = jav != null,
                    ) {
                        Icon(Icons.Filled.Favorite, contentDescription = null)
                        Spacer(Modifier.width(4.dp))
                        Text("收藏")
                    }
                    OutlinedButton(
                        onClick = { showEdit = true },
                        enabled = jav != null,
                    ) {
                        Icon(Icons.Filled.Edit, contentDescription = null)
                        Spacer(Modifier.width(4.dp))
                        Text("编辑")
                    }
                }

                // 片商 / 系列（可点击）
                val studio = jav?.studio
                val seriesId = jav?.seriesId ?: 0
                if ((studio != null && studio.name.isNotBlank()) || (seriesId > 0 && state.seriesName.isNotBlank())) {
                    Spacer(Modifier.height(16.dp))
                    Text("片商 / 系列", style = MaterialTheme.typography.labelLarge)
                    Spacer(Modifier.height(8.dp))
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        if (studio != null && studio.name.isNotBlank()) {
                            AssistChip(
                                onClick = {
                                    onOpenJavList("片商：${studio.name}", "", "", studio.id, 0)
                                },
                                label = { Text(studio.name) },
                            )
                        }
                        if (seriesId > 0 && state.seriesName.isNotBlank()) {
                            AssistChip(
                                onClick = {
                                    onOpenJavList("系列：${state.seriesName}", "", "", 0, seriesId)
                                },
                                label = { Text(state.seriesName) },
                            )
                        }
                    }
                }

                // 演员（可点击）
                if (!jav?.idols.isNullOrEmpty()) {
                    Spacer(Modifier.height(16.dp))
                    Text("演员", style = MaterialTheme.typography.labelLarge)
                    Spacer(Modifier.height(8.dp))
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        jav!!.idols.forEach { idol ->
                            AssistChip(
                                onClick = {
                                    onOpenJavList("演员：${idol.displayName}", idol.id.toString(), "", 0, 0)
                                },
                                label = { Text(idol.displayName) },
                            )
                        }
                    }
                }

                // 标签（可点击）
                if (!jav?.tags.isNullOrEmpty()) {
                    Spacer(Modifier.height(16.dp))
                    Text("标签", style = MaterialTheme.typography.labelLarge)
                    Spacer(Modifier.height(8.dp))
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        jav!!.tags.forEach { tag ->
                            AssistChip(
                                onClick = {
                                    onOpenJavList("标签：${tag.name}", "", tag.id.toString(), 0, 0)
                                },
                                label = { Text(tag.name) },
                            )
                        }
                    }
                }

                // 外部链接
                if (!jav?.code.isNullOrBlank()) {
                    Spacer(Modifier.height(16.dp))
                    Text("外部链接", style = MaterialTheme.typography.labelLarge)
                    Spacer(Modifier.height(8.dp))
                    OutlinedButton(onClick = {
                        scope.launch {
                            val url = viewModel.resolveJavDbUrl(jav!!.code)
                            if (url != null) {
                                runCatching {
                                    context.startActivity(Intent(Intent.ACTION_VIEW, url.toUri()))
                                }
                            } else {
                                Toast.makeText(context, "未找到对应的 JavDB 页面", Toast.LENGTH_SHORT).show()
                            }
                        }
                    }) {
                        Icon(Icons.AutoMirrored.Filled.OpenInNew, contentDescription = null)
                        Spacer(Modifier.width(4.dp))
                        Text("JavDB")
                    }
                }

                // 截图
                if (video != null && state.screenshots.isNotEmpty()) {
                    Spacer(Modifier.height(16.dp))
                    Text("截图", style = MaterialTheme.typography.labelLarge)
                    Spacer(Modifier.height(8.dp))
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        items(state.screenshots, key = { it.name }) { shot ->
                            AsyncImage(
                                model = viewModel.screenshotUrl(video.id, shot.name),
                                contentDescription = shot.name,
                                contentScale = ContentScale.Crop,
                                modifier = Modifier
                                    .height(120.dp)
                                    .aspectRatio(16f / 9f),
                            )
                        }
                    }
                }
                Spacer(Modifier.height(32.dp))
            }
        }
    }

    if (showFavorite && jav != null) {
        FavoriteDialog(
            javId = jav.id,
            viewModel = viewModel,
            onDismiss = { showFavorite = false },
        )
    }
    if (showEdit && jav != null) {
        EditDialog(
            jav = jav,
            viewModel = viewModel,
            onDismiss = { showEdit = false },
        )
    }
}

/** 收藏弹窗：勾选收藏夹 + 新建收藏夹，保存时全量替换 */
@Composable
private fun FavoriteDialog(
    javId: Long,
    viewModel: DetailViewModel,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var groups by remember { mutableStateOf<List<FavoriteGroupDto>?>(null) }
    var selected by remember { mutableStateOf<Set<Long>>(emptySet()) }
    var newName by remember { mutableStateOf("") }
    var loadFailed by remember { mutableStateOf(false) }

    LaunchedEffect(javId) {
        try {
            val (g, s) = viewModel.loadFavoriteData(javId)
            groups = g
            selected = s
        } catch (e: Exception) {
            loadFailed = true
        }
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("收藏到…") },
        text = {
            Column {
                when {
                    loadFailed -> Text("加载收藏夹失败", color = MaterialTheme.colorScheme.error)
                    groups == null -> Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        CircularProgressIndicator(Modifier.size(20.dp))
                        Text("加载中…")
                    }
                    else -> {
                        if (groups!!.isEmpty()) {
                            Text("还没有收藏夹，先新建一个", style = MaterialTheme.typography.bodySmall)
                            Spacer(Modifier.height(8.dp))
                        }
                        groups!!.forEach { group ->
                            Row(
                                Modifier
                                    .fillMaxWidth()
                                    .clickable {
                                        selected = if (group.id in selected) selected - group.id
                                        else selected + group.id
                                    },
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Checkbox(
                                    checked = group.id in selected,
                                    onCheckedChange = null,
                                )
                                Text("${group.name} (${group.count})")
                            }
                        }
                        HorizontalDivider(Modifier.padding(vertical = 8.dp))
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            OutlinedTextField(
                                value = newName,
                                onValueChange = { newName = it },
                                label = { Text("新建收藏夹") },
                                singleLine = true,
                                modifier = Modifier.weight(1f),
                            )
                            TextButton(
                                onClick = {
                                    val name = newName.trim()
                                    if (name.isEmpty()) return@TextButton
                                    scope.launch {
                                        try {
                                            val created = viewModel.createFavoriteGroup(name)
                                            groups = groups!! + created
                                            selected = selected + created.id
                                            newName = ""
                                        } catch (e: Exception) {
                                            Toast.makeText(
                                                context, "创建失败：名称可能已存在", Toast.LENGTH_SHORT,
                                            ).show()
                                        }
                                    }
                                },
                                enabled = newName.isNotBlank(),
                            ) { Text("新建") }
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    viewModel.saveFavorite(javId, selected)
                    onDismiss()
                },
                enabled = groups != null,
            ) { Text("保存") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("取消") }
        },
    )
}
