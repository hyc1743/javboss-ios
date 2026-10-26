import Foundation

/// 服务端 API 方法封装（对应上游 JavBoss internal/api 全部核心路由）。
final class Repository {
    let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    // MARK: 认证

    func authStatus() async throws -> AuthStatusResponse { try await api.get("auth/status") }
    func login(serverUrl: String, password: String) async throws {
        api.cookieJar.clear()
        api.session.saveServerUrl(serverUrl)
        let res: LoginResponse = try await api.post("auth/login", body: LoginRequest(password: password))
        if !res.authenticated { throw ApiError.network("登录失败") }
    }
    func changePassword(current: String, new: String) async throws {
        try await api.putVoid("auth/password", body: ChangePasswordRequest(currentPassword: current, newPassword: new))
    }

    // MARK: 视频

    func listVideos(limit: Int = 50, offset: Int = 0, search: String = "", sort: String = "",
                    tags: [Int64] = [], hideJav: Bool = false, seed: Int64? = nil) async throws -> VideoListResponse {
        var query = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        if !search.isEmpty { query.append(URLQueryItem(name: "search", value: search)) }
        if !sort.isEmpty { query.append(URLQueryItem(name: "sort", value: sort)) }
        if !tags.isEmpty { query.append(URLQueryItem(name: "tags", value: tags.map(String.init).joined(separator: ","))) }
        if hideJav { query.append(URLQueryItem(name: "hide_jav", value: "true")) }
        if let seed { query.append(URLQueryItem(name: "seed", value: String(seed))) }
        return try await api.get("videos", query: query)
    }

    func getVideo(id: Int64) async throws -> Video { try await api.get("videos/\(id)") }
    func getStreams(id: Int64, locationId: Int64? = nil) async throws -> PlaybackInfo {
        var query: [URLQueryItem] = []
        if let locationId, locationId > 0 {
            query.append(URLQueryItem(name: "location_id", value: String(locationId)))
        }
        return try await api.get("videos/\(id)/streams", query: query)
    }

    func resolvePlayUrls(id: Int64, locationId: Int64? = nil) async throws -> [String] {
        let streams = try await getStreams(id: id, locationId: locationId)
        var direct: [String] = []
        var hlsUrls: [String] = []
        let directSrc = streams.sources.first { $0.kind == "direct" }?.src ?? "videos/\(id)/stream"
        if let abs = api.absoluteUrl(directSrc) { direct.append(abs) }
        for source in streams.sources where source.kind == "hls" {
            if let abs = api.absoluteUrl(source.src) { hlsUrls.append(abs) }
        }
        return streams.preferredKind == "hls" ? hlsUrls + direct : direct + hlsUrls
    }

    func reportPlay(id: Int64) async { try? await api.postVoid("videos/\(id)/play") }

    func listScreenshots(videoId: Int64) async throws -> [VideoScreenshotInfo] {
        let res: ScreenshotListResponse = try await api.get("videos/\(videoId)/screenshots")
        return res.items
    }

    func createScreenshot(videoId: Int64, second: Double) async throws -> VideoScreenshotInfo {
        try await api.post("videos/\(videoId)/screenshots", body: VideoScreenshotCreateRequest(second: second))
    }

    func setVideoCover(videoId: Int64, screenshotName: String) async throws {
        try await api.putVoid("videos/\(videoId)/cover", body: VideoCoverRequest(screenshotName: screenshotName))
    }

