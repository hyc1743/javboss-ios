import SwiftUI

// MARK: - 修改密码

struct PasswordChangeView: View {
    @State private var current = ""
    @State private var newPassword = ""
    @State private var confirm = ""
    @State private var busy = false
    @State private var message: String?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("密码规则：6-20 个字符，首尾不能有空格") {
                SecureField("当前密码", text: $current)
                SecureField("新密码", text: $newPassword)
                SecureField("确认新密码", text: $confirm)
            }
            Section {
                Button("修改密码") {
                    guard newPassword == confirm else {
                        errorMessage = "两次输入的新密码不一致"
                        return
                    }
                    busy = true
                    Task {
                        do {
                            try await Repository(api: AppState.shared.api)
                                .changePassword(current: current, new: newPassword)
                            message = "密码已修改"
                            current = ""
                            newPassword = ""
                            confirm = ""
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                        busy = false
                    }
                }
                .disabled(busy || current.isEmpty || newPassword.isEmpty)
            }
        }
        .navigationTitle("修改密码")
        .navigationBarTitleDisplayMode(.inline)
        .errorAlert(errorMessage) { errorMessage = nil }
        .alert("提示", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }
}

// MARK: - 服务器设置与状态

@MainActor
final class SettingsVM: ObservableObject {
    @Published var resources: ResourcesSnapshot?
    @Published var tools: ToolsResponse?
    @Published var providers: [AvailabilityProvider] = []
    @Published var config: [String: Any] = [:]
    @Published var configText = ""
    @Published var loading = false
    @Published var errorMessage: String?
    @Published var message: String?
    @Published var busyProvider: String?

    func loadAll() async {
        loading = true
        let repo = Repository(api: AppState.shared.api)
        do {
            resources = try await repo.getResources()
        } catch { resources = nil }
        do {
            tools = try await repo.getTools()
        } catch { tools = nil }
        do {
            providers = try await repo.listProviders()
        } catch { providers = [] }
        do {
            config = try await repo.getConfig()
            if let data = try? JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys]),
               let text = String(data: data, encoding: .utf8) {
                configText = text
            }
        } catch { config = [:] }
        loading = false
    }

    func checkProvider(_ provider: AvailabilityProvider) {
        busyProvider = provider.id
        Task {
            defer { busyProvider = nil }
            do {
                _ = try await Repository(api: AppState.shared.api).checkProvider(provider.id)
                providers = (try? await Repository(api: AppState.shared.api).listProviders()) ?? providers
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func downloadFFmpeg() {
        Task {
            do {
                _ = try await Repository(api: AppState.shared.api).downloadFFmpeg()
                tools = try await Repository(api: AppState.shared.api).getTools()
                message = "已触发下载"
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func setLanAccess(_ enabled: Bool) {
        Task {
            do {
                try await Repository(api: AppState.shared.api).updateConfig(allowLanAccess: enabled)
                message = "已更新"
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct SettingsView: View {
    @StateObject private var vm = SettingsVM()

    var body: some View {
        List {
            Section("局域网访问") {
                if let lan = vm.config["allow_lan_access"] as? Bool {
                    Toggle("允许局域网访问", isOn: Binding(
                        get: { lan },
                        set: { vm.setLanAccess($0) }
                    ))
                } else {
                    Text("配置未加载")
                        .foregroundStyle(.secondary)
                }
            }

            Section("系统资源") {
                if let res = vm.resources {
                    if let os = res.os {
                        LabeledContent("系统", value: "\(os) · \(res.logicalCpus ?? 0) 核")
                    }
                    if let cpu = res.process?.cpuPercent {
                        LabeledContent("进程 CPU", value: String(format: "%.1f%%", cpu))
                    }
                    if let sysCpu = res.systemCpuPercent {
                        LabeledContent("系统 CPU", value: String(format: "%.1f%%", sysCpu))
                    }
                    if let mem = res.systemMemory {
                        LabeledContent("内存", value: "\(Fmt.bytes(Int64(mem.usedBytes ?? 0)))/\(Fmt.bytes(Int64(mem.totalBytes ?? 0))) (\(String(format: "%.0f", mem.usedPercent ?? 0))%)")
                    }
                    if let disk = res.dataDisk {
                        LabeledContent("数据盘", value: "\(Fmt.bytes(Int64(disk.freeBytes ?? 0))) 可用 (\(String(format: "%.0f", disk.usedPercent ?? 0))%)")
                    }
                    if let up = res.process?.uptimeSeconds {
                        LabeledContent("运行时长", value: Fmt.duration(up))
                    }
                } else if !vm.loading {
                    Text("资源信息不可用")
                        .foregroundStyle(.secondary)
                }
            }

            Section("FFmpeg 工具") {
                if let ffmpeg = vm.tools?.ffmpeg {
                    LabeledContent("状态", value: ffmpeg.installed == true ? "已安装" : "未安装")
                    if let version = ffmpeg.version, !version.isEmpty {
                        LabeledContent("版本", value: version)
                    }
                    if ffmpeg.installed == false {
                        Button("下载 FFmpeg（服务端转码需要）") {
                            vm.downloadFFmpeg()
                        }
                    } else if ffmpeg.upgradeAvailable == true {
                        Button("升级 FFmpeg") {
                            vm.downloadFFmpeg()
                        }
                    }
                } else if !vm.loading {
                    Text("工具服务不可用")
                        .foregroundStyle(.secondary)
                }
            }

            Section("数据源可用性") {
                ForEach(vm.providers) { provider in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.name ?? provider.id)
                                .font(.subheadline)
                            if let domain = provider.domain, !domain.isEmpty {
                                Text(domain)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if vm.busyProvider == provider.id {
                            ProgressView()
                                .controlSize(.small)
                        } else if let result = provider.lastResult {
                            HStack(spacing: 4) {
                                Text(result.status ?? "?")
                                if let elapsed = result.elapsedMs {
                                    Text("\(elapsed)ms")
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(result.status == "ok" ? .green : .red)
                            .onTapGesture {
                                vm.checkProvider(provider)
                            }
                        } else {
                            Button("检测") {
                                vm.checkProvider(provider)
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                    }
                }
                if vm.providers.isEmpty && !vm.loading {
                    Text("暂无数据源")
                        .foregroundStyle(.secondary)
                }
            }

            Section("服务器配置（只读摘要）") {
                NavigationLink {
                    ScrollView {
                        Text(vm.configText.isEmpty ? "未加载" : vm.configText)
                            .font(.caption.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .navigationTitle("服务器配置")
                    .navigationBarTitleDisplayMode(.inline)
                } label: {
                    Label("查看完整配置 JSON", systemImage: "doc.text")
                }
            }
        }
        .navigationTitle("服务器")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await vm.loadAll() }
        .task { await vm.loadAll() }
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
