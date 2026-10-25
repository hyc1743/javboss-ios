package com.javboss.phone.ui.detail

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.InputChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.javboss.phone.data.api.dto.IdolDto
import com.javboss.phone.data.api.dto.JavDto
import com.javboss.phone.data.api.dto.JavItemUpdateRequest
import com.javboss.phone.data.api.dto.TagDto
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

private val DATE_FORMAT: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd")
private val DATE_REGEX = Regex("""\d{4}-\d{2}-\d{2}""")

/**
 * 编辑作品信息弹窗：标题/发行日期/时长/片商/系列/演员/标签（含新建标签）。
 * 保存走 PUT /jav/items/{id}；注意服务端的 studio_id/series_id 传 null 表示不修改，
 * 所以这里不提供"清空片商/系列"操作。
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun EditDialog(
    jav: JavDto,
    viewModel: DetailViewModel,
    onDismiss: () -> Unit,
) {
    var title by remember { mutableStateOf(jav.title) }
    var releaseDate by remember {
        mutableStateOf(
            if (jav.releaseUnix > 0)
                Instant.ofEpochSecond(jav.releaseUnix).atZone(ZoneId.systemDefault())
                    .toLocalDate().format(DATE_FORMAT)
            else "",
        )
    }
    var durationMin by remember {
        mutableStateOf(if (jav.durationMin > 0) jav.durationMin.toString() else "")
    }
    var studioId by remember { mutableStateOf(jav.studio?.id) }
    var seriesId by remember { mutableStateOf(jav.seriesId) }
    var selectedIdols by remember { mutableStateOf(jav.idols) }
    var selectedTagIds by remember { mutableStateOf(jav.tags.map { it.id }.toSet()) }

    var options by remember { mutableStateOf<DetailViewModel.EditOptions?>(null) }
    var allTags by remember { mutableStateOf<List<TagDto>>(emptyList()) }
    var idolQuery by remember { mutableStateOf("") }
    var idolResults by remember { mutableStateOf<List<IdolDto>>(emptyList()) }
    var newTagName by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    LaunchedEffect(Unit) {
        val loaded = viewModel.loadEditOptions()
        options = loaded
        allTags = loaded.tags
    }
    // 演员搜索防抖
    LaunchedEffect(idolQuery) {
        if (idolQuery.isBlank()) {
            idolResults = emptyList()
            return@LaunchedEffect
        }
        delay(400)
        idolResults = viewModel.searchIdols(idolQuery.trim())
    }

    val dateValid = releaseDate.isBlank() || DATE_REGEX.matches(releaseDate)

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("编辑作品信息") },
        text = {
            Column(
                Modifier
                    .fillMaxWidth()
                    .heightIn(max = 480.dp)
                    .verticalScroll(rememberScrollState()),
            ) {
                OutlinedTextField(
                    value = title,
                    onValueChange = { title = it },
                    label = { Text("标题") },
                    modifier = Modifier.fillMaxWidth(),
                )
                Spacer(Modifier.height(8.dp))
                OutlinedTextField(
                    value = releaseDate,
                    onValueChange = { releaseDate = it },
                    label = { Text("发行日期") },
                    placeholder = { Text("YYYY-MM-DD") },
                    singleLine = true,
                    isError = !dateValid,
                    supportingText = if (!dateValid) ({ Text("格式应为 YYYY-MM-DD") }) else null,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    modifier = Modifier.fillMaxWidth(),
                )
                Spacer(Modifier.height(8.dp))
                OutlinedTextField(
                    value = durationMin,
                    onValueChange = { durationMin = it.filter(Char::isDigit) },
                    label = { Text("时长（分钟）") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    modifier = Modifier.fillMaxWidth(),
                )

                Spacer(Modifier.height(8.dp))
                val opts = options
                if (opts != null) {
                    EntityDropdown(
                        label = "片商",
                        entries = opts.studios.map { it.id to it.name },
                        selectedId = studioId,
                        onSelect = { studioId = it },
                    )
                    Spacer(Modifier.height(8.dp))
                    EntityDropdown(
                        label = "系列",
                        entries = opts.series.map { it.id to it.name },
                        selectedId = seriesId,
                        onSelect = { seriesId = it },
                    )
                } else {
                    Text("加载选项…", style = MaterialTheme.typography.bodySmall)
                }

                // 演员：已选 chips + 搜索添加
                Spacer(Modifier.height(16.dp))
                Text("演员", style = MaterialTheme.typography.labelLarge)
                if (selectedIdols.isNotEmpty()) {
                    Spacer(Modifier.height(4.dp))
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        selectedIdols.forEach { idol ->
                            InputChip(
                                selected = true,
                                onClick = {
                                    selectedIdols = selectedIdols.filterNot { it.id == idol.id }
                                },
                                label = { Text(idol.displayName) },
                            )
                        }
                    }
                }
                Spacer(Modifier.height(4.dp))
                OutlinedTextField(
                    value = idolQuery,
                    onValueChange = { idolQuery = it },
                    label = { Text("搜索演员添加") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                idolResults.forEach { idol ->
                    TextButton(
                        onClick = {
                            if (selectedIdols.none { it.id == idol.id }) {
                                selectedIdols = selectedIdols + idol
                            }
                            idolQuery = ""
                            idolResults = emptyList()
                        },
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text(idol.displayName + if (idol.name != idol.displayName) "（${idol.name}）" else "")
                    }
                }

                // 标签：多选 + 新建
                Spacer(Modifier.height(16.dp))
                Text("标签", style = MaterialTheme.typography.labelLarge)
                Spacer(Modifier.height(4.dp))
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    allTags.forEach { tag ->
                        FilterChip(
                            selected = tag.id in selectedTagIds,
                            onClick = {
                                selectedTagIds = if (tag.id in selectedTagIds)
                                    selectedTagIds - tag.id else selectedTagIds + tag.id
                            },
                            label = { Text(tag.name) },
                        )
                    }
                }
                Spacer(Modifier.height(4.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    OutlinedTextField(
                        value = newTagName,
                        onValueChange = { newTagName = it },
                        label = { Text("新建标签") },
                        singleLine = true,
                        modifier = Modifier.weight(1f),
                    )
                    TextButton(
                        onClick = {
                            val name = newTagName.trim()
                            if (name.isEmpty()) return@TextButton
                            scope.launch {
                                try {
                                    val tag = viewModel.createTag(name)
                                    allTags = allTags + tag
                                    selectedTagIds = selectedTagIds + tag.id
                                    newTagName = ""
                                } catch (e: Exception) {
                                    error = "创建标签失败：名称可能已存在"
                                }
                            }
                        },
                        enabled = newTagName.isNotBlank(),
                    ) { Text("新建") }
                }

                error?.let {
                    Spacer(Modifier.height(8.dp))
                    Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    viewModel.saveEdit(
                        jav.id,
                        JavItemUpdateRequest(
                            title = title,
                            tagIds = selectedTagIds.toList(),
                            idolIds = selectedIdols.map { it.id },
                            studioId = studioId,
                            seriesId = seriesId,
                            releaseDate = releaseDate.ifBlank { null },
                            durationMin = durationMin.toIntOrNull(),
                        ),
                    )
                    onDismiss()
                },
                enabled = dateValid,
            ) { Text("保存") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("取消") }
        },
    )
}

/** 标签创建是 suspend 操作，弹窗内用 rememberCoroutineScope 调用 */

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun EntityDropdown(
    label: String,
    entries: List<Pair<Long, String>>,
    selectedId: Long?,
    onSelect: (Long?) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    val selectedName = entries.firstOrNull { it.first == selectedId }?.second ?: "未设置"
    ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }) {
        OutlinedTextField(
            value = selectedName,
            onValueChange = {},
            readOnly = true,
            singleLine = true,
            label = { Text(label) },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded) },
            modifier = Modifier
                .fillMaxWidth()
                .menuAnchor(),
        )
        ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            DropdownMenuItem(
                text = { Text("不修改") },
                onClick = {
                    expanded = false
                    onSelect(null)
                },
            )
            entries.forEach { (id, name) ->
                DropdownMenuItem(
                    text = { Text(name) },
                    onClick = {
                        expanded = false
                        onSelect(id)
                    },
                )
            }
        }
    }
}
