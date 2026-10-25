import SwiftUI
import SafariServices

struct SafariWrapper: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

// MARK: - 作品编辑

@MainActor
final class WorkEditVM: ObservableObject {
    @Published var studios: [JavStudioSummary] = []
    @Published var seriesList: [JavSeriesSummary] = []
    @Published var idols: [JavIdolSummary] = []
    @Published var loaded = false

    func loadOptions() async {
        let repo = Repository(api: AppState.shared.api)
        studios = (try? await repo.listStudios(limit: 200).items) ?? []
        seriesList = (try? await repo.listSeries(limit: 200).items) ?? []
        idols = (try? await repo.listIdols(limit: 200).items) ?? []
        loaded = true
    }
}

struct WorkEditView: View {
    let javId: Int64
    let onSaved: () -> Void

    @StateObject private var vm = WorkEditVM()
    @Environment(\.dismiss) private var dismiss
    @State private var jav: Jav?
    @State private var title = ""
    @State private var zhTitle = ""
    @State private var releaseDate = ""
    @State private var durationMin = ""
    @State private var coverUrl = ""
    @State private var studioId: Int64?
    @State private var seriesId: Int64?
    @State private var selectedIdols: Set<Int64> = []
    @State private var errorMessage: String?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("标题") {
                    TextField("标题", text: $title)
                    TextField("中文标题（可空）", text: $zhTitle)
                }
                Section("发行信息") {
                    TextField("发行日期 YYYY-MM-DD", text: $releaseDate)
                    TextField("时长（分钟）", text: $durationMin)
                        .keyboardType(.numberPad)
                }
                Section("片商 / 系列") {
                    Picker("片商", selection: Binding(
                        get: { studioId ?? 0 },
                        set: { studioId = $0 == 0 ? nil : $0 }
                    )) {
                        Text("无").tag(Int64(0))
                        ForEach(vm.studios) { studio in
                            Text(studio.name).tag(studio.id)
                        }
                    }
                    Picker("系列", selection: Binding(
                        get: { seriesId ?? 0 },
                        set: { seriesId = $0 == 0 ? nil : $0 }
                    )) {
                        Text("无").tag(Int64(0))
                        ForEach(vm.seriesList) { series in
                            Text(series.displayName).tag(series.id)
                        }
                    }
                }
                Section("演员") {
                    ForEach(vm.idols) { idol in
                        Button {
                            if selectedIdols.contains(idol.id) {
                                selectedIdols.remove(idol.id)
                            } else {
                                selectedIdols.insert(idol.id)
                            }
                        } label: {
                            HStack {
                                Text(idol.displayName)
                                Spacer()
                                if selectedIdols.contains(idol.id) {
                                    Image(systemName: "checkmark").foregroundStyle(.orange)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
                Section("封面") {
                    TextField("封面图片地址（留空不改）", text: $coverUrl)
                }
            }
            .navigationTitle("编辑作品")
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
                                try await Repository(api: AppState.shared.api).updateJavItem(
                                    id: javId,
                                    request: JavItemUpdateRequest(
                                        title: title,
                                        zhTitle: zhTitle,
                                        coverUrl: coverUrl.trimmingCharacters(in: .whitespaces).isEmpty ? nil : coverUrl,
                                        idolIds: Array(selectedIdols),
                                        studioId: studioId,
                                        seriesId: seriesId,
                                        releaseDate: releaseDate,
                                        durationMin: Int(durationMin)
                                    ))
                                onSaved()
                                dismiss()
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                            saving = false
                        }
                    }
                    .disabled(saving)
                }
            }
            .task {
                await vm.loadOptions()
                if let item = try? await Repository(api: AppState.shared.api).getJavItem(id: javId) {
                    jav = item
                    title = item.title
                    zhTitle = item.zhTitle ?? ""
                    releaseDate = item.releaseUnix.map { release in
                        let date = Date(timeIntervalSince1970: TimeInterval(release))
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM-dd"
                        return formatter.string(from: date)
                    } ?? ""
                    durationMin = item.durationMin.map(String.init) ?? ""
                    studioId = item.studioId
                    seriesId = item.seriesId
                    selectedIdols = Set((item.idols ?? []).map(\.id))
                }
            }
            .errorAlert(errorMessage) { errorMessage = nil }
        }
    }
}

// MARK: - 收藏夹选择

@MainActor
final class FavoritePickerVM: ObservableObject {
    @Published var groups: [FavoriteGroupSummary] = []
    @Published var selected: Set<Int64> = []
    @Published var loading = true
    @Published var errorMessage: String?

    let entity: FavoriteEntity
    let itemId: Int64

    init(entity: FavoriteEntity, itemId: Int64) {
        self.entity = entity
        self.itemId = itemId
    }

