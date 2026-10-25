import Foundation

enum ApiError: Error, LocalizedError {
    case authExpired
    case http(status: Int, message: String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .authExpired:
            return "登录状态已失效"
        case .http(_, let message):
            return message
        case .network(let message):
            return message
        }
    }
}

struct EmptyResponse: Decodable {}

/// 网络客户端：服务器地址由用户输入、运行时可变；
/// 手动管理 Cookie（禁用系统 Cookie 存储，保证 Set-Cookie 可见且仅同源注入）。
final class APIClient {
    let session: Session
    let cookieJar: CookieJar

    let urlSession: URLSession

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    init(session: Session, cookieJar: CookieJar) {
        self.session = session
        self.cookieJar = cookieJar
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpCookieStorage = nil
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        urlSession = URLSession(configuration: config)
    }

    // MARK: - URL 构造

    func baseUrl() -> URL? {
        URL(string: session.serverUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    /// 拼接 API 地址
    func apiUrl(_ path: String, query: [URLQueryItem] = []) -> URL? {
        guard var comps = URLComponents(string: session.serverUrl + "/" + path) else { return nil }
        if !query.isEmpty {
            comps.queryItems = query.filter { $0.value != nil && !$0.value!.isEmpty }
        }
        return comps.url
    }

    /// 资源绝对地址：相对路径补全；绝对地址必须同源
    func absoluteUrl(_ pathOrUrl: String) -> String? {
        let trimmed = pathOrUrl.trimmingCharacters(in: .whitespaces)
        let urlString: String
        if trimmed.contains("://") {
            urlString = trimmed
        } else {
            urlString = session.serverUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                + "/" + trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        guard let url = URL(string: urlString), cookieJar.sameOrigin(url) else { return nil }
        return urlString
    }

    func videoThumbnailUrl(videoId: Int64) -> String? { absoluteUrl("videos/\(videoId)/thumbnail") }
    func javCoverUrl(code: String) -> String? { absoluteUrl("jav/\(code)/cover") }
    func videoScreenshotUrl(videoId: Int64, name: String) -> String? {
        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return absoluteUrl("videos/\(videoId)/screenshots/\(encoded)")
    }
    func javSampleImageUrl(javId: Int64, index: Int, variant: String) -> String? {
        absoluteUrl("jav/items/\(javId)/sample-images/\(index)/\(variant)")
    }
    func idolCoverUrl(id: Int64) -> String? { absoluteUrl("jav/idols/\(id)/cover") }
    func studioCoverUrl(id: Int64) -> String? { absoluteUrl("jav/studios/\(id)/cover") }
    func seriesCoverUrl(id: Int64) -> String? { absoluteUrl("jav/series/\(id)/cover") }

    // MARK: - 请求

    /// 构造带会话 Cookie 的请求（仅同源注入）
    func makeRequest(method: String, url: URL, body: Data? = nil, extraHeaders: [String: String] = [:]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("JavBossiOS/0.1", forHTTPHeaderField: "User-Agent")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let cookie = cookieJar.cookieHeader(for: url) {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        return request
    }

    func handleResponse(_ response: URLResponse?, data: Data?, allow401: Bool = false) throws -> Data {
        guard let http = response as? HTTPURLResponse else {
            throw ApiError.network("网络错误：无响应")
        }
        // 任何同源响应都可能带 Set-Cookie，先保存
        if let url = http.url {
            cookieJar.storeCookies(from: http, for: url)
        }
        if http.statusCode == 401 && !allow401 {
            throw ApiError.authExpired
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = Self.parseErrorBody(data) ?? "请求失败（\(http.statusCode)）"
            throw ApiError.http(status: http.statusCode, message: message)
        }
        return data ?? Data()
    }

    static func parseErrorBody(_ data: Data?) -> String? {
        guard let data = data, !data.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let zh = obj["error_zh"] as? String, !zh.isEmpty { return zh }
        if let en = obj["error_en"] as? String, !en.isEmpty { return en }
        if let message = obj["message"] as? String, !message.isEmpty { return message }
        if let error = obj["error"] as? String, !error.isEmpty { return error }
        return nil
    }

    // MARK: - 泛型请求

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        guard let url = apiUrl(path, query: query) else { throw ApiError.network("服务器地址无效") }
        var request = makeRequest(method: "GET", url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await urlSession.data(for: request)
        let body = try handleResponse(response, data: data)
        do {
            return try decoder.decode(T.self, from: body)
        } catch {
            if let message = Self.parseErrorBody(body) {
                throw ApiError.http(status: 200, message: "解析失败：\(message)")
            }
            throw ApiError.network("解析响应失败：\(error.localizedDescription)")
        }
    }

    func post<T: Decodable>(_ path: String, body: (some Encodable)? = Optional<EmptyRequest>.none) async throws -> T {
        try await send(method: "POST", path: path, body: body)
    }

    func put<T: Decodable>(_ path: String, body: (some Encodable)? = Optional<EmptyRequest>.none) async throws -> T {
        try await send(method: "PUT", path: path, body: body)
    }

    func patch<T: Decodable>(_ path: String, body: (some Encodable)? = Optional<EmptyRequest>.none) async throws -> T {
        try await send(method: "PATCH", path: path, body: body)
    }

    func delete<T: Decodable>(_ path: String) async throws -> T {
        try await send(method: "DELETE", path: path, body: Optional<EmptyRequest>.none)
    }

    func postVoid(_ path: String, body: (some Encodable)? = Optional<EmptyRequest>.none) async throws {
        let _: EmptyResponse = try await send(method: "POST", path: path, body: body)
    }

    func putVoid(_ path: String, body: (some Encodable)? = Optional<EmptyRequest>.none) async throws {
        let _: EmptyResponse = try await send(method: "PUT", path: path, body: body)
    }

    func patchVoid(_ path: String, body: (some Encodable)? = Optional<EmptyRequest>.none) async throws {
        let _: EmptyResponse = try await send(method: "PATCH", path: path, body: body)
    }

    func deleteVoid(_ path: String) async throws {
        let _: EmptyResponse = try await send(method: "DELETE", path: path, body: Optional<EmptyRequest>.none)
    }

    func send<T: Decodable>(method: String, path: String, body: (some Encodable)?) async throws -> T {
        guard let url = apiUrl(path) else { throw ApiError.network("服务器地址无效") }
        var data: Data?
        if let body = body, !(body is EmptyRequest) {
            data = try encoder.encode(body)
        }
        let request = makeRequest(method: method, url: url, body: data)
        let (responseData, response) = try await urlSession.data(for: request)
        let resultData = try handleResponse(response, data: responseData, allow401: path == "auth/login")
        if T.self == EmptyResponse.self || resultData.isEmpty {
            return EmptyResponse() as! T
        }
        do {
            return try decoder.decode(T.self, from: resultData)
        } catch {
            if let message = Self.parseErrorBody(resultData) {
                throw ApiError.http(status: 200, message: "解析失败：\(message)")
            }
            throw ApiError.network("解析响应失败：\(error.localizedDescription)")
        }
    }

    struct EmptyRequest: Encodable {}

    // MARK: - 图片

    /// 带会话 Cookie 加载图片数据
    func imageData(url: URL) async throws -> Data {
        let request = makeRequest(method: "GET", url: url)
        let (data, response) = try await urlSession.data(for: request)
        let _ = try handleResponse(response, data: data)
        return data
    }
}
