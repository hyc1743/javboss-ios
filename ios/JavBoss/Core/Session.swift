import Foundation

/// 会话持久化：服务器地址 + 登录 Cookie（对齐 Android 端语义）。
final class Session: ObservableObject {
    private let defaults = UserDefaults.standard
    private let keychain = KeychainStore()
    private let keyServerUrl = "session_server_url"
    private let keyCookie = "session_cookie_header"

    @Published var serverUrl: String = ""
    @Published var cookieHeader: String = ""

    var hasSession: Bool { !serverUrl.isEmpty && !cookieHeader.isEmpty }

    init() {
        restore()
    }

    func restore() {
        serverUrl = defaults.string(forKey: keyServerUrl) ?? ""
        if let cookie = keychain.string(forKey: keyCookie) {
            cookieHeader = cookie
        } else if let legacyCookie = defaults.string(forKey: keyCookie), !legacyCookie.isEmpty {
            // One-time migration from the old UserDefaults storage.
            cookieHeader = legacyCookie
            keychain.set(legacyCookie, forKey: keyCookie)
            defaults.removeObject(forKey: keyCookie)
        } else {
            cookieHeader = ""
        }
    }

    /// 规范化：去掉末尾斜杠，无协议头时自动补 http://
    func normalizedServerUrl(_ input: String) -> String {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        if !value.isEmpty, !value.hasPrefix("http://"), !value.hasPrefix("https://") {
            value = "http://" + value
        }
        return value
    }

    func saveServerUrl(_ url: String) {
        serverUrl = normalizedServerUrl(url)
        defaults.set(serverUrl, forKey: keyServerUrl)
    }

    func saveCookie(_ header: String) {
        cookieHeader = header
        if header.isEmpty {
            keychain.remove(forKey: keyCookie)
        } else {
            keychain.set(header, forKey: keyCookie)
        }
    }

    func clear() {
        serverUrl = ""
        cookieHeader = ""
        defaults.removeObject(forKey: keyServerUrl)
        defaults.removeObject(forKey: keyCookie)
        keychain.remove(forKey: keyCookie)
    }
}
