import SwiftUI

@MainActor
final class DirectoriesVM: ObservableObject {
    @Published var directories: [Directory] = []
    @Published var loading = true
    @Published var errorMessage: String?
    @Published var busyLabel: String?

    func load() async {
        loading = true
        do {
            directories = try await Repository(api: AppState.shared.api).listDirectories()
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

    func delete(_ dir: Directory) {
        perform("删除目录") {
            try await Repository(api: AppState.shared.api)
                .updateDirectory(id: dir.id, request: DirectoryUpdateRequest(isDelete: true))
        }
    }
}

struct DirectoriesView: View {
    @StateObject private var vm = DirectoriesVM()
    @State private var showCreate = false
    @State private var editTarget: Directory?
    @State private var showEdit = false
    @State private var deleteTarget: Directory?
    @State private var showDelete = false

    var body: some View {
        NavigationStack {
            Group {
                if vm.loading && vm.directories.isEmpty {
                    Spacer()
                    ProgressView("加载中…")
                    Spacer()
                } else if vm.directories.isEmpty {
                    EmptyPlaceholder(icon: "folder", text: "暂无目录，点右上角 + 添加")
                } else {
                    List {
                        ForEach(vm.directories) { dir in
                            DirectoryRow(dir: dir)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    editTarget = dir
                                    showEdit = true
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        deleteTarget = dir
                                        showDelete = true
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("目录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreate = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .refreshable { await vm.load() }
            .task { await vm.load() }
            .errorAlert(vm.errorMessage) { vm.clearError() }
            .overlay {
                if vm.busyLabel != nil {
                    ProgressView(vm.busyLabel ?? "处理中…")
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .sheet(isPresented: $showCreate) {
                DirectoryCreateView {
                    Task { await vm.load() }
                }
            }
            .sheet(item: $editTarget) { dir in
                DirectoryEditView(directory: dir) {
                    Task { await vm.load() }
                }
            }
            .confirmDialog(
                title: "删除目录",
                message: "删除「\(deleteTarget?.path ?? "")」？已扫描的视频会被隐藏，可通过重新添加恢复。",
                confirmLabel: "删除",
                destructive: true,
                isPresented: $showDelete
            ) {
                if let target = deleteTarget {
                    vm.delete(target)
                }
            }
        }
    }
}

struct DirectoryRow: View {
    let dir: Directory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.orange)
                Text(dir.path)
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer()
                if dir.enabled == false {
                    Text("停用")
                        .font(.system(size: 10))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.gray.opacity(0.5), in: Capsule())
                }
            }
            HStack(spacing: 10) {
                Text("视频 \(dir.scannedVideoCount ?? 0)")
                Text("作品 \(dir.scrapedVideoCount ?? 0)")
                if dir.autoScanEnabled == true {
                    Text("自动扫描")
                        .foregroundStyle(.green)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            if dir.isScanning == true {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("扫描中… 已扫描 \(dir.scannedFileCount ?? 0) 个文件")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct DirectoryCreateView: View {
    let onCreated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var path = ""
    @State private var errorMessage: String?
    @State private var showBrowser = false
    @State private var creating = false

    var body: some View {
        NavigationStack {
            Form {
                Section("目录路径（服务器本机绝对路径）") {
                    TextField("/data/media/...", text: $path)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button {
                        showBrowser = true
                    } label: {
                        Label("浏览服务器文件系统", systemImage: "folder.badge.gearshape")
                    }
                }
            }
            .navigationTitle("添加目录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        creating = true
                        Task {
                            do {
                                _ = try await Repository(api: AppState.shared.api).createDirectory(path: path)
                                onCreated()
                                dismiss()
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                            creating = false
                        }
                    }
                    .disabled(creating || path.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showBrowser) {
                DirectoryBrowserView { selected in
                    path = selected
                    showBrowser = false
                }
            }
            .errorAlert(errorMessage) { errorMessage = nil }
        }
    }
}

struct DirectoryEditView: View {
    let directory: Directory
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var path = ""
    @State private var enabled = true
    @State private var autoScanEnabled = false
    @State private var autoScanInterval = ""
    @State private var errorMessage: String?
    @State private var busy = false
    @State private var showBrowser = false

    var body: some View {
        NavigationStack {
            Form {
                Section("路径") {
                    TextField("路径", text: $path)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button {
                        showBrowser = true
                    } label: {
                        Label("浏览服务器文件系统", systemImage: "folder.badge.gearshape")
                    }
                }
                Section("状态") {
                    Toggle("启用", isOn: $enabled)
                    Toggle("自动扫描", isOn: $autoScanEnabled)
                    TextField("扫描周期（分钟）", text: $autoScanInterval)
                        .keyboardType(.numberPad)
                }
                Section("操作") {
                    Button("立即扫描") {
                        busy = true
                        Task {
                            do {
                                try await Repository(api: AppState.shared.api).scanDirectory(id: directory.id)
                                onSaved()
                                dismiss()
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                            busy = false
                        }
                    }
                    Button("立即处理（刮削关联）") {
                        busy = true
                        Task {
                            do {
                                try await Repository(api: AppState.shared.api).processDirectory(id: directory.id)
                                onSaved()
                                dismiss()
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                            busy = false
                        }
                    }
                }
            }
            .navigationTitle("目录设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        busy = true
                        Task {
                            do {
                                try await Repository(api: AppState.shared.api).updateDirectory(
                                    id: directory.id,
                                    request: DirectoryUpdateRequest(
                                        path: path,
                                        enabled: enabled,
                                        autoScanEnabled: autoScanEnabled,
                                        autoScanIntervalMinutes: Int(autoScanInterval)))
                                onSaved()
                                dismiss()
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                            busy = false
                        }
                    }
                    .disabled(busy)
                }
            }
            .sheet(isPresented: $showBrowser) {
                DirectoryBrowserView { selected in
                    path = selected
                    showBrowser = false
                }
            }
            .onAppear {
                path = directory.path
                enabled = directory.enabled ?? true
                autoScanEnabled = directory.autoScanEnabled ?? false
                autoScanInterval = directory.autoScanIntervalMinutes.map(String.init) ?? ""
            }
            .errorAlert(errorMessage) { errorMessage = nil }
        }
    }
}

// MARK: - 服务器文件系统浏览

@MainActor
final class DirectoryBrowserVM: ObservableObject {
    @Published var response: DirectoryBrowseResponse?
    @Published var loading = true
    @Published var errorMessage: String?
    @Published var pathStack: [String] = []

    func load(path: String? = nil) async {
        loading = true
        do {
            let res = try await Repository(api: AppState.shared.api)
                .browseDirectories(path: path ?? "")
            if path == nil {
                pathStack = []
            }
            response = res
        } catch let error as ApiError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }

    func navigate(_ path: String) async {
        pathStack.append(response?.path ?? "")
        await load(path: path)
    }

    func goBack() async {
        let previous = pathStack.popLast()
        await load(path: previous)
    }
}

struct DirectoryBrowserView: View {
    let onPick: (String) -> Void

    @StateObject private var vm = DirectoryBrowserVM()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("快捷入口") {
                    ForEach(vm.response?.roots ?? [], id: \.path) { root in
                        Button {
                            Task { await vm.navigate(root.path) }
                        } label: {
                            Label(root.path, systemImage: "externaldrive")
                        }
                    }
                    if let home = vm.response?.home, !home.isEmpty {
                        Button {
                            Task { await vm.navigate(home) }
                        } label: {
                            Label("用户目录 \(home)", systemImage: "house")
                        }
                    }
                }
                Section("当前：\(vm.response?.path ?? "")") {
                    if let parent = vm.response?.parent, !parent.isEmpty {
                        Button {
                            Task { await vm.goBack() }
                        } label: {
                            Label("..", systemImage: "arrow.up")
                        }
                    }
                    ForEach(vm.response?.directories ?? [], id: \.path) { dir in
                        Button {
                            Task { await vm.navigate(dir.path) }
                        } label: {
                            Label(dir.name, systemImage: "folder")
                        }
                    }
                    if (vm.response?.directories ?? []).isEmpty && vm.response != nil {
                        Text("无子目录")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("浏览服务器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("选择此目录") {
                        if let path = vm.response?.path {
                            onPick(path)
                        }
                    }
                }
            }
            .task { await vm.load() }
            .errorAlert(vm.errorMessage) { vm.errorMessage = nil }
        }
    }
}
