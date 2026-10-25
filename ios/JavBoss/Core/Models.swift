import Foundation

// MARK: - 通用

struct AuthStatusResponse: Decodable { let authenticated: Bool }
struct LoginRequest: Encodable { let password: String }
struct LoginResponse: Decodable { let authenticated: Bool }
struct ChangePasswordRequest: Encodable { let currentPassword: String; let newPassword: String }
struct NameRequest: Encodable { let name: String }
struct TagIdsRequest: Encodable { let tagIds: [Int64] }
struct EntityIdsRequest: Encodable { let entityIds: [Int64] }
struct GroupIdsRequest: Encodable { let groupIds: [Int64] }
struct VideoIdsRequest: Encodable { let videoIds: [Int64] }
struct TagIdRequest: Encodable { let tagId: Int64 }
struct VideoTagAssignRequest: Encodable { let videoIds: [Int64]; let tagId: Int64 }
struct VideoTagsReplaceRequest: Encodable { let videoIds: [Int64]; let tagIds: [Int64] }
struct UrlResponse: Decodable { let url: String }

// MARK: - 视频

struct Video: Decodable, Identifiable {
    let id: Int64
    var locationId: Int64?
    var directoryId: Int64?
    var path: String?
    var filename: String
    var size: Int64
    var modifiedAt: String?
    var durationSec: Int64
    var playCount: Int64
    var watchedMs: Int64
    var javScrapeOverride: String?
    var coverScreenshotName: String?
    var javId: Int64?
    var jav: Jav?
    var tags: [VideoTag]?
    var locations: [VideoLocation]?

    var displayTitle: String {
        if let jav = jav, !jav.code.isEmpty {
            let title = jav.title
            return title.isEmpty ? jav.code : "\(jav.code) \(title)"
        }
        return filename.isEmpty ? "视频 #\(id)" : filename
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        locationId = try c.decodeIfPresent(Int64.self, forKey: .locationId)
        directoryId = try c.decodeIfPresent(Int64.self, forKey: .directoryId)
        path = try c.decodeIfPresent(String.self, forKey: .path)
        filename = try c.decodeIfPresent(String.self, forKey: .filename) ?? ""
        size = try c.decodeIfPresent(Int64.self, forKey: .size) ?? 0
        modifiedAt = try c.decodeIfPresent(String.self, forKey: .modifiedAt)
        durationSec = try c.decodeIfPresent(Int64.self, forKey: .durationSec) ?? 0
        playCount = try c.decodeIfPresent(Int64.self, forKey: .playCount) ?? 0
        watchedMs = try c.decodeIfPresent(Int64.self, forKey: .watchedMs) ?? 0
        javScrapeOverride = try c.decodeIfPresent(String.self, forKey: .javScrapeOverride)
        coverScreenshotName = try c.decodeIfPresent(String.self, forKey: .coverScreenshotName)
        javId = try c.decodeIfPresent(Int64.self, forKey: .javId)
        jav = try c.decodeIfPresent(Jav.self, forKey: .jav)
        tags = try c.decodeIfPresent([VideoTag].self, forKey: .tags)
        locations = try c.decodeIfPresent([VideoLocation].self, forKey: .locations)
    }

    enum CodingKeys: String, CodingKey {
        case id, locationId, directoryId, path, filename, size, modifiedAt
        case durationSec, playCount, watchedMs, javScrapeOverride, coverScreenshotName
        case javId, jav, tags, locations
    }
}

struct VideoLocation: Decodable, Identifiable {
    let id: Int64
    var videoId: Int64?
    var directoryId: Int64?
    var javId: Int64?
    var path: String?
    var filename: String?
    var size: Int64?
    var modifiedAt: String?
}

struct VideoTag: Decodable, Identifiable {
    let id: Int64
    var name: String
    var categoryId: Int64?
    var category: TagCategory?
}

struct VideoListResponse: Decodable { let items: [Video]; let total: Int }

// MARK: - 播放

