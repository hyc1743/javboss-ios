import SwiftUI

// MARK: - 视频标签编辑

@MainActor
final class VideoTagsEditorVM: ObservableObject {
    @Published var allTags: [VideoTagCount] = []
    @Published var current: [VideoTag] = []
    @Published var selected: Set<Int64> = []
    @Published var loading = true
    @Published var errorMessage: String?

    let videoId: Int64

    init(videoId: Int64) {
        self.videoId = videoId
    }

    func load() async {
        loading = true
        let repo = Repository(api: AppState.shared.api)
        do {
            let video = try await repo.getVideo(id: videoId)
            current = video.tags ?? []
            allTags = (try? await repo.listVideoTags()) ?? []
            selected = Set(current.map(\.id))
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }

    func save() async throws {
        try await Repository(api: AppState.shared.api).replaceVideoTags(videoIds: [videoId], tagIds: Array(selected))
    }

    func createTag(name: String) async throws {
        let tag = try await Repository(api: AppState.shared.api).createVideoTag(name: name)
        allTags.append(tag)
        selected.insert(tag.id)
    }
}

struct VideoTagsEditorView: View {
    let videoId: Int64
    let onSaved: () -> Void

    @StateObject private var vm: VideoTagsEditorVM
    @Environment(\.dismiss) private var dismiss
    @State private var newTagName = ""
    @State private var showCreate = false
    @State private var saving = false

    init(videoId: Int64, onSaved: @escaping () -> Void) {
        self.videoId = videoId
        self.onSaved = onSaved
        _vm = StateObject(wrappedValue: VideoTagsEditorVM(videoId: videoId))
    }

