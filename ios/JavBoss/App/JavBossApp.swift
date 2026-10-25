import SwiftUI
import UIKit

@main
struct JavBossApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(appState.session)
                .preferredColorScheme(.dark)
                .tint(Color(red: 0.95, green: 0.55, blue: 0.25))
        }
    }
}

/// 全局应用状态：会话 + API 客户端，所有页面通过 environmentObject 访问。
final class AppState: ObservableObject {
    static let shared = AppState()

    let session = Session()
    let cookieJar: CookieJar
    let api: APIClient

    /// 当前是否已登录（由 RootView 监听）
    @Published var loggedIn = false

    private init() {
        session.restore()
        cookieJar = CookieJar(session: session)
        cookieJar.restoreFromSession()
        api = APIClient(session: session, cookieJar: cookieJar)
        loggedIn = session.hasSession
    }

    /// 启动校验本地会话是否仍有效
    @MainActor
    func verifySession() async {
        guard session.hasSession else {
            loggedIn = false
            return
        }
        do {
            let status: AuthStatusResponse = try await api.get("auth/status")
            loggedIn = status.authenticated
            if !status.authenticated {
                session.clear()
                cookieJar.clear()
            }
        } catch {
            // 服务器不可达时不强制登出，保留本地会话以便恢复
            if case ApiError.authExpired = error {
                session.clear()
                cookieJar.clear()
                loggedIn = false
            } else {
                loggedIn = true
            }
        }
    }

    @MainActor
    func logout() async {
        try? await api.postVoid("auth/logout")
        session.clear()
        cookieJar.clear()
        loggedIn = false
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindowScene?
    ) -> UIInterfaceOrientationMask {
        return OrientationLock.shared.isPlayerActive ? .landscape : .portrait
    }
}

/// 播放页进入时锁定横屏，退出恢复竖屏。
final class OrientationLock: ObservableObject {
    static let shared = OrientationLock()
    @Published var isPlayerActive = false

    private init() {}

    func enterPlayer() {
        isPlayerActive = true
        setNeedsUpdate()
    }

    func exitPlayer() {
        isPlayerActive = false
        setNeedsUpdate()
    }

    private func setNeedsUpdate() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            UIViewController.attemptRotationToDeviceOrientation()
            if #available(iOS 16.0, *), let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                let orientation: UIInterfaceOrientationMask = self.isPlayerActive ? .landscape : .portrait
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation))
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.loggedIn {
                MainTabsView()
            } else {
                LoginView()
            }
        }
        .task {
            if appState.loggedIn {
                await appState.verifySession()
            }
        }
        .animation(.default, value: appState.loggedIn)
    }
}