struct PlaybackInfo: Decodable {
    let videoId: Int64
    var locationId: Int64?
    var preferredKind: String?
    var sources: [PlaybackSource]
    var videoCodec: String?
    var audioCodec: String?
}

struct PlaybackSource: Decodable {
    var kind: String
    var src: String
    var mimeType: String?
    var label: String?
}

struct VideoScreenshotInfo: Decodable {
    var videoId: Int64?
    var name: String
    var url: String?
    var size: Int64?
    var modifiedAt: String?
    var isCover: Bool
}

struct ScreenshotListResponse: Decodable { let items: [VideoScreenshotInfo] }

struct VideoCoverRequest: Encodable { let screenshotName: String }

struct VideoJavScrapeSettingsRequest: Encodable { let mode: String; let code: String }
struct VideoJavPossibleCodesResponse: Decodable {
    let filename: String
    let possibleCodes: [String]
}
struct VideoJavScrapeInfoResponse: Decodable {
    var code: String
    var title: String
    var studio: String
    var series: String
    var releaseDate: String?
    var releaseUnix: Int64?
    var durationMin: Int?
    var tags: [String]
    var actors: [String]
    var coverUrl: String?
    var isUncensored: Bool?
}
struct VideoJavExistingLinkRequest: Encodable { let locationId: Int64; let code: String }
struct VideoJavManualScrapeRequest: Encodable {
    let locationId: Int64
    let code: String
    let title: String
    let studio: String
    let series: String
    let releaseDate: String
    let durationMin: Int?
    let tags: [String]
    let actors: [String]
    let coverUrl: String
    let isUncensored: Bool?
}
struct RenameVideoLocationRequest: Encodable { let filename: String }

// MARK: - 观看时长

struct WatchedTimeTotal: Decodable { let id: Int64; let watchedMs: Int64 }
struct WatchedTimeSnapshot: Decodable { var videos: [WatchedTimeTotal]; var javs: [WatchedTimeTotal] }
struct PlaybackSessionResponse: Decodable { let sessionId: String }
struct PlaybackSessionRequest: Encodable { let locationId: Int64 }
struct WatchedMsRequest: Encodable { let watchedMs: Int64 }

// MARK: - JAV 作品

struct Jav: Decodable, Identifiable {
    let id: Int64
    var code: String
    var title: String
    var zhTitle: String?
    var studioId: Int64?
    var studio: JavStudio?
    var seriesId: Int64?
    var series: JavSeriesSummary?
    var releaseUnix: Int64?
    var durationMin: Int?
    var isUncensored: Bool?
    var sampleImages: [String]?
    var favoriteRating: Double?
    var watchedMs: Int64?
    var coverCropPosition: Double?
    var tags: [JavTag]?
    var idols: [JavIdolSummary]?
    var videos: [Video]?
    var favoriteCount: Int64?
    var fetchedAt: String?

    var displayTitle: String {
        let base = title.isEmpty ? code : title
        if let zh = zhTitle, !zh.isEmpty { return zh }
        return base
    }
}

struct JavListResponse: Decodable { let items: [Jav]; let total: Int }
struct IdolListResponse: Decodable { let items: [JavIdolSummary]; let total: Int }
struct StudioListResponse: Decodable { let items: [JavStudioSummary]; let total: Int }
struct SeriesListResponse: Decodable { let items: [JavSeriesSummary]; let total: Int }

struct JavStudio: Decodable { let id: Int64; var name: String }

struct JavStudioSummary: Decodable, Identifiable {
    let id: Int64
    var name: String
    var aliases: [String]?
    var workCount: Int64?
    var sampleCode: String?
    var favoriteCount: Int64?
    var codePrefixes: [StudioCodePrefixSummary]?
    var series: [JavSeriesSummary]?
}

struct StudioCodePrefixSummary: Decodable { let prefix: String; let workCount: Int64 }

