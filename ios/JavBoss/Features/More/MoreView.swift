import SwiftUI

struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("库管理") {
                    NavigationLink {
                        TagsView()
                    } label: {
                        Label("标签管理", systemImage: "tag")
                    }
                    NavigationLink {
                        TokensView()
                    } label: {
                        Label("扩展 API 令牌", systemImage: "key")
                    }
                }
                Section("服务器") {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("服务器设置与状态", systemImage: "gearshape.2")
                    }
                    NavigationLink {
                        DownloadsView()
                    } label: {
                        Label("下载器", systemImage: "arrow.down.circle")
                    }
                }
                Section("账户") {
                    NavigationLink {
                        PasswordChangeView()
                    } label: {
                        Label("修改密码", systemImage: "lock.rotation")
                    }
                    Button {
                        NotificationCenter.default.post(name: .logoutRequested, object: nil)
                    } label: {
                        Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                            .foregroundStyle(.red)
                    }
                }
                Section("关于") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("JavBoss iOS")
                            .font(.headline)
                        Text("版本 0.1.0")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("上游 JavBoss 服务端的第三方 iOS 客户端，调用其自托管 HTTP API。\n上游项目：github.com/Solr159/JavBoss\n本项目与上游官方无关。")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("更多")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
