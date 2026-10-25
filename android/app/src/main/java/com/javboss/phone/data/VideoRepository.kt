package com.javboss.phone.data

import com.javboss.phone.data.api.ApiClient
import com.javboss.phone.data.api.dto.IdolListResponse
import com.javboss.phone.data.api.dto.JavDto
import com.javboss.phone.data.api.dto.JavItemUpdateRequest
import com.javboss.phone.data.api.dto.JavListResponse
import com.javboss.phone.data.api.dto.JavTagsReplaceRequest
import com.javboss.phone.data.api.dto.PrefixDto
import com.javboss.phone.data.api.dto.SeriesDto
import com.javboss.phone.data.api.dto.SeriesListResponse
import com.javboss.phone.data.api.dto.StreamsResponse
import com.javboss.phone.data.api.dto.StudioListResponse
import com.javboss.phone.data.api.dto.TagDto
import com.javboss.phone.data.api.dto.TagNameRequest
import com.javboss.phone.data.api.dto.VideoDto
import com.javboss.phone.data.api.dto.VideoListResponse

class VideoRepository(private val apiClient: ApiClient) {

    suspend fun listVideos(limit: Int, offset: Int, search: String = "", sort: String = ""): VideoListResponse =
        apiClient.api().listVideos(limit = limit, offset = offset, search = search, sort = sort)

    suspend fun getVideo(id: Long): VideoDto =
        apiClient.api().getVideo(id)

    suspend fun getStreams(id: Long): StreamsResponse =
        apiClient.api().getStreams(id)

    /**
     * 播放源地址转绝对 URL。direct 永远排最前（免转码、原生 Range 拖动），
     * 服务端按浏览器标准未列出 direct 源时（mkv/wmv/h265 等）按固定格式自拼；
     * HLS 排最后兜底（依赖服务端 ffmpeg）。
     */
    suspend fun resolvePlayUrls(id: Long): List<String> {
        val streams = getStreams(id)
        val direct = streams.sources.firstOrNull { it.kind == "direct" }?.src
            ?: "videos/$id/stream"
        val hls = streams.sources.filter { it.kind == "hls" }.map { it.src }
        return (listOf(direct) + hls).map { apiClient.absoluteUrl(it) }
    }

    suspend fun reportPlay(id: Long) {
        runCatching { apiClient.api().incrementPlayCount(id) }
    }

    suspend fun searchJavs(
        limit: Int,
        offset: Int,
        search: String = "",
        idolIds: List<Long> = emptyList(),
        tagIds: List<Long> = emptyList(),
        studioId: Long? = null,
        seriesId: Long? = null,
        prefix: String = "",
        solo: Boolean = false,
        sort: String = "",
        seed: Long? = null,
    ): JavListResponse =
        apiClient.api().searchJav(
            limit = limit,
            offset = offset,
            search = search,
            idolIds = idolIds.joinToString(","),
            tagIds = tagIds.joinToString(","),
            studioId = studioId,
            seriesId = seriesId,
            prefix = prefix,
            solo = if (solo) 1 else 0,
            sort = sort,
            seed = seed,
        )

    suspend fun listJavPrefixes(): List<PrefixDto> =
        apiClient.api().listJavPrefixes()

    suspend fun listJavTags(): List<TagDto> =
        apiClient.api().listJavTags()

    suspend fun listJavIdols(limit: Int, offset: Int, search: String = "", sort: String = ""): IdolListResponse =
        apiClient.api().listJavIdols(limit = limit, offset = offset, search = search, sort = sort)

    suspend fun listJavStudios(limit: Int, offset: Int, search: String = ""): StudioListResponse =
        apiClient.api().listJavStudios(limit = limit, offset = offset, search = search)

    suspend fun listJavSeries(limit: Int, offset: Int, search: String = ""): SeriesListResponse =
        apiClient.api().listJavSeries(limit = limit, offset = offset, search = search)

    suspend fun getJavSeries(id: Long): SeriesDto? =
        runCatching { apiClient.api().getJavSeries(id) }.getOrNull()

    suspend fun listVideoScreenshots(videoId: Long) =
        runCatching { apiClient.api().listVideoScreenshots(videoId).items }.getOrDefault(emptyList())

    // ---------- 标签管理 / 作品编辑 / 外部链接 ----------

    /** 新建 JAV 标签，返回创建后的标签（服务端对空名/重名报 400） */
    suspend fun createJavTag(name: String): TagDto =
        apiClient.api().createJavTag(TagNameRequest(name))

    /** 全量替换一批作品的标签（勾选保存语义） */
    suspend fun replaceJavTags(javIds: List<Long>, tagIds: List<Long>) =
        apiClient.api().replaceJavTags(JavTagsReplaceRequest(javIds, tagIds))

    /** 编辑作品信息，仅传入需要修改的字段；返回更新后的作品 */
    suspend fun updateJavItem(id: Long, request: JavItemUpdateRequest): JavDto =
        apiClient.api().updateJavItem(id, request)

    /** 查询作品的 JavDB 页面地址；404/失败返回 null */
    suspend fun getJavDbUrl(code: String): String? =
        runCatching { apiClient.api().getJavDbUrl(code).url.takeIf { it.isNotBlank() } }.getOrNull()
}