struct JavSeriesSummary: Decodable, Identifiable {
    let id: Int64
    var name: String
    var zhName: String?
    var studioId: Int64?
    var studioName: String?
    var workCount: Int64?
    var sampleCode: String?
    var favoriteCount: Int64?
}

struct JavIdolSummary: Decodable, Identifiable {
    let id: Int64
    var name: String
    var aliases: [String]?
    var romanName: String?
    var japaneseName: String?
    var chineseName: String?
    var heightCm: Int?
    var birthDate: String?
    var bust: Int?
    var waist: Int?
    var hips: Int?
    var cup: Int?
    var workCount: Int64?
    var coverJavId: Int64?
    var coverCode: String?
    var coverCropLeft: Double?
    var favoriteCount: Int64?

    var displayName: String {
        if let cn = chineseName, !cn.isEmpty { return cn }
        if let rn = romanName, !rn.isEmpty { return rn }
        return name
    }
}

struct JavTag: Decodable, Identifiable {
    let id: Int64
    var name: String
    var simplifiedName: String?
    var isUser: Bool?
    var provider: Int?
    var categoryId: Int64?
    var category: JavTagCategory?
    var categoryName: String?
    var count: Int64?

    enum CodingKeys: String, CodingKey {
        case id, name, simplifiedName, isUser, provider, categoryId
        case category = "category"
        case count
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        simplifiedName = try c.decodeIfPresent(String.self, forKey: .simplifiedName)
        isUser = try c.decodeIfPresent(Bool.self, forKey: .isUser)
        provider = try c.decodeIfPresent(Int.self, forKey: .provider)
        categoryId = try c.decodeIfPresent(Int64.self, forKey: .categoryId)
        if let cat = try? c.decodeIfPresent(JavTagCategory.self, forKey: .category) {
            category = cat
        }
        if let nameValue = try? c.decodeIfPresent(String.self, forKey: .category) {
            categoryName = nameValue
        }
        count = try c.decodeIfPresent(Int64.self, forKey: .count)
    }
}

struct JavTagCategory: Decodable, Identifiable {
    let id: Int64
    var name: String
    var sortOrder: Int?
}

struct TagCategory: Decodable, Identifiable {
    let id: Int64
    var name: String
    var sortOrder: Int?
}

struct VideoTagCount: Decodable, Identifiable {
    let id: Int64
    var name: String
    var count: Int64?
    var categoryId: Int64?
    var categoryName: String?

    enum CodingKeys: String, CodingKey {
        case id, name, count
        case categoryId = "category_id"
        case categoryName = "category"
    }
}

struct JavPrefixSummary: Decodable {
    var prefix: String
    var studioId: Int64?
    var studioName: String?
    var isUncensored: Bool?
    var workCount: Int64?
    var sampleCode: String?
}

struct JavFilterOptions: Decodable {
    var total: Int64?
    var soloCount: Int64?
    var prefixes: [JavPrefixSummary]?
    var idols: [JavIdolSummary]?
    var tags: [JavTag]?
    var studios: [JavStudioSummary]?
    var series: [JavSeriesSummary]?
}

struct JavItemUpdateRequest: Encodable {
    var title: String?
    var zhTitle: String?
    var coverUrl: String?
    var tagIds: [Int64]?
    var idolIds: [Int64]?
    var scrapedTagIds: [Int64]?
    var studioId: Int64?
    var seriesId: Int64?
    var releaseDate: String?
    var durationMin: Int?
    var favoriteRating: Double?
    var coverCropPosition: Double?
}

