import SwiftUI

@MainActor
final class DownloadsVM: ObservableObject {
    @Published var jobs: [DownloadJob] = []
    @Published var counts: DownloadJobCounts?
    @Published var total: Int64 = 0
    @Published var loading = true
    @Published var loadingMore = false
    @Published var errorMessage: String?
    @Published var busyLabel: String?

    private let pageSize = 50

    func load() async {
        loading = true
        do {
            let page = try await Repository(api: AppState.shared.api).listDownloadJobs(limit: pageSize, offset: 0)
            jobs = page.items
            total = page.total ?? 0
            counts = page.counts
        } catch let error as ApiError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }

    func loadMore() async {
        guard jobs.count < total, !loadingMore else { return }
        loadingMore = true
        do {
            let page = try await Repository(api: AppState.shared.api).listDownloadJobs(limit: pageSize, offset: jobs.count)
            jobs.append(contentsOf: page.items)
        } catch {
            errorMessage = error.localizedDescription
        }
        loadingMore = false
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
}

struct DownloadsView: View {
    @StateObject private var vm = DownloadsVM()
    @State private var showCreate = false
    @State private var showSettings = false
    @State private var deleteTarget: DownloadJob?
    @State private var showDelete = false

    var body: some View {
        NavigationStack {
            Group {
                if vm.loading && vm.jobs.isEmpty {
                    Spacer()
                    ProgressView("加载中…")
                    Spacer()
                } else if vm.jobs.isEmpty {
                    EmptyPlaceholder(icon: "arrow.down.circle", text: "暂无下载任务")
                } else {
                    List {
                        ForEach(vm.jobs) { job in
                            DownloadJobRow(job: job, vm: vm)
                                .onAppear {
                                    Task { await vm.loadMore() }
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        deleteTarget = job
                                        showDelete = true
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                        }
                        if vm.loadingMore {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("下载")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
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
                CreateDownloadJobView {
                    Task { await vm.load() }
                }
            }
            .sheet(isPresented: $showSettings) {
                DownloaderSettingsView()
            }
            .confirmDialog(
                title: "删除下载任务",
                message: "确定删除任务「\(deleteTarget?.magnetName ?? "")」？",
                confirmLabel: "删除",
                destructive: true,
                isPresented: $showDelete
            ) {
                if let target = deleteTarget {
                    vm.perform("删除任务") {
                        try await Repository(api: AppState.shared.api).deleteDownloadJob(id: target.id)
                    }
                }
            }
        }
    }
}

struct DownloadJobRow: View {
    let job: DownloadJob
    @ObservedObject var vm: DownloadsVM

    private var progress: Double {
        guard let total = job.bytesTotal, total > 0 else { return 0 }
        return Double(job.bytesDownloaded ?? 0) / Double(total)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(job.magnetName?.isEmpty == false ? job.magnetName! : "下载任务 #\(job.id)")
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer()
                statusBadge
            }
            if job.status == "downloading" || job.status == "active" || job.status == "queued" {
                ProgressView(value: progress)
                HStack {
                    Text("\(Fmt.bytes(job.bytesDownloaded ?? 0)) / \(Fmt.bytes(job.bytesTotal ?? 0))")
                    Spacer()
                    if job.status != "queued" {
                        Button("取消") {
                            vm.perform("取消任务") {
                                try await Repository(api: AppState.shared.api).cancelDownloadJob(id: job.id)
                            }
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            if job.status == "failed", let error = job.errorMessage, !error.isEmpty {
                HStack(spacing: 8) {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                    Spacer()
                    Button("重试") {
                        vm.perform("重试任务") {
                            try await Repository(api: AppState.shared.api).retryDownloadJob(id: job.id)
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch job.status {
        case "completed":
            Text("完成")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.green.opacity(0.7), in: Capsule())
        case "failed":
            Text("失败")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.red.opacity(0.7), in: Capsule())
        case "downloading", "active":
            Text("下载中")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.blue.opacity(0.7), in: Capsule())
        default:
            Text(job.status ?? "queued")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.gray.opacity(0.5), in: Capsule())
        }
    }
}

struct CreateDownloadJobView: View {
    let onCreated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var magnetUrl = ""
    @State private var errorMessage: String?
    @State private var creating = false

    var body: some View {
        NavigationStack {
            Form {
                Section("磁力链接") {
                    TextField("magnet:?xt=urn:btih:...", text: $magnetUrl)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .lineLimit(3)
                }
            }
            .navigationTitle("新建下载")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        creating = true
                        Task {
                            do {
                                try await Repository(api: AppState.shared.api).createDownloadJob(magnetUrl: magnetUrl)
                                onCreated()
                                dismiss()
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                            creating = false
                        }
                    }
                    .disabled(creating || !magnetUrl.hasPrefix("magnet:"))
                }
            }
            .errorAlert(errorMessage) { errorMessage = nil }
        }
    }
}

// MARK: - 下载器设置

@MainActor
final class DownloaderSettingsVM: ObservableObject {
    @Published var settings: DownloaderSettings?
    @Published var loading = true
    @Published var errorMessage: String?
    @Published var message: String?

    var downloadDirectory = ""
    var localConcurrency = ""
    var minVideoSizeMb = ""
    var address = ""
    var apiToken = ""
    var remoteFolder = ""

    func load() async {
        loading = true
        do {
            settings = try await Repository(api: AppState.shared.api).downloaderSettings()
            if let s = settings {
                downloadDirectory = s.downloadDirectory
                localConcurrency = String(s.localConcurrency)
                minVideoSizeMb = String(s.minVideoSizeMb)
                address = s.address
                remoteFolder = s.remoteFolder
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }

    func saveLocal() async throws {
        try await Repository(api: AppState.shared.api).updateDownloaderSettings(
            request: DownloaderSettingsRequest(
                downloadDirectory: downloadDirectory,
                localConcurrency: Int(localConcurrency),
                minVideoSizeMb: Int64(minVideoSizeMb)))
    }

    func saveCloudDrive2() async throws {
        try await Repository(api: AppState.shared.api).updateCloudDrive2Settings(
            request: CloudDrive2SettingsRequest(
                address: address,
                apiToken: apiToken.isEmpty ? nil : apiToken,
                remoteFolder: remoteFolder))
    }

    func testCloudDrive2() async throws -> CloudDrive2TestResponse {
        try await Repository(api: AppState.shared.api).testCloudDrive2()
    }
}

struct DownloaderSettingsView: View {
    @StateObject private var vm = DownloaderSettingsVM()
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section("本地下载") {
                    TextField("下载目录", text: $vm.downloadDirectory)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("并发数", text: $vm.localConcurrency)
                        .keyboardType(.numberPad)
                    TextField("最小视频大小 MB", text: $vm.minVideoSizeMb)
                        .keyboardType(.numberPad)
                    Button("保存本地设置") {
                        busy = true
                        Task {
                            do {
                                try await vm.saveLocal()
                                vm.message = "已保存"
                            } catch {
                                vm.errorMessage = error.localizedDescription
                            }
                            busy = false
                        }
                    }
                    .disabled(busy)
                }
                Section("CloudDrive2 云下载") {
                    TextField("地址", text: $vm.address)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField(vm.settings?.tokenConfigured == true ? "API Token（已配置，留空不变）" : "API Token", text: $vm.apiToken)
                    TextField("云端离线目录", text: $vm.remoteFolder)
                        .autocorrectionDisabled()
                    Button("保存云端设置") {
                        busy = true
                        Task {
                            do {
                                try await vm.saveCloudDrive2()
                                vm.message = "已保存"
                            } catch {
                                vm.errorMessage = error.localizedDescription
                            }
                            busy = false
                        }
                    }
                    .disabled(busy)
                    Button("测试连接") {
                        busy = true
                        Task {
                            do {
                                let result = try await vm.testCloudDrive2()
                                vm.message = result.message ?? (result.ok == true ? "连接成功" : "连接失败")
                            } catch {
                                vm.errorMessage = error.localizedDescription
                            }
                            busy = false
                        }
                    }
                    .disabled(busy)
                }
            }
            .navigationTitle("下载器设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task { await vm.load() }
            .errorAlert(vm.errorMessage) { vm.errorMessage = nil }
            .alert("提示", isPresented: Binding(
                get: { vm.message != nil },
                set: { if !$0 { vm.message = nil } }
            )) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(vm.message ?? "")
            }
        }
    }
}
