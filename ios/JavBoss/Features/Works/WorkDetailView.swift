import SwiftUI

@MainActor
final class WorkDetailVM: ObservableObject {
    @Published var jav: Jav?
    @Published var loading = true
    @Published var errorMessage: String?
    @Published var busyLabel: String?
    @Published var sampleImages: [String] = []

    let javId: Int64

    init(javId: Int64) {
        self.javId = javId
    }

    func load() async {
        loading = true
        do {
            jav = try await Repository(api: AppState.shared.api).getJavItem(id: javId)
            sampleImages = jav?.sampleImages ?? []
        } catch let error as ApiError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }

    func clearError() { errorMessage = nil }

    func perform(_ label: String, _ action: @escaping () async throws -> Void) {
        busyLabel = label
        Task {
            defer { busyLabel = nil }
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

    func refreshSampleImages() {
        perform("抓取预览图") {
            let images = try await Repository(api: AppState.shared.api).resolveJavSampleImages(id: self.javId)
            self.sampleImages = images
        }
    }
}

struct WorkDetailView: View {
    @StateObject private var vm: WorkDetailVM
    @State private var showEdit = false
    @State private var showFavorite = false
    @State private var showRating = false
    @State private var showTags = false
    @State private var viewerIndex: Int?
    @State private var viewerTarget: SampleViewerTarget?
    @State private var showWebTarget: WebTarget?

    init(javId: Int64) {
        _vm = StateObject(wrappedValue: WorkDetailVM(javId: javId))
    }

    var body: some View {
        Group {
            if vm.loading && vm.jav == nil {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let jav = vm.jav {
                content(jav)
            } else {
                EmptyPlaceholder(icon: "exclamationmark.triangle", text: "作品不存在或加载失败")
            }
        }
        .background(Color(white: 0.09))
        .navigationTitle(vm.jav?.code ?? "作品详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showFavorite = true
                    } label: {
                        Label("收藏夹", systemImage: "heart")
                    }
                    Button {
                        showRating = true
                    } label: {
                        Label("喜爱度", systemImage: "star")
                    }
                    Button {
                        showTags = true
                    } label: {
                        Label("编辑标签", systemImage: "tag")
                    }
                    Button {
                        showEdit = true
                    } label: {
                        Label("编辑信息", systemImage: "square.and.pencil")
                    }
                    Button {
                        vm.perform("翻译标题") {
                            guard let id = vm.jav?.id else { return }
                            try await Repository(api: AppState.shared.api).translateJavTitle(id: id)
                        }
                    } label: {
                        Label("翻译标题", systemImage: "character.bubble")
                    }
                    Divider()
                    Button {
                        Task {
                            do {
                                guard let code = vm.jav?.code else { return }
                                let url = try await Repository(api: AppState.shared.api).javdbUrl(code: code)
                                showWebTarget = WebTarget(url: url)
                            } catch {
                                vm.errorMessage = error.localizedDescription
                            }
                        }
                    } label: {
                        Label("JavDB 页面", systemImage: "globe")
                    }
                    Button {
                        Task {
                            do {
                                guard let code = vm.jav?.code else { return }
                                let url = try await Repository(api: AppState.shared.api).avsoxUrl(code: code)
                                showWebTarget = WebTarget(url: url)
                            } catch {
                                vm.errorMessage = error.localizedDescription
                            }
                        }
                    } label: {
                        Label("Avsox 页面", systemImage: "globe")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task { await vm.load() }
        .errorAlert(vm.errorMessage) { vm.clearError() }
        .overlay {
            if vm.busyLabel != nil {
                ProgressView(vm.busyLabel ?? "处理中…")
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .sheet(isPresented: $showEdit) {
            WorkEditView(javId: vm.javId) { Task { await vm.load() } }
        }
        .sheet(isPresented: $showFavorite) {
            FavoritePickerSheet(entity: .jav, itemId: vm.javId, title: vm.jav?.code ?? "收藏夹") {
                Task { await vm.load() }
            }
        }
        .sheet(isPresented: $showRating) {
            RatingSheet(current: vm.jav?.favoriteRating ?? 0) { rating in
                vm.perform("保存喜爱度") {
                    try await Repository(api: AppState.shared.api).updateJavItem(
                        id: vm.javId, request: JavItemUpdateRequest(favoriteRating: rating))
                }
            }
        }
        .sheet(isPresented: $showTags) {
            JavTagsEditorView(javId: vm.javId) { Task { await vm.load() } }
        }
        .sheet(item: $showWebTarget) { target in
            WebViewer(url: target.url)
        }
        .fullScreenCover(item: $viewerTarget) { target in
            SampleImageViewer(javId: vm.javId, count: vm.sampleImages.count, index: target.index)
        }
    }

    private func content(_ jav: Jav) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 头部：封面 + 基础信息
                HStack(alignment: .top, spacing: 12) {
                    RemoteImage(url: URL(string: AppState.shared.api.javCoverUrl(code: jav.code) ?? ""),
                                contentMode: .fit)
                        .frame(width: 110, height: 156)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(jav.code)
                            .font(.title3.bold())
                            .foregroundStyle(.orange)
                        if let zh = jav.zhTitle, !zh.isEmpty, zh != jav.title {
                            Text(zh)
                                .font(.subheadline)
                        }
                        Text(jav.title)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                        HStack(spacing: 8) {
                            if let studio = jav.studio {
                                NavigationLink {
                                    StudioDetailView(studioId: studio.id)
                                } label: {
                                    Text(studio.name)
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                }
                            }
                            if let series = jav.series {
                                NavigationLink {
                                    SeriesDetailView(seriesId: series.id)
                                } label: {
                                    Text(series.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal)

                // 元数据
                HStack(spacing: 10) {
                    if let release = jav.releaseUnix, release > 0 {
                        MetaItem(icon: "calendar", text: Fmt.date(ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: TimeInterval(release)))))
                    }
                    if let duration = jav.durationMin, duration > 0 {
                        MetaItem(icon: "clock", text: "\(duration) min")
                    }
                    if let watched = jav.watchedMs, watched > 0 {
                        MetaItem(icon: "eye", text: "已看 \(Fmt.ms(watched))")
                    }
                    if let rating = jav.favoriteRating, rating > 0 {
                        MetaItem(icon: "star.fill", text: String(format: "%.1f", rating))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

                // 演员
                if let idols = jav.idols, !idols.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("演员")
                            .font(.subheadline.bold())
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(idols) { idol in
                                    NavigationLink {
                                        IdolDetailView(idolId: idol.id)
                                    } label: {
                                        VStack(spacing: 4) {
                                            RemoteImage(url: URL(string: AppState.shared.api.idolCoverUrl(id: idol.id) ?? ""))
                                                .frame(width: 64, height: 88)
                                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                            Text(idol.displayName)
                                                .font(.caption2)
                                                .lineLimit(1)
                                                .frame(width: 64)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                // 标签
                if let tags = jav.tags, !tags.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("标签")
                            .font(.subheadline.bold())
                        ChipFlowLayout(chips: tags.map(\.name))
                    }
                    .padding(.horizontal)
                }

                // 预览图
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("预览图（\(vm.sampleImages.count)）")
                            .font(.subheadline.bold())
                        Spacer()
                        Button("抓取") { vm.refreshSampleImages() }
                            .font(.caption)
                    }
                    if vm.sampleImages.isEmpty {
                        Text("暂无预览图，点「抓取」从数据源获取")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(vm.sampleImages.enumerated()), id: \.offset) { index, _ in
                                    Rectangle()
                                        .fill(Color(white: 0.15))
                                        .frame(width: 120, height: 80)
                                        .overlay {
                                            RemoteImage(url: URL(string: AppState.shared.api.javSampleImageUrl(javId: jav.id, index: index, variant: "thumbnail") ?? ""))
                                        }
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                        .onTapGesture {
                                            viewerTarget = SampleViewerTarget(index: index)
                                        }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)

                // 关联视频
                if let videos = jav.videos, !videos.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("关联视频（\(videos.count)）")
                            .font(.subheadline.bold())
                        ForEach(videos) { video in
                            NavigationLink {
                                VideoDetailView(videoId: video.id)
                            } label: {
                                HStack(spacing: 10) {
                                    Rectangle()
                                        .fill(Color(white: 0.15))
                                        .frame(width: 100, height: 56)
                                        .overlay {
                                            RemoteImage(url: URL(string: AppState.shared.api.videoThumbnailUrl(videoId: video.id) ?? ""))
                                        }
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(video.displayTitle)
                                            .font(.footnote)
                                            .lineLimit(2)
                                        HStack(spacing: 8) {
                                            Text(Fmt.duration(video.durationSec))
                                            Text(Fmt.bytes(video.size))
                                            if video.watchedMs > 0 {
                                                Text("已看 \(Fmt.ms(video.watchedMs))")
                                            }
                                        }
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "play.circle")
                                        .foregroundStyle(.orange)
                                }
                                .padding(8)
                                .background(Color(white: 0.14), in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }
}

struct WebTarget: Identifiable {
    let id = UUID()
    let url: String
}

struct SampleViewerTarget: Identifiable {
    let id = UUID()
    let index: Int
}

struct WebViewer: View {
    let url: String
    @Environment(\.dismiss) private var dismiss
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            Group {
                if let valid = URL(string: url) {
                    SafariWrapper(url: valid)
                } else {
                    Text("地址无效")
                }
            }
            .navigationTitle("外部页面")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

struct SampleImageViewer: View {
    let javId: Int64
    let count: Int
    let index: Int

    @Environment(\.dismiss) private var dismiss
    @State private var current = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $current) {
                ForEach(0..<max(count, 1), id: \.self) { i in
                    RemoteImage(url: URL(string: AppState.shared.api.javSampleImageUrl(javId: javId, index: i, variant: "detail") ?? ""),
                                contentMode: .fit)
                        .tag(i)
                }
            }
            .tabViewStyle(.page)
            .ignoresSafeArea()
            VStack {
                HStack {
                    Text("\(current + 1) / \(max(count, 1))")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.6), in: Capsule())
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
                }
                .padding()
                Spacer()
            }
        }
        .onAppear { current = index }
    }
}