struct JavTagsReplaceRequest: Encodable { let javIds: [Int64]; let tagIds: [Int64] }
struct JavTagsAddRequest: Encodable { let javIds: [Int64]; let tagIds: [Int64] }
struct JavTagsRemoveRequest: Encodable { let javIds: [Int64]; let tagIds: [Int64] }
struct JavTagsBatchDeleteRequest: Encodable { let tagIds: [Int64] }
struct JavTagCategoryRequest: Encodable { let tagIds: [Int64]; let categoryId: Int64? }
struct TagCategoryOrderRequest: Encodable { let categoryIds: [Int64] }
struct JavIdolCreateRequest: Encodable { let name: String }
struct JavIdolUpdateRequest: Encodable {
    var name: String?
    var romanName: String?
    var japaneseName: String?
    var chineseName: String?
    var heightCm: Int?
    var birthDate: String?
    var bust: Int?
    var waist: Int?
    var hips: Int?
    var cup: Int?
    var aliases: [String]?
}
struct MergeRequest: Encodable { let canonicalId: Int64; let mergeIds: [Int64] }
struct JavStudioUpdateRequest: Encodable { var name: String?; var aliases: [String]? }
struct JavSeriesUpdateRequest: Encodable { var name: String?; var zhName: String? }
struct JavIdolCoverOption: Decodable, Identifiable {
    let id: Int64
    var code: String
    var title: String
    var zhTitle: String?
    var solo: Bool?
}
struct IdolCoverOptionsResponse: Decodable { let items: [JavIdolCoverOption] }
struct JavIdolCoverRequest: Encodable { let javId: Int64; let cropLeft: Double }
struct SampleImagesResponse: Decodable { let items: [String]? }

// MARK: - 收藏夹

struct FavoriteGroupSummary: Decodable, Identifiable {
    let id: Int64
    var entityType: String?
    var name: String
    var count: Int64?
    var sortOrder: Int?
}

struct FavoriteGroupListResponse: Decodable { let items: [FavoriteGroupSummary] }

struct FavoriteItemSummary: Decodable, Identifiable {
    let id: Int64
    var entityType: String?
    var name: String
    var romanName: String?
    var japaneseName: String?
    var chineseName: String?
    var code: String?
    var title: String?
    var zhTitle: String?
    var titleEn: String?
    var workCount: Int64?
    var sampleCode: String?
    var favoriteRating: Double?
    var coverCode: String?

    var displayName: String {
        if let cn = chineseName, !cn.isEmpty { return cn }
        if let rn = romanName, !rn.isEmpty { return rn }
        return name
    }

    var displaySubtitle: String {
        if let code = code, !code.isEmpty {
            let t = title ?? ""
            return t.isEmpty ? code : "\(code) \(t)"
        }
        if let sc = sampleCode, !sc.isEmpty { return sc }
        return ""
    }
}

struct FavoriteItemListResponse: Decodable { let items: [FavoriteItemSummary] }
struct SelectedFavoriteGroupsResponse: Decodable { let selectedGroupIds: [Int64] }
struct FavoriteGroupOrderRequest: Encodable { let groupIds: [Int64] }
struct AddJavsToFavoriteGroupsRequest: Encodable { let javIds: [Int64]; let groupIds: [Int64] }

// MARK: - 目录

struct Directory: Decodable, Identifiable {
    let id: Int64
    var path: String
    var enabled: Bool?
    var autoScanEnabled: Bool?
    var autoScanIntervalMinutes: Int?
    var scannedVideoCount: Int64?
    var scrapedVideoCount: Int64?
    var createdAt: String?
    var updatedAt: String?
    var isScanning: Bool?
    var workStatus: String?
    var scannedFileCount: Int64?
    var scanElapsedMs: Int64?
}

struct DirectoryCreateRequest: Encodable { let path: String }
struct DirectoryUpdateRequest: Encodable {
    var path: String?
    var isDelete: Bool?
    var enabled: Bool?
    var autoScanEnabled: Bool?
    var autoScanIntervalMinutes: Int?
}

struct BrowseEntry: Decodable { let name: String; let path: String }
struct DirectoryBrowseResponse: Decodable {
    var path: String
    var parent: String?
    var home: String?
    var roots: [BrowseEntry]
    var directories: [BrowseEntry]
}

// MARK: - 下载

struct DownloaderSettings: Decodable {
    var downloadDirectory: String
    var localConcurrency: Int
    var minVideoSizeMb: Int64
    var address: String
    var remoteFolder: String
    var tokenConfigured: Bool
}

