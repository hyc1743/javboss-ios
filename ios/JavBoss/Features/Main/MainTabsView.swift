import SwiftUI

struct MainTabsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selection = 0
    @State private var showLogoutConfirm = false

    var body: some View {
        TabView(selection: $selection) {
            VideosView()
                .tabItem { Label("视频", systemImage: "play.rectangle") }
                .tag(0)

            WorksView()
                .tabItem { Label("作品", systemImage: "square.grid.2x2") }
                .tag(1)

            FavoritesView()
                .tabItem { Label("收藏", systemImage: "heart") }
                .tag(2)

            DirectoriesView()
                .tabItem { Label("目录", systemImage: "folder") }
                .tag(3)

            MoreView()
                .tabItem { Label("更多", systemImage: "ellipsis.circle") }
                .tag(4)
        }
        .tint(Color(red: 0.95, green: 0.55, blue: 0.25))
        .confirmDialog(
            title: "退出登录",
            message: "确定要退出当前服务器吗？本地会话将被清除。",
            confirmLabel: "退出",
            destructive: true,
            isPresented: $showLogoutConfirm
        ) {
            Task { await appState.logout() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .logoutRequested)) { _ in
            showLogoutConfirm = true
        }
    }
}

extension Notification.Name {
    static let logoutRequested = Notification.Name("javboss.logoutRequested")
}
