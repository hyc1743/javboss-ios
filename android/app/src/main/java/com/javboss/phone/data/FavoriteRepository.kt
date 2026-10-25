package com.javboss.phone.data

import com.javboss.phone.data.api.ApiClient
import com.javboss.phone.data.api.dto.FavoriteGroupDto
import com.javboss.phone.data.api.dto.FavoriteGroupNameRequest
import com.javboss.phone.data.api.dto.FavoriteItemDto
import com.javboss.phone.data.api.dto.RemoveFavoriteItemsRequest
import com.javboss.phone.data.api.dto.ReplaceFavoriteGroupsRequest

/** 作品收藏夹（/jav/jav-favorite-groups） */
class FavoriteRepository(private val apiClient: ApiClient) {

    suspend fun listGroups(): List<FavoriteGroupDto> =
        apiClient.api().listFavoriteGroups().items

    suspend fun createGroup(name: String): FavoriteGroupDto =
        apiClient.api().createFavoriteGroup(FavoriteGroupNameRequest(name))

    suspend fun renameGroup(id: Long, name: String) =
        apiClient.api().renameFavoriteGroup(id, FavoriteGroupNameRequest(name))

    suspend fun deleteGroup(id: Long) =
        apiClient.api().deleteFavoriteGroup(id)

    suspend fun listItems(groupId: Long): List<FavoriteItemDto> =
        apiClient.api().listFavoriteGroupItems(groupId).items

    suspend fun removeItems(groupId: Long, entityIds: List<Long>) =
        apiClient.api().removeFavoriteGroupItems(groupId, RemoveFavoriteItemsRequest(entityIds))

    /** 某作品当前所在的收藏夹 id 列表 */
    suspend fun selectedGroupIds(javId: Long): List<Long> =
        apiClient.api().listFavoriteGroupIds(javId).selectedGroupIds

    /** 全量替换某作品的收藏夹归属（勾选保存语义） */
    suspend fun replaceGroups(javId: Long, groupIds: List<Long>) =
        apiClient.api().replaceFavoriteGroups(javId, ReplaceFavoriteGroupsRequest(groupIds))
}
