import Foundation

/// 极简 CookieJar：内存保存当前 JavBoss 服务端的会话 Cookie，并持久化 Cookie 头。
/// 仅允许同源（scheme/host/port 一致）请求携带会话，绝不可泄漏到外部地址。
final class CookieJar {
    private let session: Session
    private var store: [String: String] = [:]

    init(session: Session) {
        self.session = session
    }

    func restoreFromSession() {
        guard !session.cookieHeader.isEmpty else { return }
        for pair in session.cookieHeader.components(separatedBy: "; ") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                store[String(parts[0])] = String(parts[1])
            }
        }
    }

    func cookieHeader() -> String {
        return store.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
    }

    /// 仅当目标地址与当前服务端同源时返回 Cookie 头
    func cookieHeader(for url: URL) -> String? {
        guard sameOrigin(url) else { return nil }
        let header = cookieHeader()
        return header.isEmpty ? nil : header
    }

    func clear() {
        store.removeAll()
        session.saveCookie("")
    }

    /// 从响应头解析 Set-Cookie 并保存（仅同源响应）
    func storeCookies(from response: HTTPURLResponse, for url: URL) {
        guard sameOrigin(url) else { return }
        guard let headers = response.allHeaderFields as? [String: String] else { return }
        var changed = false
        // allHeaderFields 会把多个 Set-Cookie 合并成一个以逗号分隔的字符串，
        // 需要按 "; name=" 的方式重新切分
        var setCookies: [String] = []
        for (key, value) in headers where key.lowercased() == "set-cookie" {
            // 用启发式切分：", " 后面跟 "名字=" 的视为新 cookie
            var current = ""
            for segment in value.components(separatedBy: ", ") {
                if segment.range(of: "^\\s*[A-Za-z0-9_-]+=", options: .regularExpression) != nil {
                    if !current.isEmpty { setCookies.append(current) }
                    current = segment
                } else {
                    current += current.isEmpty ? segment : ", " + segment
                }
            }
            if !current.isEmpty { setCookies.append(current) }
        }
        for raw in setCookies {
            let firstPart = raw.components(separatedBy: ";").first ?? ""
            let pair = firstPart.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else { continue }
            let name = String(pair[0]).trimmingCharacters(in: .whitespaces)
            let value = String(pair[1]).trimmingCharacters(in: .whitespaces)
            let lower = raw.lowercased()
            if lower.contains("max-age=0") || lower.contains("expires=thu, 01 jan 1970") {
                if store.removeValue(forKey: name) != nil { changed = true }
            } else if !value.isEmpty {
                store[name] = value
                changed = true
            }
        }
        if changed {
            session.saveCookie(cookieHeader())
        }
    }

    /// 同源校验：scheme + host + port 完全一致
    func sameOrigin(_ url: URL) -> Bool {
        guard let server = URL(string: session.serverUrl), let scheme = url.scheme, let host = url.host else {
            return false
        }
        guard server.scheme == scheme, server.host == host else { return false }
        let serverPort = server.port ?? defaultPort(for: server.scheme)
        let urlPort = url.port ?? defaultPort(for: scheme)
        return serverPort == urlPort
    }

    private func defaultPort(for scheme: String?) -> Int {
        scheme == "https" ? 443 : 80
    }
}
