import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var appState: AppState

    @State private var serverUrl = ""
    @State private var password = ""
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var showHelp = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "film.stack")
                    .font(.system(size: 64))
                    .foregroundStyle(Color(red: 0.95, green: 0.55, blue: 0.25))
                Text("JavBoss")
                    .font(.largeTitle.bold())
                Text("连接自托管 JavBoss 服务端")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    TextField("服务器地址（如 192.168.1.100:8080）", text: $serverUrl)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    SecureField("密码", text: $password)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal, 32)

                Button {
                    Task { await login() }
                } label: {
                    Group {
                        if busy {
                            ProgressView().tint(.white)
                        } else {
                            Text("登录")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.95, green: 0.55, blue: 0.25))
                .padding(.horizontal, 32)
                .disabled(busy || serverUrl.trimmingCharacters(in: .whitespaces).isEmpty)

                Button("使用说明") { showHelp = true }
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer()
                Text("本项目与 JavBoss 官方无关，仅调用其自托管服务端的 HTTP API")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 8)
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showHelp) {
                LoginHelpView()
            }
            .errorAlert(errorMessage) { errorMessage = nil }
        }
    }

    private func login() async {
        busy = true
        defer { busy = false }
        do {
            try await Repository(api: AppState.shared.api).login(serverUrl: serverUrl, password: password)
            AppState.shared.loggedIn = true
        } catch {
            errorMessage = (error as? ApiError)?.localizedDescription ?? error.localizedDescription
        }
    }
}

struct LoginHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("服务端准备") {
                    Text("在电脑上运行 JavBoss（v1.9.0+），进入「全局设置」开启「允许局域网访问」，按提示重启。")
                    Text("旧版本可在启动参数中加入允许局域网访问的开关（见上游 README）。")
                }
                Section("连接") {
                    Text("填写运行 JavBoss 电脑的局域网 IP 与端口（如 192.168.1.100:8080），以及你设置的密码。")
                    Text("端口默认 8080。首次启动若弹出 Windows 防火墙提示，勾选「专用网络」并允许访问。")
                }
                Section("安全") {
                    Text("会话 Cookie 仅发送给当前配置的同源服务器，不会泄漏给外部地址。")
                }
            }
            .navigationTitle("使用说明")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