    var body: some View {
        NavigationStack {
            List {
                Section("已选标签（\(vm.selected.count)）") {
                    ForEach(vm.allTags) { tag in
                        Button {
                            if vm.selected.contains(tag.id) {
                                vm.selected.remove(tag.id)
                            } else {
                                vm.selected.insert(tag.id)
                            }
                        } label: {
                            HStack {
                                Text(tag.name)
                                Spacer()
                                Text(Fmt.count(tag.count))
                                    .foregroundStyle(.secondary)
                                if vm.selected.contains(tag.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
                Section {
                    Button {
                        showCreate = true
                    } label: {
                        Label("新建标签", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("编辑标签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saving = true
                        Task {
                            do {
                                try await vm.save()
                                onSaved()
                                dismiss()
                            } catch {
                                vm.errorMessage = error.localizedDescription
                            }
                            saving = false
                        }
                    }
                    .disabled(saving)
                }
            }
            .sheet(isPresented: $showCreate) {
                VStack(spacing: 16) {
                    Text("新建标签")
                        .font(.headline)
                    TextField("标签名", text: $newTagName)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("取消", role: .cancel) { showCreate = false }
                            .frame(maxWidth: .infinity)
                        Button("创建") {
                            Task {
                                do {
                                    try await vm.createTag(name: newTagName)
                                    newTagName = ""
                                    showCreate = false
                                } catch {
                                    vm.errorMessage = error.localizedDescription
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding()
                .presentationDetents([.height(220)])
            }
            .task { await vm.load() }
            .errorAlert(vm.errorMessage) { vm.errorMessage = nil }
        }
    }
}

// MARK: - 视频关联作品（JAV 刮削）

@MainActor
final class VideoJavScrapeVM: ObservableObject {
    @Published var possibleCodes: VideoJavPossibleCodesResponse?
    @Published var lookupResult: VideoJavScrapeInfoResponse?
    @Published var loading = true
    @Published var busy = false
    @Published var errorMessage: String?
    @Published var provider = ""

    let videoId: Int64

    init(videoId: Int64) {
        self.videoId = videoId
    }

    func load() async {
        loading = true
        do {
            possibleCodes = try await Repository(api: AppState.shared.api).videoJavPossibleCodes(videoId: videoId)
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }

    func lookup(code: String) async {
        busy = true
        defer { busy = false }
        do {
            lookupResult = try await Repository(api: AppState.shared.api).videoJavLookup(videoId: videoId, provider: provider, code: code)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func link(code: String) async throws {
        let video = try await Repository(api: AppState.shared.api).getVideo(id: videoId)
        let locationId = video.locations?.first?.id ?? 0
        try await Repository(api: AppState.shared.api).videoJavLink(videoId: videoId, locationId: locationId, code: code)
    }

    func manual(_ request: VideoJavManualScrapeRequest) async throws {
        try await Repository(api: AppState.shared.api).videoJavManual(videoId: videoId, request: request)
    }
}

struct VideoJavScrapeView: View {
    let videoId: Int64
    let onChanged: () -> Void

    @StateObject private var vm: VideoJavScrapeVM
    @Environment(\.dismiss) private var dismiss
    @State private var showManual = false

    init(videoId: Int64, onChanged: @escaping () -> Void) {
        self.videoId = videoId
        self.onChanged = onChanged
        _vm = StateObject(wrappedValue: VideoJavScrapeVM(videoId: videoId))
    }

    var body: some View {
        NavigationStack {
            List {
                Section("关联已有作品") {
                    if vm.loading {
                        ProgressView()
                    } else if let codes = vm.possibleCodes, !codes.possibleCodes.isEmpty {
                        ForEach(codes.possibleCodes, id: \.self) { code in
                            HStack {
                                Text(code)
                                    .font(.subheadline.monospaced())
                                Spacer()
                                Button("关联") {
                                    Task {
                                        do {
                                            try await vm.link(code: code)
                                            onChanged()
                                            dismiss()
                                        } catch {
                                            vm.errorMessage = error.localizedDescription
                                        }
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .tint(.orange)
                            }
                        }
                    } else {
                        Text("未识别出候选番号")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("在线查询") {
                    Picker("数据源", selection: $vm.provider) {
                        Text("默认").tag("")
                        Text("JavDB").tag("javdb")
                        Text("JavBus").tag("javbus")
                    }
                    ForEach(vm.possibleCodes?.possibleCodes ?? [], id: \.self) { code in
                        Button {
                            Task { await vm.lookup(code: code) }
                        } label: {
                            Label("查询 \(code)", systemImage: "magnifyingglass")
                        }
                    }
                    if let result = vm.lookupResult {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(result.code).font(.headline.monospaced())
                            Text(result.title).font(.subheadline)
                            if !result.studio.isEmpty { Text("片商：\(result.studio)").font(.caption) }
                            if !result.series.isEmpty { Text("系列：\(result.series)").font(.caption) }
                            if !result.actors.isEmpty { Text("演员：\(result.actors.joined(separator: "、"))").font(.caption) }
                            if !result.tags.isEmpty {
                                ChipFlowLayout(chips: result.tags)
                            }
                            Button("抓取并关联") {
                                Task {
                                    do {
                                        try await vm.manual(VideoJavManualScrapeRequest(
                                            locationId: 0,
                                            code: result.code,
                                            title: result.title,
                                            studio: result.studio,
                                            series: result.series,
                                            releaseDate: result.releaseDate ?? "",
                                            durationMin: result.durationMin,
                                            tags: result.tags,
                                            actors: result.actors,
                                            coverUrl: result.coverUrl ?? "",
                                            isUncensored: result.isUncensored
                                        ))
                                        onChanged()
                                        dismiss()
                                    } catch {
                                        vm.errorMessage = error.localizedDescription
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                        }
                    }
                }

                Section {
                    Button {
                        showManual = true
                    } label: {
                        Label("手动填写元数据", systemImage: "square.and.pencil")
                    }
                }
            }
            .navigationTitle("关联 JAV 作品")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .sheet(isPresented: $showManual) {
                VideoManualScrapeView(videoId: videoId) {
                    onChanged()
                    dismiss()
                }
            }
            .task { await vm.load() }
            .errorAlert(vm.errorMessage) { vm.errorMessage = nil }
            .overlay {
                if vm.busy {
                    ProgressView("查询中…")
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
}

struct VideoManualScrapeView: View {
    let videoId: Int64
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var title = ""
    @State private var studio = ""
    @State private var series = ""
    @State private var releaseDate = ""
    @State private var durationMin = ""
    @State private var tags = ""
    @State private var actors = ""
    @State private var coverUrl = ""
    @State private var uncensored = false
    @State private var errorMessage: String?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("番号", text: $code)
                    TextField("标题", text: $title)
                    TextField("片商", text: $studio)
                    TextField("系列", text: $series)
                    TextField("发行日期 YYYY-MM-DD", text: $releaseDate)
                    TextField("时长（分钟）", text: $durationMin)
                        .keyboardType(.numberPad)
                    Toggle("无码", isOn: $uncensored)
                }
                Section("标签 / 演员") {
                    TextField("标签（逗号分隔）", text: $tags)
                    TextField("演员（逗号分隔）", text: $actors)
                }
                Section("封面") {
                    TextField("封面图片地址", text: $coverUrl)
                }
            }
            .navigationTitle("手动填写")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saving = true
                        Task {
                            do {
                                try await Repository(api: AppState.shared.api).videoJavManual(
                                    videoId: videoId,
                                    request: VideoJavManualScrapeRequest(
                                        locationId: 0,
                                        code: code,
                                        title: title,
                                        studio: studio,
                                        series: series,
                                        releaseDate: releaseDate,
                                        durationMin: Int(durationMin),
                                        tags: tags.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
                                        actors: actors.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
                                        coverUrl: coverUrl,
                                        isUncensored: uncensored
                                    ))
                                onDone()
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                            saving = false
                        }
                    }
                    .disabled(saving || code.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .errorAlert(errorMessage) { errorMessage = nil }
        }
    }
}

// MARK: - 视频位置管理

@MainActor
final class VideoLocationsVM: ObservableObject {
    @Published var locations: [VideoLocation] = []
    @Published var loading = true
    @Published var errorMessage: String?

    let videoId: Int64

    init(videoId: Int64) {
        self.videoId = videoId
    }

    func load() async {
        loading = true
        do {
            let video = try await Repository(api: AppState.shared.api).getVideo(id: videoId)
            locations = video.locations ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }
}

struct VideoLocationsView: View {
    let videoId: Int64
    let onChanged: () -> Void

    @StateObject private var vm: VideoLocationsVM
    @Environment(\.dismiss) private var dismiss
    @State private var renameTarget: VideoLocation?
    @State private var deleteTarget: VideoLocation?
    @State private var showRename = false
    @State private var showDelete = false

    init(videoId: Int64, onChanged: @escaping () -> Void) {
        self.videoId = videoId
        self.onChanged = onChanged
        _vm = StateObject(wrappedValue: VideoLocationsVM(videoId: videoId))
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(vm.locations) { loc in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(loc.filename ?? "位置 #\(loc.id)")
                            .font(.subheadline)
                        if let size = loc.size {
                            Text(Fmt.bytes(size))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            deleteTarget = loc
                            showDelete = true
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        Button {
                            renameTarget = loc
                            showRename = true
                        } label: {
                            Label("重命名", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
            }
            .navigationTitle("视频位置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task { await vm.load() }
            .errorAlert(vm.errorMessage) { vm.errorMessage = nil }
            .sheet(isPresented: $showRename) {
                TextInputDialog(title: "重命名位置", placeholder: "新文件名", initial: renameTarget?.filename ?? "") { name in
                    guard let target = renameTarget else { return }
                    Task {
                        do {
                            try await Repository(api: AppState.shared.api)
                                .renameVideoLocation(videoId: videoId, locationId: target.id, filename: name)
                            onChanged()
                            showRename = false
                            await vm.load()
                        } catch {
                            vm.errorMessage = error.localizedDescription
                        }
                    }
                } onCancel: {
                    showRename = false
                }
            }
            .confirmDialog(
                title: "删除位置",
                message: "确定要删除这个视频位置吗？对应文件也会被移入回收站。",
                confirmLabel: "删除",
                destructive: true,
                isPresented: $showDelete
            ) {
                guard let target = deleteTarget else { return }
                Task {
                    do {
                        try await Repository(api: AppState.shared.api)
                            .deleteVideoLocation(videoId: videoId, locationId: target.id)
                        onChanged()
                        await vm.load()
                    } catch {
                        vm.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }
}