    func resetVideoCover(videoId: Int64) async throws { try await api.deleteVoid("videos/\(videoId)/cover") }
    func deleteVideoScreenshot(videoId: Int64, name: String) async throws {
        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return }
        try await api.deleteVoid("videos/\(videoId)/screenshots/\(encoded)")
    }

    // MARK: JAV 刮削（视频关联作品）

    func videoJavScrapeSettings(videoId: Int64, mode: String, code: String) async throws {
        try await api.patchVoid("videos/\(videoId)/jav-scrape", body: VideoJavScrapeSettingsRequest(mode: mode, code: code))
    }

    func videoJavPossibleCodes(videoId: Int64) async throws -> VideoJavPossibleCodesResponse {
        try await api.get("videos/\(videoId)/jav-scrape/possible-codes")
    }

    func videoJavLookup(videoId: Int64, provider: String, code: String) async throws -> VideoJavScrapeInfoResponse {
        var query = [URLQueryItem(name: "code", value: code)]
        if !provider.isEmpty { query.append(URLQueryItem(name: "provider", value: provider)) }
        return try await api.get("videos/\(videoId)/jav-scrape/lookup", query: query)
    }

    func videoJavLink(videoId: Int64, locationId: Int64, code: String) async throws {
        try await api.postVoid("videos/\(videoId)/jav-scrape/link", body: VideoJavExistingLinkRequest(locationId: locationId, code: code))
    }

    func videoJavManual(videoId: Int64, request: VideoJavManualScrapeRequest) async throws {
        try await api.postVoid("videos/\(videoId)/jav-scrape/manual", body: request)
    }

    func renameVideoLocation(videoId: Int64, locationId: Int64, filename: String) async throws {
        try await api.patchVoid("videos/\(videoId)/locations/\(locationId)", body: RenameVideoLocationRequest(filename: filename))
    }

    func deleteVideoLocation(videoId: Int64, locationId: Int64) async throws {
        try await api.deleteVoid("videos/\(videoId)/locations/\(locationId)")
    }

    // MARK: 观看时长

    func watchedTime(videoIds: [Int64] = [], javIds: [Int64] = []) async throws -> WatchedTimeSnapshot {
        var query: [URLQueryItem] = []
        if !videoIds.isEmpty { query.append(URLQueryItem(name: "video_ids", value: videoIds.map(String.init).joined(separator: ","))) }
        if !javIds.isEmpty { query.append(URLQueryItem(name: "jav_ids", value: javIds.map(String.init).joined(separator: ","))) }
        return try await api.get("videos/watched-time", query: query)
    }

    func watchedTimeEventStream() -> AsyncStream<WatchedTimeSnapshot> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    do {
                        try await api.consumeSSE("videos/watched-time/events") { data in
                            if let snapshot = try? JSONDecoder().decode(WatchedTimeSnapshot.self, from: data) {
                                continuation.yield(snapshot)
                            }
                        }
                    } catch ApiError.authExpired {
                        break
                    } catch {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func createPlaybackSession(videoId: Int64, locationId: Int64 = 0) async throws -> String {
        let res: PlaybackSessionResponse = try await api.post("videos/\(videoId)/playback-sessions",
                                                               body: PlaybackSessionRequest(locationId: locationId))
        return res.sessionId
    }

    func reportPlaybackSession(videoId: Int64, sessionId: String, watchedMs: Int64) async throws {
        try await api.putVoid("videos/\(videoId)/playback-sessions/\(sessionId)", body: WatchedMsRequest(watchedMs: watchedMs))
    }

    // MARK: JAV 作品

    func searchJav(limit: Int = 50, offset: Int = 0, search: String = "", idolIds: [Int64] = [],
                   tagIds: [Int64] = [], studioId: Int64? = nil, seriesId: Int64? = nil,
                   prefix: String = "", solo: Bool = false, sort: String = "", seed: Int64? = nil,
                   favoriteGroupId: Int64? = nil, favoriteRatingMin: Double? = nil, favoriteRatingMax: Double? = nil) async throws -> JavListResponse {
        var query = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        if !search.isEmpty { query.append(URLQueryItem(name: "search", value: search)) }
        if !idolIds.isEmpty { query.append(URLQueryItem(name: "idol_ids", value: idolIds.map(String.init).joined(separator: ","))) }
        if !tagIds.isEmpty { query.append(URLQueryItem(name: "tag_ids", value: tagIds.map(String.init).joined(separator: ","))) }
        if let studioId { query.append(URLQueryItem(name: "studio_id", value: String(studioId))) }
        if let seriesId { query.append(URLQueryItem(name: "series_id", value: String(seriesId))) }
        if !prefix.isEmpty { query.append(URLQueryItem(name: "prefix", value: prefix)) }
        if solo { query.append(URLQueryItem(name: "solo", value: "1")) }
        if !sort.isEmpty { query.append(URLQueryItem(name: "sort", value: sort)) }
        if let seed { query.append(URLQueryItem(name: "seed", value: String(seed))) }
        if let favoriteGroupId { query.append(URLQueryItem(name: "favorite_group_id", value: String(favoriteGroupId))) }
        if let favoriteRatingMin { query.append(URLQueryItem(name: "favorite_rating_min", value: String(favoriteRatingMin))) }
        if let favoriteRatingMax { query.append(URLQueryItem(name: "favorite_rating_max", value: String(favoriteRatingMax))) }
        return try await api.get("jav", query: query)
    }

    func getJavItem(id: Int64) async throws -> Jav { try await api.get("jav/items/\(id)") }
    func updateJavItem(id: Int64, request: JavItemUpdateRequest) async throws -> Jav {
        try await api.put("jav/items/\(id)", body: request)
    }
    func deleteJavVideos(id: Int64) async throws { try await api.deleteVoid("jav/items/\(id)/videos") }

    func listJavPrefixes() async throws -> [JavPrefixSummary] { try await api.get("jav/prefixes") }
    func listJavTags() async throws -> [JavTag] { try await api.get("jav/tags") }
    func listJavTagCategories() async throws -> [JavTagCategory] { try await api.get("jav/tag-categories") }
    func createJavTag(name: String) async throws -> JavTag {
        try await api.post("jav/tags", body: NameRequest(name: name))
    }
    func createJavScrapedTag(name: String) async throws -> JavTag {
        try await api.post("jav/tags/scraped", body: NameRequest(name: name))
    }
    func renameJavTag(id: Int64, name: String) async throws {
        try await api.patchVoid("jav/tags/\(id)", body: NameRequest(name: name))
    }
    func deleteJavTag(id: Int64) async throws { try await api.deleteVoid("jav/tags/\(id)") }
    func batchDeleteJavTags(ids: [Int64]) async throws {
        try await api.postVoid("jav/tags/batch_delete", body: JavTagsBatchDeleteRequest(tagIds: ids))
    }
    func createJavTagCategory(name: String) async throws -> JavTagCategory {
        try await api.post("jav/tag-categories", body: NameRequest(name: name))
    }
    func renameJavTagCategory(id: Int64, name: String) async throws {
        try await api.patchVoid("jav/tag-categories/\(id)", body: NameRequest(name: name))
    }
    func deleteJavTagCategory(id: Int64) async throws { try await api.deleteVoid("jav/tag-categories/\(id)") }
    func reorderJavTagCategories(ids: [Int64]) async throws {
        try await api.putVoid("jav/tag-categories/order", body: TagCategoryOrderRequest(categoryIds: ids))
    }
    func assignJavTagsCategory(tagIds: [Int64], categoryId: Int64?) async throws {
        try await api.postVoid("jav/tags/category", body: JavTagCategoryRequest(tagIds: tagIds, categoryId: categoryId))
    }
    func replaceJavTags(javIds: [Int64], tagIds: [Int64]) async throws {
        try await api.postVoid("jav/tags/replace", body: JavTagsReplaceRequest(javIds: javIds, tagIds: tagIds))
    }
    func organizeJavTags() async throws {
        try await api.postVoid("jav/tags/organize")
    }

    func listJavFilterOptions(search: String = "", idolIds: [Int64] = [], tagIds: [Int64] = [],
                              studioId: Int64? = nil, seriesId: Int64? = nil, prefix: String = "",
                              solo: Bool = false, favoriteGroupId: Int64? = nil,
                              optionSearches: [String: String] = [:]) async throws -> JavFilterOptions {
        var query: [URLQueryItem] = []
        if !search.isEmpty { query.append(URLQueryItem(name: "search", value: search)) }
        if !idolIds.isEmpty { query.append(URLQueryItem(name: "idol_ids", value: idolIds.map(String.init).joined(separator: ","))) }
        if !tagIds.isEmpty { query.append(URLQueryItem(name: "tag_ids", value: tagIds.map(String.init).joined(separator: ","))) }
        if let studioId { query.append(URLQueryItem(name: "studio_id", value: String(studioId))) }
        if let seriesId { query.append(URLQueryItem(name: "series_id", value: String(seriesId))) }
        if !prefix.isEmpty { query.append(URLQueryItem(name: "prefix", value: prefix)) }
        if solo { query.append(URLQueryItem(name: "solo", value: "1")) }
        if let favoriteGroupId { query.append(URLQueryItem(name: "favorite_group_id", value: String(favoriteGroupId))) }
        for (key, value) in optionSearches where !value.isEmpty {
            query.append(URLQueryItem(name: key, value: value))
        }
        return try await api.get("jav/filter-options", query: query)
    }

    func resolveJavSampleImages(id: Int64) async throws -> [String] {
        let res: SampleImagesResponse = try await api.post("jav/items/\(id)/sample-images")
        return res.items ?? []
    }

    func javdbUrl(code: String) async throws -> String {
        let res: UrlResponse = try await api.get("jav/javdb-url", query: [URLQueryItem(name: "code", value: code)])
        return res.url
    }

    func avsoxUrl(code: String) async throws -> String {
        let res: UrlResponse = try await api.get("jav/avsox-redirect", query: [URLQueryItem(name: "code", value: code)])
        return res.url
    }

    func translateJavTitle(id: Int64) async throws { try await api.postVoid("jav/items/\(id)/title-translation") }
    func translateJavTitles(ids: [Int64]) async throws {
        try await api.postVoid("jav/title-translation/items", body: ["ids": ids])
    }

    // MARK: 女优 / 片商 / 系列

    func listIdols(limit: Int = 50, offset: Int = 0, search: String = "", sort: String = "",
                   favoriteGroupId: Int64? = nil,
                   ranges: [String: (Int?, Int?)] = [:]) async throws -> IdolListResponse {
        var query = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        if !search.isEmpty { query.append(URLQueryItem(name: "search", value: search)) }
        if !sort.isEmpty { query.append(URLQueryItem(name: "sort", value: sort)) }
        if let favoriteGroupId { query.append(URLQueryItem(name: "favorite_group_id", value: String(favoriteGroupId))) }
        for (key, range) in ranges {
            if let min = range.0 { query.append(URLQueryItem(name: "\(key)_min", value: String(min))) }
            if let max = range.1 { query.append(URLQueryItem(name: "\(key)_max", value: String(max))) }
        }
        let res: IdolListResponse = try await api.get("jav/idols", query: query)
        return res
    }

    func createIdol(name: String) async throws -> JavIdolSummary {
        try await api.post("jav/idols", body: JavIdolCreateRequest(name: name))
    }
    func getIdol(id: Int64) async throws -> JavIdolSummary { try await api.get("jav/idols/\(id)") }
    func updateIdol(id: Int64, request: JavIdolUpdateRequest) async throws -> JavIdolSummary {
        try await api.patch("jav/idols/\(id)", body: request)
    }
    func mergeIdols(canonicalId: Int64, mergeIds: [Int64]) async throws {
        try await api.postVoid("jav/idols/merge", body: MergeRequest(canonicalId: canonicalId, mergeIds: mergeIds))
    }
    func idolCoverOptions(id: Int64) async throws -> [JavIdolCoverOption] {
        let res: IdolCoverOptionsResponse = try await api.get("jav/idols/\(id)/cover-options")
        return res.items
    }
    func updateIdolCover(id: Int64, javId: Int64, cropLeft: Double) async throws {
        try await api.putVoid("jav/idols/\(id)/cover", body: JavIdolCoverRequest(javId: javId, cropLeft: cropLeft))
    }
    func idolJavdbUrl(code: String, name: String) async throws -> String {
        let res: UrlResponse = try await api.get("jav/idols/javdb-url", query: [
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "name", value: name),
        ])
        return res.url
    }

    func listStudios(limit: Int = 50, offset: Int = 0, search: String = "",
                     favoriteGroupId: Int64? = nil) async throws -> StudioListResponse {
        var query = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        if !search.isEmpty { query.append(URLQueryItem(name: "search", value: search)) }
        if let favoriteGroupId { query.append(URLQueryItem(name: "favorite_group_id", value: String(favoriteGroupId))) }
        let res: StudioListResponse = try await api.get("jav/studios", query: query)
        return res
    }
    func getStudio(id: Int64) async throws -> JavStudioSummary { try await api.get("jav/studios/\(id)") }
    func updateStudio(id: Int64, request: JavStudioUpdateRequest) async throws -> JavStudioSummary {
        try await api.patch("jav/studios/\(id)", body: request)
    }
    func mergeStudios(canonicalId: Int64, mergeIds: [Int64]) async throws {
        try await api.postVoid("jav/studios/merge", body: MergeRequest(canonicalId: canonicalId, mergeIds: mergeIds))
    }
    func studioJavdbUrl(studioId: Int64) async throws -> String {
        let res: UrlResponse = try await api.get("jav/studios/javdb-url", query: [URLQueryItem(name: "studio_id", value: String(studioId))])
        return res.url
    }

    func listSeries(limit: Int = 50, offset: Int = 0, search: String = "",
                    favoriteGroupId: Int64? = nil) async throws -> SeriesListResponse {
        var query = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        if !search.isEmpty { query.append(URLQueryItem(name: "search", value: search)) }
        if let favoriteGroupId { query.append(URLQueryItem(name: "favorite_group_id", value: String(favoriteGroupId))) }
        let res: SeriesListResponse = try await api.get("jav/series", query: query)
        return res
    }
    func getSeries(id: Int64) async throws -> JavSeriesSummary { try await api.get("jav/series/\(id)") }
    func updateSeries(id: Int64, request: JavSeriesUpdateRequest) async throws -> JavSeriesSummary {
        try await api.patch("jav/series/\(id)", body: request)
    }
    func translateSeriesName(id: Int64) async throws { try await api.postVoid("jav/series/\(id)/name-translation") }
    func seriesJavdbUrl(seriesId: Int64) async throws -> String {
        let res: UrlResponse = try await api.get("jav/series/javdb-url", query: [URLQueryItem(name: "series_id", value: String(seriesId))])
        return res.url
    }

    // MARK: 收藏夹（jav / idol / studio / series）

    func favoriteEntityPath(_ entity: FavoriteEntity) -> String {
        switch entity {
        case .jav: return "jav/jav-favorite-groups"
        case .idol: return "jav/idol-favorite-groups"
        case .studio: return "jav/studio-favorite-groups"
        case .series: return "jav/series-favorite-groups"
        }
    }

    func listFavoriteGroups(_ entity: FavoriteEntity) async throws -> [FavoriteGroupSummary] {
        let res: FavoriteGroupListResponse = try await api.get(favoriteEntityPath(entity))
        return res.items
    }

    func createFavoriteGroup(_ entity: FavoriteEntity, name: String) async throws -> FavoriteGroupSummary {
        try await api.post(favoriteEntityPath(entity), body: NameRequest(name: name))
    }

    func renameFavoriteGroup(_ entity: FavoriteEntity, id: Int64, name: String) async throws {
        try await api.patchVoid("\(favoriteEntityPath(entity))/\(id)", body: NameRequest(name: name))
    }

    func deleteFavoriteGroup(_ entity: FavoriteEntity, id: Int64) async throws {
        try await api.deleteVoid("\(favoriteEntityPath(entity))/\(id)")
    }

    func reorderFavoriteGroups(_ entity: FavoriteEntity, ids: [Int64]) async throws {
        try await api.putVoid("\(favoriteEntityPath(entity))/order", body: FavoriteGroupOrderRequest(groupIds: ids))
    }

    func listFavoriteGroupItems(_ entity: FavoriteEntity, id: Int64) async throws -> [FavoriteItemSummary] {
        let res: FavoriteItemListResponse = try await api.get("\(favoriteEntityPath(entity))/\(id)/items")
        return res.items
    }

    func removeFavoriteGroupItems(_ entity: FavoriteEntity, id: Int64, entityIds: [Int64]) async throws {
        try await api.postVoid("\(favoriteEntityPath(entity))/\(id)/items/remove", body: EntityIdsRequest(entityIds: entityIds))
    }

    func reorderFavoriteGroupItems(_ entity: FavoriteEntity, id: Int64, entityIds: [Int64]) async throws {
        try await api.putVoid("\(favoriteEntityPath(entity))/\(id)/item-order", body: EntityIdsRequest(entityIds: entityIds))
    }

    func selectedFavoriteGroupIds(_ entity: FavoriteEntity, itemId: Int64) async throws -> [Int64] {
        let path: String
        switch entity {
        case .jav: path = "jav/items/\(itemId)/favorite-groups"
        case .idol: path = "jav/idols/\(itemId)/favorite-groups"
        case .studio: path = "jav/studios/\(itemId)/favorite-groups"
        case .series: path = "jav/series/\(itemId)/favorite-groups"
        }
        let res: SelectedFavoriteGroupsResponse = try await api.get(path)
        return res.selectedGroupIds
    }

    func replaceFavoriteGroups(_ entity: FavoriteEntity, itemId: Int64, groupIds: [Int64]) async throws {
        let path: String
        switch entity {
        case .jav: path = "jav/items/\(itemId)/favorite-groups"
        case .idol: path = "jav/idols/\(itemId)/favorite-groups"
        case .studio: path = "jav/studios/\(itemId)/favorite-groups"
        case .series: path = "jav/series/\(itemId)/favorite-groups"
        }
        try await api.putVoid(path, body: GroupIdsRequest(groupIds: groupIds))
    }

    func addJavsToFavoriteGroups(javIds: [Int64], groupIds: [Int64]) async throws {
        try await api.postVoid("jav/items/favorite-groups/add", body: AddJavsToFavoriteGroupsRequest(javIds: javIds, groupIds: groupIds))
    }

    // MARK: 视频标签

    func listVideoTags() async throws -> [VideoTagCount] { try await api.get("tags") }
    func listVideoTagCategories() async throws -> [TagCategory] { try await api.get("tags/categories") }
    func createVideoTag(name: String) async throws -> VideoTagCount {
        try await api.post("tags", body: NameRequest(name: name))
    }
    func renameVideoTag(id: Int64, name: String) async throws {
        try await api.patchVoid("tags/\(id)", body: NameRequest(name: name))
    }
    func deleteVideoTag(id: Int64) async throws { try await api.deleteVoid("tags/\(id)") }
    func batchDeleteVideoTags(ids: [Int64]) async throws {
        try await api.postVoid("tags/batch_delete", body: TagIdsRequest(tagIds: ids))
    }
    func createVideoTagCategory(name: String) async throws -> TagCategory {
        try await api.post("tags/categories", body: NameRequest(name: name))
    }
    func renameVideoTagCategory(id: Int64, name: String) async throws {
        try await api.patchVoid("tags/categories/\(id)", body: NameRequest(name: name))
    }
    func deleteVideoTagCategory(id: Int64) async throws { try await api.deleteVoid("tags/categories/\(id)") }
    func reorderVideoTagCategories(ids: [Int64]) async throws {
        try await api.putVoid("tags/categories/order", body: TagCategoryOrderRequest(categoryIds: ids))
    }
    func assignVideoTagsCategory(tagIds: [Int64], categoryId: Int64?) async throws {
        try await api.postVoid("tags/category", body: JavTagCategoryRequest(tagIds: tagIds, categoryId: categoryId))
    }
    func addVideoTags(videoIds: [Int64], tagId: Int64) async throws {
        try await api.postVoid("videos/tags/add", body: VideoTagAssignRequest(videoIds: videoIds, tagId: tagId))
    }
    func removeVideoTags(videoIds: [Int64], tagId: Int64) async throws {
        try await api.postVoid("videos/tags/remove", body: VideoTagAssignRequest(videoIds: videoIds, tagId: tagId))
    }
    func replaceVideoTags(videoIds: [Int64], tagIds: [Int64]) async throws {
        try await api.postVoid("videos/tags/replace", body: VideoTagsReplaceRequest(videoIds: videoIds, tagIds: tagIds))
    }

    // MARK: 目录

    func listDirectories() async throws -> [Directory] { try await api.get("directories") }
    func createDirectory(path: String) async throws -> Directory {
        try await api.post("directories", body: DirectoryCreateRequest(path: path))
    }
    func browseDirectories(path: String) async throws -> DirectoryBrowseResponse {
        try await api.get("directories/browse", query: [URLQueryItem(name: "path", value: path)])
    }
    func scanDirectory(id: Int64) async throws { try await api.postVoid("directories/\(id)/scan") }
    func processDirectory(id: Int64) async throws { try await api.postVoid("directories/\(id)/process") }
    func updateDirectory(id: Int64, request: DirectoryUpdateRequest) async throws {
        try await api.patchVoid("directories/\(id)", body: request)
    }

    // MARK: 下载

    func downloaderSettings() async throws -> DownloaderSettings { try await api.get("downloader/settings") }
    func updateDownloaderSettings(request: DownloaderSettingsRequest) async throws {
        try await api.putVoid("downloader/settings", body: request)
    }
    func updateCloudDrive2Settings(request: CloudDrive2SettingsRequest) async throws {
        try await api.putVoid("downloader/clouddrive2", body: request)
    }
    func cloudDrive2Token() async throws -> String {
        let res: CloudDrive2TokenResponse = try await api.get("downloader/clouddrive2/token")
        return res.token ?? ""
    }
    func testCloudDrive2() async throws -> CloudDrive2TestResponse {
        try await api.post("downloader/clouddrive2/test")
    }
    func listDownloadJobs(limit: Int = 50, offset: Int = 0) async throws -> DownloadJobPage {
        try await api.get("downloads", query: [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ])
    }
    func createDownloadJob(magnetUrl: String) async throws {
        try await api.postVoid("downloads", body: CreateDownloadRequest(magnetUrl: magnetUrl))
    }
    func retryDownloadJob(id: Int64) async throws { try await api.postVoid("downloads/\(id)/retry") }
    func cancelDownloadJob(id: Int64) async throws { try await api.postVoid("downloads/\(id)/cancel") }
    func revealDownloadJob(id: Int64) async throws { try await api.postVoid("downloads/\(id)/reveal") }
    func deleteDownloadJob(id: Int64) async throws { try await api.deleteVoid("downloads/\(id)") }

    // MARK: 扩展令牌

    func listExtensionTokens() async throws -> [ExtensionToken] {
        let res: ExtensionTokenListResponse = try await api.get("auth/extension-tokens")
        return res.items
    }
    func createExtensionToken(name: String, expiresInDays: Int?) async throws -> ExtensionTokenCreateResponse {
        try await api.post("auth/extension-tokens", body: ExtensionTokenCreateRequest(name: name, expiresInDays: expiresInDays))
    }
    func rotateExtensionToken(id: UInt64) async throws -> ExtensionTokenCreateResponse {
        try await api.post("auth/extension-tokens/\(id)/rotate")
    }
    func deleteExtensionToken(id: UInt64) async throws {
        try await api.deleteVoid("auth/extension-tokens/\(id)")
    }

    // MARK: 系统 / 工具 / 配置

    func getTools() async throws -> ToolsResponse { try await api.get("tools") }
    func downloadFFmpeg() async throws -> ToolStatus { try await api.post("tools/ffmpeg/download") }
    func getResources() async throws -> ResourcesSnapshot { try await api.get("system/resources") }
    func listProviders() async throws -> [AvailabilityProvider] { try await api.get("jav/providers") }
    func checkProvider(_ provider: String) async throws -> AvailabilityResult {
        try await api.post("jav/providers/\(provider)/availability")
    }
    func getConfig() async throws -> [String: Any] {
        let data: Data = try await api.getRaw("config")
        let obj = try JSONSerialization.jsonObject(with: data)
        return (obj as? [String: Any]) ?? [:]
    }
    func updateConfig(allowLanAccess: Bool) async throws {
        try await api.patchVoid("config", body: ServerConfigUpdateRequest(allowLanAccess: allowLanAccess))
    }
}

enum FavoriteEntity: String, CaseIterable, Identifiable {
    case jav
    case idol
    case studio
    case series

    var id: String { rawValue }

    var label: String {
        switch self {
        case .jav: return "作品"
        case .idol: return "女优"
        case .studio: return "片商"
        case .series: return "系列"
        }
    }
}

extension APIClient {
    func getRaw(_ path: String, query: [URLQueryItem] = []) async throws -> Data {
        guard let url = apiUrl(path, query: query) else { throw ApiError.network("服务器地址无效") }
        let request = makeRequest(method: "GET", url: url)
        let (data, response) = try await urlSession.data(for: request)
        return try handleResponse(response, data: data)
    }
}
