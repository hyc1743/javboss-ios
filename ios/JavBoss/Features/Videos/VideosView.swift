import SwiftUI

@MainActor
final class VideosViewModel: PagedListVM<Video> {
    var search = ""
    var sort = ""
    var tagIds: [Int64] = []
    var hideJav = false
    var seed: Int64?
    var allTags: [VideoTagCount] = []

    func loadTags() async {
        allTags = (try? await Repository(api: AppState.shared.api).listVideoTags()) ?? []
    }

    override func fetchPage(offset: Int) async throws -> ([Video], Int) {
        let res = try await Repository(api: AppState.shared.api).listVideos(
            limit: pageSize, offset: offset, search: search, sort: sort,
            tags: tagIds, hideJav: hideJav, seed: seed)
        return (res.items, res.total)
    }
}

struct VideosView: View {
    @StateObject private var vm = VideosViewModel()
    @State private var searchText = ""
    @State private var showFilter = false

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                SearchField(placeholder: "搜索文件名 / 番号 / 标题", text: $searchText) {
                    vm.search = searchText
                    Task { await vm.refresh() }
                }
                .padding(.horizontal)

                if vm.loading && vm.items.isEmpty {
                    Spacer()
                    ProgressView("加载中…")
                    Spacer()
                } else if vm.items.isEmpty {
                    EmptyPlaceholder(icon: "play.rectangle", text: "没有视频")
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(vm.items) { video in
                                NavigationLink {
                                    VideoDetailView(videoId: video.id)
                                } label: {
                                    VideoCard(video: video)
                                }
                                .buttonStyle(.plain)
                                .task {
                                    await vm.loadMoreIfNeeded(current: video)
                                }
                            }
                        }
                        .padding(.horizontal)
                        if vm.loadingMore {
                            ProgressView().padding(8)
                        }
                    }
                    .refreshable {
                        await vm.refresh()
                    }
                }
            }
            .background(Color(white: 0.09))
            .navigationTitle("视频")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        NotificationCenter.default.post(name: .logoutRequested, object: nil)
                    } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 14) {
                        Button {
                            vm.seed = Int64.random(in: 1...Int64.max)
                            Task { await vm.refresh() }
                        } label: {
                            Image(systemName: "shuffle")
                        }
                        Menu {
                            Picker("排序", selection: Binding(
                                get: { vm.sort },
                                set: { vm.sort = $0; Task { await vm.refresh() } }
                            )) {
                                Text("默认").tag("")
                                Text("时长最长").tag("watched")
                                Text("时长最短").tag("watched_asc")
                                Text("最近").tag("recent")
                                Text("播放最多").tag("play_count")
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                        }
                        Button {
                            showFilter = true
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                        }
                    }
                }
            }
            .sheet(isPresented: $showFilter) {
                VideoFilterSheet(vm: vm)
            }
            .task {
                if vm.items.isEmpty {
                    await vm.refresh()
                }
                await vm.loadTags()
            }
            .errorAlert(vm.errorMessage) { vm.clearError() }
        }
    }
}

struct VideoCard: View {
    let video: Video

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                Rectangle()
                    .fill(Color(white: 0.15))
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .overlay {
                        RemoteImage(url: URL(string: AppState.shared.api.videoThumbnailUrl(videoId: video.id) ?? ""),
                                    contentMode: .fill)
                    }
                Text(Fmt.duration(video.durationSec))
                    .font(.caption2.monospacedDigit())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
                    .padding(5)
                if video.watchedMs > 0 {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .padding(5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(video.displayTitle)
                .font(.footnote)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Text(Fmt.bytes(video.size))
                Text("▶ \(Fmt.count(Int64(video.playCount)))")
                if video.watchedMs > 0 {
                    Text("已看 \(Fmt.ms(video.watchedMs))")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }
}

struct VideoFilterSheet: View {
    @ObservedObject var vm: VideosViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTags: Set<Int64> = []

    var body: some View {
        NavigationStack {
            List {
                Section("标签筛选") {
                    if vm.allTags.isEmpty {
                        Text("暂无视频标签")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(vm.allTags) { tag in
                            Button {
                                if selectedTags.contains(tag.id) {
                                    selectedTags.remove(tag.id)
                                } else {
                                    selectedTags.insert(tag.id)
                                }
                            } label: {
                                HStack {
                                    Text(tag.name)
                                    Spacer()
                                    Text(Fmt.count(tag.count))
                                        .foregroundStyle(.secondary)
                                    if selectedTags.contains(tag.id) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.orange)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
                Section {
                    Toggle("隐藏已关联作品", isOn: Binding(
                        get: { vm.hideJav },
                        set: { vm.hideJav = $0 }
                    ))
                }
            }
            .navigationTitle("筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") {
                        vm.tagIds = Array(selectedTags)
                        Task { await vm.refresh() }
                        dismiss()
                    }
                }
            }
            .onAppear {
                selectedTags = Set(vm.tagIds)
            }
        }
        .presentationDetents([.medium, .large])
    }
}