    func load() async {
        loading = true
        let repo = Repository(api: AppState.shared.api)
        do {
            groups = try await repo.listFavoriteGroups(entity)
            let ids = try await repo.selectedFavoriteGroupIds(entity, itemId: itemId)
            selected = Set(ids)
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }

    func save() async throws {
        try await Repository(api: AppState.shared.api).replaceFavoriteGroups(entity, itemId: itemId, groupIds: Array(selected))
    }

    func create(name: String) async throws {
        let group = try await Repository(api: AppState.shared.api).createFavoriteGroup(entity, name: name)
        groups.append(group)
        selected.insert(group.id)
    }
}

struct FavoritePickerSheet: View {
    let entity: FavoriteEntity
    let itemId: Int64
    let title: String
    let onSaved: () -> Void

    @StateObject private var vm: FavoritePickerVM
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var showCreate = false

    init(entity: FavoriteEntity, itemId: Int64, title: String, onSaved: @escaping () -> Void) {
        self.entity = entity
        self.itemId = itemId
        self.title = title
        self.onSaved = onSaved
        _vm = StateObject(wrappedValue: FavoritePickerVM(entity: entity, itemId: itemId))
    }

    var body: some View {
        NavigationStack {
            List {
                Section("加入收藏夹") {
                    ForEach(vm.groups) { group in
                        Button {
                            if vm.selected.contains(group.id) {
                                vm.selected.remove(group.id)
                            } else {
                                vm.selected.insert(group.id)
                            }
                        } label: {
                            HStack {
                                Text(group.name)
                                Spacer()
                                Text(Fmt.count(group.count))
                                    .foregroundStyle(.secondary)
                                if vm.selected.contains(group.id) {
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
                        Label("新建收藏夹", systemImage: "plus")
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            do {
                                try await vm.save()
                                onSaved()
                                dismiss()
                            } catch {
                                vm.errorMessage = error.localizedDescription
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showCreate) {
                VStack(spacing: 16) {
                    Text("新建收藏夹")
                        .font(.headline)
                    TextField("名称", text: $newName)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("取消", role: .cancel) { showCreate = false }
                            .frame(maxWidth: .infinity)
                        Button("创建") {
                            Task {
                                do {
                                    try await vm.create(name: newName)
                                    newName = ""
                                    showCreate = false
                                } catch {
                                    vm.errorMessage = error.localizedDescription
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
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

// MARK: - 喜爱度

struct RatingSheet: View {
    let current: Double
    let onSave: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var rating: Double = 0

    var body: some View {
        VStack(spacing: 20) {
            Text("喜爱度")
                .font(.headline)
            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { i in
                    Image(systemName: rating >= Double(i) + 0.75 ? "star.fill" : (rating >= Double(i) + 0.25 ? "star.leadinghalf.filled" : "star"))
                        .font(.largeTitle)
                        .foregroundStyle(.yellow)
                        .onTapGesture {
                            rating = Double(i) + 1
                        }
                }
            }
            Text(String(format: "%.1f 分", rating))
                .foregroundStyle(.secondary)
            HStack {
                Button("取消", role: .cancel) { dismiss() }
                    .frame(maxWidth: .infinity)
                Button("保存") {
                    onSave(rating)
                    dismiss()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .onAppear { rating = current }
        .presentationDetents([.height(260)])
    }
}

// MARK: - 作品标签编辑

@MainActor
final class JavTagsEditorVM: ObservableObject {
    @Published var allTags: [JavTag] = []
    @Published var selected: Set<Int64> = []
    @Published var loading = true
    @Published var errorMessage: String?

    let javId: Int64

    init(javId: Int64) {
        self.javId = javId
    }

    func load() async {
        loading = true
        let repo = Repository(api: AppState.shared.api)
        do {
            let item = try await repo.getJavItem(id: javId)
            allTags = (try? await repo.listJavTags()) ?? []
            selected = Set((item.tags ?? []).map(\.id))
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }

    func save() async throws {
        try await Repository(api: AppState.shared.api).replaceJavTags(javIds: [javId], tagIds: Array(selected))
    }

    func create(name: String) async throws {
        let tag = try await Repository(api: AppState.shared.api).createJavTag(name: name)
        allTags.append(tag)
        selected.insert(tag.id)
    }
}

struct JavTagsEditorView: View {
    let javId: Int64
    let onSaved: () -> Void

    @StateObject private var vm: JavTagsEditorVM
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var showCreate = false

    init(javId: Int64, onSaved: @escaping () -> Void) {
        self.javId = javId
        self.onSaved = onSaved
        _vm = StateObject(wrappedValue: JavTagsEditorVM(javId: javId))
    }

    var body: some View {
        NavigationStack {
            List {
                Section("标签（\(vm.selected.count)）") {
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
                                    Image(systemName: "checkmark").foregroundStyle(.orange)
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
                        Task {
                            do {
                                try await vm.save()
                                onSaved()
                                dismiss()
                            } catch {
                                vm.errorMessage = error.localizedDescription
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showCreate) {
                VStack(spacing: 16) {
                    Text("新建标签")
                        .font(.headline)
                    TextField("标签名", text: $newName)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("取消", role: .cancel) { showCreate = false }
                            .frame(maxWidth: .infinity)
                        Button("创建") {
                            Task {
                                do {
                                    try await vm.create(name: newName)
                                    newName = ""
                                    showCreate = false
                                } catch {
                                    vm.errorMessage = error.localizedDescription
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
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