struct DownloaderSettingsRequest: Encodable {
    var downloadDirectory: String?
    var localConcurrency: Int?
    var minVideoSizeMb: Int64?
}

struct CloudDrive2SettingsRequest: Encodable {
    var address: String?
    var apiToken: String?
    var clearApiToken: Bool?
    var remoteFolder: String?
}

struct CloudDrive2TokenResponse: Decodable { let token: String? }
struct CloudDrive2TestResponse: Decodable {
    var ok: Bool?
    var message: String?
    var success: Bool?
    var status: String?
    var remoteFolder: String?
}

struct DownloadJob: Decodable, Identifiable {
    let id: Int64
    var directoryPath: String?
    var provider: String?
    var infoHash: String?
    var magnetName: String?
    var remoteFolder: String?
    var remoteTaskId: String?
    var status: String?
    var bytesTotal: Int64?
    var bytesDownloaded: Int64?
    var errorMessage: String?
    var createdAt: String?
    var updatedAt: String?
    var completedAt: String?
}

struct DownloadJobPage: Decodable {
    var items: [DownloadJob]
    var total: Int64?
    var counts: DownloadJobCounts?
}
struct DownloadJobCounts: Decodable {
    var active: Int64?
    var completed: Int64?
    var failed: Int64?
}
struct CreateDownloadRequest: Encodable { let magnetUrl: String }

// MARK: - 扩展令牌

struct ExtensionToken: Decodable, Identifiable {
    let id: UInt64
    var name: String
    var token: String?
    var createdAt: String?
    var expiresAt: String?
    var lastUsedAt: String?
}
struct ExtensionTokenListResponse: Decodable { let items: [ExtensionToken] }
struct ExtensionTokenCreateResponse: Decodable { let item: ExtensionToken; let token: String }
struct ExtensionTokenCreateRequest: Encodable { let name: String; let expiresInDays: Int? }

// MARK: - 系统

struct ToolStatus: Decodable {
    var name: String?
    var version: String?
    var supported: Bool?
    var installed: Bool?
    var upgradeAvailable: Bool?
    var source: String?
    var downloading: Bool?
    var progress: Int?
    var downloadedBytes: Int64?
    var totalBytes: Int64?
    var path: String?
    var error: String?
}
struct ToolsResponse: Decodable { let ffmpeg: ToolStatus }

struct MemoryInfo: Decodable {
    var totalBytes: UInt64?
    var usedBytes: UInt64?
    var availableBytes: UInt64?
    var usedPercent: Double?
}
struct DiskInfo: Decodable {
    var path: String?
    var totalBytes: UInt64?
    var usedBytes: UInt64?
    var freeBytes: UInt64?
    var usedPercent: Double?
}
struct ProcessInfo: Decodable {
    var cpuPercent: Double?
    var rssBytes: UInt64?
    var readBytesPerSecond: Double?
    var writeBytesPerSecond: Double?
    var diskReadBytesPerSecond: Double?
    var diskWriteBytesPerSecond: Double?
    var goroutines: Int?
    var uptimeSeconds: Int64?
}
struct ResourcesSnapshot: Decodable {
    var sampledAt: String?
    var sampleSeconds: Double?
    var os: String?
    var logicalCpus: Int?
    var container: Bool?
    var process: ProcessInfo?
    var systemCpuPercent: Double?
    var systemMemory: MemoryInfo?
    var dataDisk: DiskInfo?
    var unavailable: [String]?
}

struct AvailabilityProvider: Decodable, Identifiable {
    var id: String
    var name: String?
    var domain: String?
    var sample: String?
    var lastResult: AvailabilityResult?
}
struct AvailabilityResult: Decodable {
    var provider: String?
    var status: String?
    var httpStatus: Int?
    var elapsedMs: Int64?
    var checkedAt: String?
}

// MARK: - 配置

struct ServerConfigUpdateRequest: Encodable {
    var allowLanAccess: Bool?
}
