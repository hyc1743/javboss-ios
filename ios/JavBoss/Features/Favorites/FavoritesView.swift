import SwiftUI

struct FavoritesView: View {
    @State private var entity: FavoriteEntity = .jav

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("类型", selection: $entity) {
                    ForEach(FavoriteEntity.allCases) { e in
                        Text(e.label).tag(e)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                FavoriteGroupsView(entity: entity)
                    .id(entity)
            }
            .background(Color(white: 0.09))
            .navigationTitle("收藏")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

@MainActor
final class FavoriteGroupsVM: ObservableObject {
    @Published var groups: [FavoriteGroupSummary] = []
    @Published var loading = true
    @Published var errorMessage: String?
    @Published var pendingCreateName = ""

    var entity: FavoriteEntity

    init(entity: FavoriteEntity) {
        self.entity = entity
    }

    func load() async {
        loading = true
        do {
            groups = try await Repository(api: AppState.shared.api).listFavoriteGroups(entity)
        } catch let error as ApiError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }

    func clearError() { errorMessage = nil }

    func create(name: String) async throws {
        let group = try await Repository(api: AppState.shared.api).createFavoriteGroup(entity, name: name)
        groups.append(group)
    }

    func rename(_ group: FavoriteGroupSummary, to name: String) async throws {
        try await Repository(api: AppState.shared.api).renameFavoriteGroup(entity, id: group.id, name: name)
        await load()
    }

    func delete(_ group: FavoriteGroupSummary) async throws {
        try await Repository(api: AppState.shared.api).deleteFavoriteGroup(entity, id: group.id)
        await load()
    }

    func move(from source: IndexSet, to destination: Int) {
        groups.move(fromOffsets: source, toOffset: destination)
        let ids = groups.map(\.id)
        Task {
            try? await Repository(api: AppState.shared.api).reorderFavoriteGroups(entity, ids: ids)
        }
    }
}

struct FavoriteGroupsView: View {
    let entity: FavoriteEntity

    @StateObject private var vm: FavoriteGroupsVM
    @State private var showCreate = false
    @State private var renameTarget: FavoriteGroupSummary?
    @State private var deleteTarget: FavoriteGroupSummary?
    @State private var showRename = false
    @State private var showDelete = false

    init(entity: FavoriteEntity) {
        self.entity = entity
        _vm = StateObject(wrappedValue: FavoriteGroupsVM(entity: entity))
    }

    var body: some View {
        Group {
            if vm.loading && vm.groups.isEmpty {
                Spacer()
                ProgressView("加载中…")
                Spacer()
            } else if vm.groups.isEmpty {
                EmptyPlaceholder(icon: "heart", text: "暂无收藏夹")
            } else {
                List {
                    ForEach(vm.groups) { group in
                        NavigationLink {
                            FavoriteGroupItemsView(entity: entity, group: group)
                        } label: {
                            HStack {
                                Image(systemName: "folder")
                                    .foregroundStyle(.orange)
                                Text(group.name)
                                Spacer()
                                Text(Fmt.count(group.count))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleteTarget = group
                                showDelete = true
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button {
                                renameTarget = group
                                showRename = true
                            } label: {
                                Label("重命名", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                    .onMove { source, destination in
                        vm.move(from: source, to: destination)
                    }
                }
                .listStyle(.plain)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack {
                    EditButton()
                    Button {
                        showCreate = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .task(id: entity) {
            vm.entity = entity
            await vm.load()
        }
        .errorAlert(vm.errorMessage) { vm.clearError() }
        .sheet(isPresented: $showCreate) {
            VStack(spacing: 16) {
                Text("新建收藏夹")
                    .font(.headline)
                TextField("名称", text: $vm.pendingCreateName)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("取消", role: .cancel) { showCreate = false }
                        .frame(maxWidth: .infinity)
                    Button("创建") {
                        Task {
                            do {
                                try await vm.create(name: vm.pendingCreateName)
                                vm.pendingCreateName = ""
                                showCreate = false
                            } catch {
                                vm.errorMessage = error.localizedDescription
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(vm.pendingCreateName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding()
            .presentationDetents([.height(220)])
        }
        .sheet(isPresented: $showRename) {
            TextInputDialog(title: "重命名收藏夹", placeholder: "新名称", initial: renameTarget?.name ?? "") { name in
                guard let target = renameTarget else { return }
                Task {
                    do {
                        try await vm.rename(target, to: name)
                        showRename = false
                    } catch {
                        vm.errorMessage = error.localizedDescription
                    }
                }
            } onCancel: {
                showRename = false
            }
        }
        .confirmDialog(
            title: "删除收藏夹",
            message: "确定要删除这个收藏夹吗？收藏条目不会被删除。",
            confirmLabel: "删除",
            destructive: true,
            isPresented: $showDelete
        ) {
            guard let target = deleteTarget else { return }
            Task {
                do {
                    try await vm.delete(target)
                } catch {
                    vm.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

@MainActor
final class FavoriteGroupItemsVM: ObservableObject {
    @Published var items: [FavoriteItemSummary] = []
    @Published var loading = true
    @Published var errorMessage: String?

    let entity: FavoriteEntity
    let group: FavoriteGroupSummary

    init(entity: FavoriteEntity, group: FavoriteGroupSummary) {
        self.entity = entity
        self.group = group
    }

    func load() async {
        loading = true
        do {
            items = try await Repository(api: AppState.shared.api).listFavoriteGroupItems(entity, id: group.id)
        } catch let error as ApiError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }

    func clearError() { errorMessage = nil }

    func remove(_ item: FavoriteItemSummary) async throws {
        try await Repository(api: AppState.shared.api).removeFavoriteGroupItems(entity, id: group.id, entityIds: [item.id])
        await load()
    }

    func move(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        let ids = items.map(\.id)
        Task {
            try? await Repository(api: AppState.shared.api).reorderFavoriteGroupItems(entity, id: group.id, entityIds: ids)
        }
    }
}

struct FavoriteGroupItemsView: View {
    let entity: FavoriteEntity
    let group: FavoriteGroupSummary

    @StateObject private var vm: FavoriteGroupItemsVM
    @State private var deleteTarget: FavoriteItemSummary?
    @State private var showDelete = false
    @State private var showAdd = false

    init(entity: FavoriteEntity, group: FavoriteGroupSummary) {
        self.entity = entity
        self.group = group
        _vm = StateObject(wrappedValue: FavoriteGroupItemsVM(entity: entity, group: group))
    }

    var body: some View {
        Group {
            if vm.loading && vm.items.isEmpty {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.items.isEmpty {
                EmptyPlaceholder(icon: "tray", text: "收藏夹为空")
            } else {
                List {
                    ForEach(vm.items) { item in
                        itemLink(item)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    deleteTarget = item
                                    showDelete = true
                                } label: {
                                    Label("移除", systemImage: "heart.slash")
                                }
                            }
                    }
                    .onMove { source, destination in
                        vm.move(from: source, to: destination)
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(Color(white: 0.09))
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack {
                    if entity == .jav {
                        Button {
                            showAdd = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                    EditButton()
                }
            }
        }
        .task { await vm.load() }
        .errorAlert(vm.errorMessage) { vm.clearError() }
        .confirmDialog(
            title: "移除条目",
            message: "从收藏夹移除「\(deleteTarget?.displayName ?? "")」？",
            confirmLabel: "移除",
            destructive: true,
            isPresented: $showDelete
        ) {
            guard let target = deleteTarget else { return }
            Task {
                do {
                    try await vm.remove(target)
                } catch {
                    vm.errorMessage = error.localizedDescription
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddWorksToGroupView(groupId: group.id) {
                Task { await vm.load() }
            }
        }
    }

    @ViewBuilder
    private func itemLink(_ item: FavoriteItemSummary) -> some View {
        switch entity {
        case .jav:
            NavigationLink {
                WorkDetailView(javId: item.id)
            } label: {
                FavoriteItemRow(item: item, icon: "film")
            }
            .contextMenu {
                Button {
                    Task {
                        if let jav = try? await Repository(api: AppState.shared.api).getJavItem(id: item.id) {
                            for video in jav.videos ?? [] { PlaybackQueue.shared.add(video) }
                        }
                    }
                } label: {
                    Label("Add videos to playlist", systemImage: "text.badge.plus")
                }
            }
        case .idol:
            NavigationLink {
                IdolDetailView(idolId: item.id)
            } label: {
                FavoriteItemRow(item: item, icon: "person")
            }
        case .studio:
            NavigationLink {
                StudioDetailView(studioId: item.id)
            } label: {
                FavoriteItemRow(item: item, icon: "building.2")
            }
        case .series:
            NavigationLink {
                SeriesDetailView(seriesId: item.id)
            } label: {
                FavoriteItemRow(item: item, icon: "list.bullet.rectangle")
            }
        }
    }
}

struct FavoriteItemRow: View {
    let item: FavoriteItemSummary
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.orange)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.subheadline)
                if !item.displaySubtitle.isEmpty {
                    Text(item.displaySubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

// MARK: - 批量添加作品到收藏夹

@MainActor
final class AddWorksToGroupVM: ObservableObject {
    @Published var works: [Jav] = []
    @Published var selected: Set<Int64> = []
    @Published var search = ""
    @Published var loading = false
    @Published var errorMessage: String?

    let groupId: Int64

    init(groupId: Int64) {
        self.groupId = groupId
    }

    func searchWorks() async {
        loading = true
        do {
            works = try await Repository(api: AppState.shared.api)
                .searchJav(limit: 100, offset: 0, search: search).items
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }

    func save() async throws {
        try await Repository(api: AppState.shared.api)
            .addJavsToFavoriteGroups(javIds: Array(selected), groupIds: [groupId])
    }
}

struct AddWorksToGroupView: View {
    let groupId: Int64
    let onAdded: () -> Void

    @StateObject private var vm: AddWorksToGroupVM
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    init(groupId: Int64, onAdded: @escaping () -> Void) {
        self.groupId = groupId
        self.onAdded = onAdded
        _vm = StateObject(wrappedValue: AddWorksToGroupVM(groupId: groupId))
    }

    var body: some View {
        NavigationStack {
            List {
                Section("选择作品（\(vm.selected.count)）") {
                    ForEach(vm.works) { jav in
                        Button {
                            if vm.selected.contains(jav.id) {
                                vm.selected.remove(jav.id)
                            } else {
                                vm.selected.insert(jav.id)
                            }
                        } label: {
                            HStack {
                                Text(jav.displayTitle)
                                    .font(.subheadline)
                                    .lineLimit(2)
                                Spacer()
                                if vm.selected.contains(jav.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    if vm.works.isEmpty && !vm.loading {
                        Text("输入番号搜索作品")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("添加作品")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        Task {
                            do {
                                try await vm.save()
                                onAdded()
                                dismiss()
                            } catch {
                                vm.errorMessage = error.localizedDescription
                            }
                        }
                    }
                    .disabled(vm.selected.isEmpty)
                }
            }
            .searchable(text: $searchText, prompt: "搜索番号 / 标题")
            .onSubmit(of: .search) {
                vm.search = searchText
                Task { await vm.searchWorks() }
            }
            .errorAlert(vm.errorMessage) { vm.errorMessage = nil }
        }
    }
}
