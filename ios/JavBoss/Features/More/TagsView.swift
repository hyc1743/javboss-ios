import SwiftUI

/// 标签管理：视频标签 + 作品标签，均支持分类 CRUD
struct TagsView: View {
    @State private var kind = 0 // 0 = 作品标签, 1 = 视频标签

    var body: some View {
        VStack(spacing: 0) {
            Picker("类型", selection: $kind) {
                Text("作品标签").tag(0)
                Text("视频标签").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            if kind == 0 {
                JavTagsManageView()
            } else {
                VideoTagsManageView()
            }
        }
        .background(Color(white: 0.09))
        .navigationTitle("标签")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 作品标签

@MainActor
final class JavTagsManageVM: ObservableObject {
    @Published var tags: [JavTag] = []
    @Published var categories: [JavTagCategory] = []
    @Published var loading = true
    @Published var errorMessage: String?

    func load() async {
        loading = true
        let repo = Repository(api: AppState.shared.api)
        do {
            tags = try await repo.listJavTags()
            categories = try await repo.listJavTagCategories()
        } catch let error as ApiError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }

    func clearError() { errorMessage = nil }

    func create(name: String) async throws {
        _ = try await Repository(api: AppState.shared.api).createJavTag(name: name)
        await load()
    }

    func createScraped(name: String) async throws {
        _ = try await Repository(api: AppState.shared.api).createJavScrapedTag(name: name)
        await load()
    }

    func rename(_ tag: JavTag, to name: String) async throws {
        try await Repository(api: AppState.shared.api).renameJavTag(id: tag.id, name: name)
        await load()
    }

    func delete(_ tag: JavTag) async throws {
        try await Repository(api: AppState.shared.api).deleteJavTag(id: tag.id)
        await load()
    }

    func createCategory(name: String) async throws {
        _ = try await Repository(api: AppState.shared.api).createJavTagCategory(name: name)
        await load()
    }

    func renameCategory(_ category: JavTagCategory, to name: String) async throws {
        try await Repository(api: AppState.shared.api).renameJavTagCategory(id: category.id, name: name)
        await load()
    }

    func deleteCategory(_ category: JavTagCategory) async throws {
        try await Repository(api: AppState.shared.api).deleteJavTagCategory(id: category.id)
        await load()
    }

    func assignCategory(tagIds: [Int64], categoryId: Int64?) async throws {
        try await Repository(api: AppState.shared.api).assignJavTagsCategory(tagIds: tagIds, categoryId: categoryId)
        await load()
    }

    func organize() async throws {
        try await Repository(api: AppState.shared.api).organizeJavTags()
        await load()
    }
}

struct JavTagsManageView: View {
    @StateObject private var vm = JavTagsManageVM()
    @State private var showCreate = false
    @State private var showScrapedCreate = false
    @State private var renameTarget: JavTag?
    @State private var deleteTarget: JavTag?
    @State private var showRename = false
    @State private var showDelete = false
    @State private var showCategories = false
    @State private var showAssign = false
    @State private var assignTagIds: Set<Int64> = []
    @State private var newTagName = ""

    var body: some View {
        Group {
            if vm.loading && vm.tags.isEmpty {
                Spacer()
                ProgressView("加载中…")
                Spacer()
            } else {
                List {
                    ForEach(vm.tags) { tag in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tag.name)
                                    .font(.subheadline)
                                if let categoryName = tag.categoryName, !categoryName.isEmpty {
                                    Text(categoryName)
                                        .font(.caption2)
                                        .foregroundStyle(.blue)
                                }
                            }
                            Spacer()
                            Text(Fmt.count(tag.count))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if tag.isUser == true {
                                Image(systemName: "person.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if assignTagIds.contains(tag.id) {
                                assignTagIds.remove(tag.id)
                            } else {
                                assignTagIds.insert(tag.id)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleteTarget = tag
                                showDelete = true
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button {
                                renameTarget = tag
                                showRename = true
                            } label: {
                                Label("重命名", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 14) {
                    Button {
                        showCategories = true
                    } label: {
                        Image(systemName: "folder")
                    }
                    if !assignTagIds.isEmpty {
                        Button {
                            showAssign = true
                        } label: {
                            Image(systemName: "tag")
                        }
                    }
                    Button {
                        showCreate = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    Menu {
                        Button("New scraped tag") { showScrapedCreate = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .task { await vm.load() }
        .errorAlert(vm.errorMessage) { vm.clearError() }
        .sheet(isPresented: $showCreate) {
            VStack(spacing: 16) {
                Text("新建作品标签")
                    .font(.headline)
                TextField("标签名", text: $newTagName)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("取消", role: .cancel) {
                        newTagName = ""
                        showCreate = false
                    }
                    .frame(maxWidth: .infinity)
                    Button("创建") {
                        Task {
                            do {
                                try await vm.create(name: newTagName)
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
        .sheet(isPresented: $showRename) {
            TextInputDialog(title: "重命名标签", placeholder: "新名称", initial: renameTarget?.name ?? "") { name in
                guard let target = renameTarget else { return }
                Task {
                    do {
                        try await vm.rename(target, to: name)
                        showRename = false
                    } catch {
                        vm.errorMessage = error.localizedDescription
                    }
                }
            } onCancel: { showRename = false }
        }
        .alert("New scraped tag", isPresented: $showScrapedCreate) {
            TextField("Tag name", text: $newTagName)
            Button("Cancel", role: .cancel) { newTagName = "" }
            Button("Create") {
                Task {
                    do {
                        try await vm.createScraped(name: newTagName)
                        newTagName = ""
                    } catch {
                        vm.errorMessage = error.localizedDescription
                    }
                }
            }
            .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
        } message: {
            Text("Creates a tag with the upstream scraped-tag provider.")
        }
        .confirmDialog(
            title: "删除标签",
            message: "确定删除标签「\(deleteTarget?.name ?? "")」？",
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
        .sheet(isPresented: $showCategories) {
            JavTagCategoriesSheet(vm: vm)
        }
        .sheet(isPresented: $showAssign) {
            JavTagAssignSheet(vm: vm, tagIds: Array(assignTagIds)) {
                assignTagIds.removeAll()
            }
        }
    }
}

struct JavTagCategoriesSheet: View {
    @ObservedObject var vm: JavTagsManageVM
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var showCreate = false
    @State private var renameTarget: JavTagCategory?
    @State private var deleteTarget: JavTagCategory?
    @State private var showRename = false
    @State private var showDelete = false

    var body: some View {
        NavigationStack {
            List {
                Section("作品标签分类") {
                    ForEach(vm.categories) { category in
                        HStack {
                            Text(category.name)
                            Spacer()
                            Text("\(category.sortOrder ?? 0)")
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleteTarget = category
                                showDelete = true
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button {
                                renameTarget = category
                                showRename = true
                            } label: {
                                Label("重命名", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }
                Section {
                    Button {
                        Task {
                            do {
                                try await vm.organize()
                            } catch {
                                vm.errorMessage = error.localizedDescription
                            }
                        }
                    } label: {
                        Label("从 JavBus 导入分类", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        showCreate = true
                    } label: {
                        Label("新建分类", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("标签分类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .sheet(isPresented: $showCreate) {
                VStack(spacing: 16) {
                    Text("新建分类")
                        .font(.headline)
                    TextField("分类名", text: $newName)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("取消", role: .cancel) { showCreate = false }
                            .frame(maxWidth: .infinity)
                        Button("创建") {
                            Task {
                                do {
                                    try await vm.createCategory(name: newName)
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
            .sheet(isPresented: $showRename) {
                TextInputDialog(title: "重命名分类", placeholder: "新名称", initial: renameTarget?.name ?? "") { name in
                    guard let target = renameTarget else { return }
                    Task {
                        do {
                            try await vm.renameCategory(target, to: name)
                            showRename = false
                        } catch {
                            vm.errorMessage = error.localizedDescription
                        }
                    }
                } onCancel: { showRename = false }
            }
            .confirmDialog(
                title: "删除分类",
                message: "删除分类「\(deleteTarget?.name ?? "")」？分类下的标签会变为未分类。",
                confirmLabel: "删除",
                destructive: true,
                isPresented: $showDelete
            ) {
                guard let target = deleteTarget else { return }
                Task {
                    do {
                        try await vm.deleteCategory(target)
                    } catch {
                        vm.errorMessage = error.localizedDescription
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct JavTagAssignSheet: View {
    @ObservedObject var vm: JavTagsManageVM
    let tagIds: [Int64]
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: Int64?

    var body: some View {
        NavigationStack {
            List {
                Section("为 \(tagIds.count) 个标签选择分类") {
                    Button {
                        selectedCategory = nil
                    } label: {
                        HStack {
                            Text("无分类")
                            Spacer()
                            if selectedCategory == nil {
                                Image(systemName: "checkmark").foregroundStyle(.orange)
                            }
                        }
                    }
                    ForEach(vm.categories) { category in
                        Button {
                            selectedCategory = category.id
                        } label: {
                            HStack {
                                Text(category.name)
                                Spacer()
                                if selectedCategory == category.id {
                                    Image(systemName: "checkmark").foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("调整分类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") {
                        Task {
                            do {
                                try await vm.assignCategory(tagIds: tagIds, categoryId: selectedCategory)
                                onDone()
                                dismiss()
                            } catch {
                                vm.errorMessage = error.localizedDescription
                            }
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - 视频标签

@MainActor
final class VideoTagsManageVM: ObservableObject {
    @Published var tags: [VideoTagCount] = []
    @Published var categories: [TagCategory] = []
    @Published var loading = true
    @Published var errorMessage: String?

    func load() async {
        loading = true
        let repo = Repository(api: AppState.shared.api)
        do {
            tags = try await repo.listVideoTags()
            categories = try await repo.listVideoTagCategories()
        } catch let error as ApiError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }

    func clearError() { errorMessage = nil }

    func create(name: String) async throws {
        _ = try await Repository(api: AppState.shared.api).createVideoTag(name: name)
        await load()
    }

    func rename(_ tag: VideoTagCount, to name: String) async throws {
        try await Repository(api: AppState.shared.api).renameVideoTag(id: tag.id, name: name)
        await load()
    }

    func delete(_ tag: VideoTagCount) async throws {
        try await Repository(api: AppState.shared.api).deleteVideoTag(id: tag.id)
        await load()
    }

    func createCategory(name: String) async throws {
        _ = try await Repository(api: AppState.shared.api).createVideoTagCategory(name: name)
        await load()
    }

    func renameCategory(_ category: TagCategory, to name: String) async throws {
        try await Repository(api: AppState.shared.api).renameVideoTagCategory(id: category.id, name: name)
        await load()
    }

    func deleteCategory(_ category: TagCategory) async throws {
        try await Repository(api: AppState.shared.api).deleteVideoTagCategory(id: category.id)
        await load()
    }

    func assignCategory(tagIds: [Int64], categoryId: Int64?) async throws {
        try await Repository(api: AppState.shared.api).assignVideoTagsCategory(tagIds: tagIds, categoryId: categoryId)
        await load()
    }
}

struct VideoTagsManageView: View {
    @StateObject private var vm = VideoTagsManageVM()
    @State private var showCreate = false
    @State private var renameTarget: VideoTagCount?
    @State private var deleteTarget: VideoTagCount?
    @State private var showRename = false
    @State private var showDelete = false
    @State private var showCategories = false
    @State private var showAssign = false
    @State private var assignTagIds: Set<Int64> = []
    @State private var newTagName = ""

    var body: some View {
        Group {
            if vm.loading && vm.tags.isEmpty {
                Spacer()
                ProgressView("加载中…")
                Spacer()
            } else {
                List {
                    ForEach(vm.tags) { tag in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tag.name)
                                    .font(.subheadline)
                                if let categoryName = tag.categoryName, !categoryName.isEmpty {
                                    Text(categoryName)
                                        .font(.caption2)
                                        .foregroundStyle(.blue)
                                }
                            }
                            Spacer()
                            Text(Fmt.count(tag.count))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if assignTagIds.contains(tag.id) {
                                assignTagIds.remove(tag.id)
                            } else {
                                assignTagIds.insert(tag.id)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleteTarget = tag
                                showDelete = true
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button {
                                renameTarget = tag
                                showRename = true
                            } label: {
                                Label("重命名", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 14) {
                    Button {
                        showCategories = true
                    } label: {
                        Image(systemName: "folder")
                    }
                    if !assignTagIds.isEmpty {
                        Button {
                            showAssign = true
                        } label: {
                            Image(systemName: "tag")
                        }
                    }
                    Button {
                        showCreate = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .task { await vm.load() }
        .errorAlert(vm.errorMessage) { vm.clearError() }
        .sheet(isPresented: $showCreate) {
            VStack(spacing: 16) {
                Text("新建视频标签")
                    .font(.headline)
                TextField("标签名", text: $newTagName)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("取消", role: .cancel) {
                        newTagName = ""
                        showCreate = false
                    }
                    .frame(maxWidth: .infinity)
                    Button("创建") {
                        Task {
                            do {
                                try await vm.create(name: newTagName)
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
        .sheet(isPresented: $showRename) {
            TextInputDialog(title: "重命名标签", placeholder: "新名称", initial: renameTarget?.name ?? "") { name in
                guard let target = renameTarget else { return }
                Task {
                    do {
                        try await vm.rename(target, to: name)
                        showRename = false
                    } catch {
                        vm.errorMessage = error.localizedDescription
                    }
                }
            } onCancel: { showRename = false }
        }
        .confirmDialog(
            title: "删除标签",
            message: "确定删除标签「\(deleteTarget?.name ?? "")」？",
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
        .sheet(isPresented: $showCategories) {
            VideoTagCategoriesSheet(vm: vm)
        }
        .sheet(isPresented: $showAssign) {
            VideoTagAssignSheet(vm: vm, tagIds: Array(assignTagIds)) {
                assignTagIds.removeAll()
            }
        }
    }
}

struct VideoTagCategoriesSheet: View {
    @ObservedObject var vm: VideoTagsManageVM
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var showCreate = false
    @State private var renameTarget: TagCategory?
    @State private var deleteTarget: TagCategory?
    @State private var showRename = false
    @State private var showDelete = false

    var body: some View {
        NavigationStack {
            List {
                Section("视频标签分类") {
                    ForEach(vm.categories) { category in
                        HStack {
                            Text(category.name)
                            Spacer()
                            Text("\(category.sortOrder ?? 0)")
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleteTarget = category
                                showDelete = true
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button {
                                renameTarget = category
                                showRename = true
                            } label: {
                                Label("重命名", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }
                Section {
                    Button {
                        showCreate = true
                    } label: {
                        Label("新建分类", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("标签分类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .sheet(isPresented: $showCreate) {
                VStack(spacing: 16) {
                    Text("新建分类")
                        .font(.headline)
                    TextField("分类名", text: $newName)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("取消", role: .cancel) { showCreate = false }
                            .frame(maxWidth: .infinity)
                        Button("创建") {
                            Task {
                                do {
                                    try await vm.createCategory(name: newName)
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
            .sheet(isPresented: $showRename) {
                TextInputDialog(title: "重命名分类", placeholder: "新名称", initial: renameTarget?.name ?? "") { name in
                    guard let target = renameTarget else { return }
                    Task {
                        do {
                            try await vm.renameCategory(target, to: name)
                            showRename = false
                        } catch {
                            vm.errorMessage = error.localizedDescription
                        }
                    }
                } onCancel: { showRename = false }
            }
            .confirmDialog(
                title: "删除分类",
                message: "删除分类「\(deleteTarget?.name ?? "")」？",
                confirmLabel: "删除",
                destructive: true,
                isPresented: $showDelete
            ) {
                guard let target = deleteTarget else { return }
                Task {
                    do {
                        try await vm.deleteCategory(target)
                    } catch {
                        vm.errorMessage = error.localizedDescription
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct VideoTagAssignSheet: View {
    @ObservedObject var vm: VideoTagsManageVM
    let tagIds: [Int64]
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: Int64?

    var body: some View {
        NavigationStack {
            List {
                Section("为 \(tagIds.count) 个标签选择分类") {
                    Button {
                        selectedCategory = nil
                    } label: {
                        HStack {
                            Text("无分类")
                            Spacer()
                            if selectedCategory == nil {
                                Image(systemName: "checkmark").foregroundStyle(.orange)
                            }
                        }
                    }
                    ForEach(vm.categories) { category in
                        Button {
                            selectedCategory = category.id
                        } label: {
                            HStack {
                                Text(category.name)
                                Spacer()
                                if selectedCategory == category.id {
                                    Image(systemName: "checkmark").foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("调整分类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") {
                        Task {
                            do {
                                try await vm.assignCategory(tagIds: tagIds, categoryId: selectedCategory)
                                onDone()
                                dismiss()
                            } catch {
                                vm.errorMessage = error.localizedDescription
                            }
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
