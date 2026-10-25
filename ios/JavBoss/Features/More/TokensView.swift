import SwiftUI

/// 扩展 API 令牌（浏览器扩展用）
@MainActor
final class TokensVM: ObservableObject {
    @Published var tokens: [ExtensionToken] = []
    @Published var loading = true
    @Published var errorMessage: String?
    @Published var reveal: String?

    func load() async {
        loading = true
        do {
            tokens = try await Repository(api: AppState.shared.api).listExtensionTokens()
        } catch let error as ApiError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }

    func clearError() { errorMessage = nil }

    func create(name: String, expiresInDays: Int?) async throws -> String {
        let res = try await Repository(api: AppState.shared.api).createExtensionToken(name: name, expiresInDays: expiresInDays)
        await load()
        return res.token
    }

    func rotate(_ token: ExtensionToken) async throws -> String {
        let res = try await Repository(api: AppState.shared.api).rotateExtensionToken(id: token.id)
        await load()
        return res.token
    }

    func delete(_ token: ExtensionToken) async throws {
        try await Repository(api: AppState.shared.api).deleteExtensionToken(id: token.id)
        await load()
    }
}

struct TokensView: View {
    @StateObject private var vm = TokensVM()
    @State private var showCreate = false
    @State private var deleteTarget: ExtensionToken?
    @State private var showDelete = false
    @State private var rotateTarget: ExtensionToken?
    @State private var showRotate = false

    var body: some View {
        Group {
            if vm.loading && vm.tokens.isEmpty {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.tokens.isEmpty {
                EmptyPlaceholder(icon: "key", text: "暂无令牌")
            } else {
                List {
                    ForEach(vm.tokens) { token in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(token.name)
                                    .font(.subheadline)
                                Text(expiryText(token))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                if let lastUsed = token.lastUsedAt, !lastUsed.isEmpty {
                                    Text("最近使用：\(Fmt.dateTime(lastUsed))")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                            if token.token != nil && !(token.token?.isEmpty ?? true) {
                                Button("复制") {
                                    UIPasteboard.general.string = token.token
                                }
                                .font(.caption)
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleteTarget = token
                                showDelete = true
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button {
                                rotateTarget = token
                                showRotate = true
                            } label: {
                                Label("轮换", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .tint(.blue)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(Color(white: 0.09))
        .navigationTitle("扩展 API 令牌")
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
        .task { await vm.load() }
        .errorAlert(vm.errorMessage) { vm.clearError() }
        .sheet(isPresented: $showCreate) {
            TokenCreateSheet { name, days in
                do {
                    let token = try await vm.create(name: name, expiresInDays: days)
                    vm.reveal = token
                } catch {
                    vm.errorMessage = error.localizedDescription
                }
            }
        }
        .confirmDialog(
            title: "删除令牌",
            message: "删除令牌「\(deleteTarget?.name ?? "")」？使用该令牌的扩展将无法连接。",
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
        .confirmDialog(
            title: "轮换令牌",
            message: "轮换「\(rotateTarget?.name ?? "")」？旧令牌将立即失效。",
            confirmLabel: "轮换",
            destructive: true,
            isPresented: $showRotate
        ) {
            guard let target = rotateTarget else { return }
            Task {
                do {
                    let token = try await vm.rotate(target)
                    vm.reveal = token
                } catch {
                    vm.errorMessage = error.localizedDescription
                }
            }
        }
        .alert("新令牌", isPresented: Binding(
            get: { vm.reveal != nil },
            set: { if !$0 { vm.reveal = nil } }
        )) {
            Button("复制") {
                UIPasteboard.general.string = vm.reveal ?? ""
            }
            Button("关闭", role: .cancel) {}
        } message: {
            Text(vm.reveal ?? "")
        }
    }

    private func expiryText(_ token: ExtensionToken) -> String {
        guard let expires = token.expiresAt, !expires.isEmpty else { return "永不过期" }
        if Fmt.parseISO(expires) != nil {
            return "过期时间：\(Fmt.dateTime(expires))"
        }
        // 服务端 time.Time 零值 = 永不过期
        if expires.hasPrefix("0001") { return "永不过期" }
        return "过期时间：\(expires)"
    }
}

struct TokenCreateSheet: View {
    let onCreate: (String, Int?) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var days = ""
    @State private var busy = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("令牌信息") {
                    TextField("名称", text: $name)
                    TextField("有效期天数（0 = 永不过期，默认 365）", text: $days)
                        .keyboardType(.numberPad)
                }
                Section {
                    Button("创建") {
                        busy = true
                        Task {
                            do {
                                try await onCreate(name, Int(days))
                                dismiss()
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                            busy = false
                        }
                    }
                    .disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("新建令牌")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .errorAlert(errorMessage) { errorMessage = nil }
        }
    }
}
