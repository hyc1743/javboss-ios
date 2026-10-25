import SwiftUI

@MainActor
final class VideoDetailViewModel: ObservableObject {
    @Published var video: Video?
    @Published var screenshots: [VideoScreenshotInfo] = []
    @Published var loading = true
    @Published var errorMessage: String?
    @Published var busyAction: String?

    let videoId: Int64

    init(videoId: Int64) {
        self.videoId = videoId
    }

    func load() async {
        loading = true
        do {
            let repo = Repository(api: AppState.shared.api)
            video = try await repo.getVideo(id: videoId)
            screenshots = (try? await repo.listScreenshots(videoId: videoId)) ?? []
        } catch let error as ApiError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }

    func clearError() { errorMessage = nil }

    func perform(_ label: String, _ action: @escaping () async throws -> Void) {
        busyAction = label
        Task {
            defer { busyAction = nil }
            do {
                try await action()
                await load()
            } catch let error as ApiError {
                errorMessage = error.localizedDescription
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct VideoDetailView: View {
    @StateObject private var vm: VideoDetailViewModel
    @State private var showPlayer = false
    @State private var showTagsEditor = false
    @State private var showJavScrape = false
    @State private var showLocationEditor = false

    init(videoId: Int64) {
        _vm = StateObject(wrappedValue: VideoDetailViewModel(videoId: videoId))
    }

    var body: some View {
        Group {
            if vm.loading && vm.video == nil {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let video = vm.video {
                content(video)
            } else {
                EmptyPlaceholder(icon: "exclamationmark.triangle", text: "视频不存在或加载失败")
            }
        }
        .background(Color(white: 0.09))
        .navigationTitle(vm.video?.jav?.code ?? "视频详情")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .errorAlert(vm.errorMessage) { vm.clearError() }
        .fullScreenCover(isPresented: $showPlayer) {
            PlayerView(videoId: vm.videoId, watchedMs: vm.video?.watchedMs ?? 0)
        }
        .sheet(isPresented: $showTagsEditor) {
            VideoTagsEditorView(videoId: vm.videoId) {
                Task { await vm.load() }
            }
        }
        .sheet(isPresented: $showJavScrape) {
            VideoJavScrapeView(videoId: vm.videoId) {
                Task { await vm.load() }
            }
        }
        .sheet(isPresented: $showLocationEditor) {
            VideoLocationsView(videoId: vm.videoId) {
                Task { await vm.load() }
            }
        }
        .overlay {
            if vm.busyAction != nil {
                ProgressView(vm.busyAction ?? "处理中…")
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func content(_ video: Video) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 播放
                Button {
                    showPlayer = true
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("播放")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.95, green: 0.55, blue: 0.25))

                // 基本信息
                VStack(alignment: .leading, spacing: 6) {
                    Text(video.displayTitle)
                        .font(.headline)
                    if !video.filename.isEmpty && video.displayTitle != video.filename {
                        Text(video.filename)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 12) {
                        MetaItem(icon: "internaldrive", text: Fmt.bytes(video.size))
                        MetaItem(icon: "clock", text: Fmt.duration(video.durationSec))
                        MetaItem(icon: "play.circle", text: "\(video.playCount)")
                        if video.watchedMs > 0 {
                            MetaItem(icon: "eye", text: "已看 \(Fmt.ms(video.watchedMs))")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                // 关联作品
                if let jav = video.jav {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("关联作品")
                            .font(.subheadline.bold())
                        NavigationLink {
                            WorkDetailView(javId: jav.id)
                        } label: {
                            HStack(spacing: 10) {
                                RemoteImage(url: URL(string: AppState.shared.api.javCoverUrl(code: jav.code) ?? ""),
                                            contentMode: .fit)
                                    .frame(width: 56, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(jav.code)
                                        .font(.subheadline.bold())
                                    Text(jav.title)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(10)
                            .background(Color(white: 0.14), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                } else {
                    Button {
                        showJavScrape = true
                    } label: {
                        HStack {
                            Image(systemName: "link.badge.plus")
                            Text("关联 JAV 作品")
                                .font(.subheadline.bold())
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(12)
                        .background(Color(white: 0.14), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                }

                // 标签
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("标签")
                            .font(.subheadline.bold())
                        Spacer()
                        Button("编辑") { showTagsEditor = true }
                            .font(.caption)
                    }
                    if let tags = video.tags, !tags.isEmpty {
                        ChipFlowLayout(chips: tags.map(\.name))
                    } else {
                        Text("暂无标签")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)

                // 视频位置
                if let locations = video.locations, !locations.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("视频位置（\(locations.count)）")
                                .font(.subheadline.bold())
                            Spacer()
                            Button("管理") { showLocationEditor = true }
                                .font(.caption)
                        }
                        ForEach(locations) { loc in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(loc.filename ?? "位置 #\(loc.id)")
                                    .font(.caption)
                                    .lineLimit(2)
                                if let size = loc.size {
                                    Text(Fmt.bytes(size))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(white: 0.14), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(.horizontal)
                }

                // 截图
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("截图（\(vm.screenshots.count)）")
                            .font(.subheadline.bold())
                        Spacer()
                        Text("截图由服务端扫描生成")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if vm.screenshots.isEmpty {
                        Text("暂无截图")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ScreenshotGrid(screenshots: vm.screenshots, videoId: vm.videoId, vm: vm)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
    }
}

struct MetaItem: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text(text)
        }
    }
}

struct ScreenshotGrid: View {
    let screenshots: [VideoScreenshotInfo]
    let videoId: Int64
    @ObservedObject var vm: VideoDetailViewModel
    @State private var viewer: ScreenshotViewTarget?

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(screenshots, id: \.name) { shot in
                let url = URL(string: AppState.shared.api.videoScreenshotUrl(videoId: videoId, name: shot.name) ?? "")
                ZStack(alignment: .topTrailing) {
                    Rectangle()
                        .fill(Color(white: 0.15))
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .overlay {
                            RemoteImage(url: url)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .onTapGesture {
                            if let url { viewer = ScreenshotViewTarget(id: url.absoluteString, url: url) }
                        }
                    if shot.isCover {
                        Text("封面")
                            .font(.system(size: 9))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(.orange, in: Capsule())
                            .padding(3)
                    } else {
                        Menu {
                            Button("设为封面") {
                                vm.perform("设为封面") {
                                    try await Repository(api: AppState.shared.api)
                                        .setVideoCover(videoId: videoId, screenshotName: shot.name)
                                }
                            }
                            Button("删除", role: .destructive) {
                                vm.perform("删除截图") {
                                    try await Repository(api: AppState.shared.api)
                                        .deleteVideoScreenshot(videoId: videoId, name: shot.name)
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(3)
                                .background(.black.opacity(0.5), in: Circle())
                                .padding(3)
                        }
                    }
                }
            }
        }
        .fullScreenCover(item: $viewer) { target in
            ScreenshotViewer(url: target.url)
        }
    }
}

struct ScreenshotViewTarget: Identifiable {
    let id: String
    let url: URL
}

struct ScreenshotViewer: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            RemoteImage(url: url, contentMode: .fit)
                .ignoresSafeArea()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .padding()
            }
        }
    }
}
