package com.javboss.phone.data.api.dto

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * 与服务端 Gin API 对应的 DTO。
 * 只声明客户端用到的字段；Json 配置里开启了 ignoreUnknownKeys。
 * 所有字段都给默认值或可空，保证服务端版本演进后新增/缺失字段不崩。
 */

@Serializable
data class AuthStatusResponse(
    val authenticated: Boolean = false,
)

@Serializable
data class LoginRequest(
    val password: String,
)

@Serializable
data class LoginResponse(
    val authenticated: Boolean = false,
)

@Serializable
data class ApiErrorResponse(
    @SerialName("error_zh") val errorZh: String = "",
    @SerialName("error_en") val errorEn: String = "",
) {
    val displayMessage: String get() = errorZh.ifBlank { errorEn.ifBlank { "请求失败" } }
}

@Serializable
data class VideoListResponse(
    val items: List<VideoDto> = emptyList(),
    val total: Int = 0,
)

@Serializable
data class VideoDto(
    val id: Long = 0,
    val filename: String = "",
    val size: Long = 0,
    @SerialName("duration_sec") val durationSec: Long = 0,
    @SerialName("play_count") val playCount: Long = 0,
    val jav: JavDto? = null,
    val tags: List<TagDto> = emptyList(),
) {
    /** 展示用标题：优先 JAV 番号 + 标题，否则文件名 */
    val displayTitle: String
        get() = jav?.let { "${it.code} ${it.title}" }?.trim() ?: filename
}

@Serializable
data class JavDto(
    val id: Long = 0,
    val code: String = "",
    val title: String = "",
    @SerialName("title_en") val titleEn: String = "",
    @SerialName("release_unix") val releaseUnix: Long = 0,
    @SerialName("duration_min") val durationMin: Int = 0,
    @SerialName("is_uncensored") val isUncensored: Boolean = false,
    @SerialName("favorite_count") val favoriteCount: Int = 0,
    @SerialName("series_id") val seriesId: Long? = null,
    val studio: StudioDto? = null,
    val tags: List<TagDto> = emptyList(),
    val idols: List<IdolDto> = emptyList(),
    val videos: List<VideoDto> = emptyList(),
)

/** /jav/prefixes 返回项：番号前缀及其归属片商、作品数 */
@Serializable
data class PrefixDto(
    val prefix: String = "",
    @SerialName("studio_id") val studioId: Long = 0,
    @SerialName("studio_name") val studioName: String = "",
    @SerialName("work_count") val workCount: Int = 0,
    @SerialName("sample_code") val sampleCode: String = "",
)

@Serializable
data class JavListResponse(
    val items: List<JavDto> = emptyList(),
    val total: Int = 0,
)

@Serializable
data class StudioDto(
    val id: Long = 0,
    val name: String = "",
    @SerialName("work_count") val workCount: Int = 0,
    @SerialName("sample_code") val sampleCode: String = "",
)

@Serializable
data class IdolDto(
    val id: Long = 0,
    val name: String = "",
    @SerialName("roman_name") val romanName: String = "",
    @SerialName("japanese_name") val japaneseName: String = "",
    @SerialName("chinese_name") val chineseName: String = "",
    @SerialName("cover_code") val coverCode: String = "",
    @SerialName("work_count") val workCount: Int = 0,
    @SerialName("height_cm") val heightCm: Int = 0,
    @SerialName("birth_date") val birthDate: String = "",
) {
    val displayName: String get() = chineseName.ifBlank { name }
}

@Serializable
data class IdolListResponse(
    val items: List<IdolDto> = emptyList(),
    val total: Int = 0,
)

@Serializable
data class StudioListResponse(
    val items: List<StudioDto> = emptyList(),
    val total: Int = 0,
)

@Serializable
data class SeriesDto(
    val id: Long = 0,
    val name: String = "",
    @SerialName("studio_name") val studioName: String = "",
    @SerialName("work_count") val workCount: Int = 0,
    @SerialName("sample_code") val sampleCode: String = "",
)

@Serializable
data class SeriesListResponse(
    val items: List<SeriesDto> = emptyList(),
    val total: Int = 0,
)

@Serializable
data class TagDto(
    val id: Long = 0,
    val name: String = "",
    val count: Int = 0,
)

@Serializable
data class StreamsResponse(
    @SerialName("video_id") val videoId: Long = 0,
    @SerialName("preferred_kind") val preferredKind: String = "direct",
    val sources: List<StreamSourceDto> = emptyList(),
)

@Serializable
data class StreamSourceDto(
    val kind: String = "",
    val src: String = "",
    @SerialName("mime_type") val mimeType: String = "",
    val label: String = "",
)

@Serializable
data class ScreenshotDto(
    val name: String = "",
    @SerialName("is_cover") val isCover: Boolean = false,
)

@Serializable
data class ScreenshotListResponse(
    val items: List<ScreenshotDto> = emptyList(),
)

// ---------- 收藏夹（/jav/jav-favorite-groups） ----------

@Serializable
data class FavoriteGroupDto(
    val id: Long = 0,
    @SerialName("entity_type") val entityType: String = "",
    val name: String = "",
    val count: Long = 0,
    @SerialName("sort_order") val sortOrder: Int = 0,
)

@Serializable
data class FavoriteGroupListResponse(
    val items: List<FavoriteGroupDto> = emptyList(),
)

@Serializable
data class FavoriteItemDto(
    val id: Long = 0,
    @SerialName("entity_type") val entityType: String = "",
    val name: String = "",
    @SerialName("roman_name") val romanName: String = "",
    @SerialName("japanese_name") val japaneseName: String = "",
    @SerialName("chinese_name") val chineseName: String = "",
    val code: String = "",
    val title: String = "",
    @SerialName("title_en") val titleEn: String = "",
    @SerialName("work_count") val workCount: Long = 0,
    @SerialName("sample_code") val sampleCode: String = "",
)

@Serializable
data class FavoriteItemListResponse(
    val items: List<FavoriteItemDto> = emptyList(),
)

@Serializable
data class FavoriteGroupNameRequest(val name: String)

@Serializable
data class SelectedFavoriteGroupsResponse(
    @SerialName("selected_group_ids") val selectedGroupIds: List<Long> = emptyList(),
)

@Serializable
data class ReplaceFavoriteGroupsRequest(
    @SerialName("group_ids") val groupIds: List<Long>,
)

@Serializable
data class RemoveFavoriteItemsRequest(
    @SerialName("entity_ids") val entityIds: List<Long>,
)

// ---------- 标签（/jav/tags） ----------

@Serializable
data class TagNameRequest(val name: String)

@Serializable
data class JavTagsReplaceRequest(
    @SerialName("jav_ids") val javIds: List<Long>,
    @SerialName("tag_ids") val tagIds: List<Long>,
)

// ---------- 作品编辑（PUT /jav/items/{id}），全部字段可选 ----------

@Serializable
data class JavItemUpdateRequest(
    val title: String? = null,
    @SerialName("tag_ids") val tagIds: List<Long>? = null,
    @SerialName("idol_ids") val idolIds: List<Long>? = null,
    @SerialName("studio_id") val studioId: Long? = null,
    @SerialName("series_id") val seriesId: Long? = null,
    @SerialName("release_date") val releaseDate: String? = null,
    @SerialName("duration_min") val durationMin: Int? = null,
)

// ---------- 外部链接（/jav/javdb-url） ----------

@Serializable
data class JavDbUrlResponse(
    val url: String = "",
)
