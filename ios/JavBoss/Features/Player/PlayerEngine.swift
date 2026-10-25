import AVFoundation
import Foundation

/// 自定义 scheme 前缀：AVPlayer 的所有资源请求（HLS playlist / 分片 / direct mp4）
/// 都会经过此加载器，由我们附加会话 Cookie 后转发到真实服务器。
enum JBScheme {
    static let prefix = "jbhttp"

    static func rewrapped(_ urlString: String) -> URL? {
        guard let url = URL(string: urlString) else { return nil }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard var components else { return nil }
        components.scheme = prefix + (components.scheme ?? "http")
        return components.url
    }

    static func unwrapped(_ url: URL) -> URL? {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard var components else { return nil }
        guard let scheme = components.scheme, scheme.hasPrefix(prefix) else { return nil }
        components.scheme = String(scheme.dropFirst(prefix.count))
        return components.url
    }
}

/// 转发 AVPlayer 资源请求并注入会话 Cookie 的 ResourceLoader。
/// 与 Android 端 AuthProxy 作用相同，但针对 AVPlayer 更高效：直接以字节范围转发。
final class CookieResourceLoader: NSObject, AVAssetResourceLoaderDelegate, URLSessionDataDelegate {

    private final class LoadContext {
        let loadingRequest: AVAssetResourceLoadingRequest
        var task: URLSessionDataTask?
        var response: URLResponse?
        var data = Data()

        init(loadingRequest: AVAssetResourceLoadingRequest) {
            self.loadingRequest = loadingRequest
        }
    }

    private var contexts: [Int: LoadContext] = [:]
    private var urlSession: URLSession?

    private var session: URLSession {
        if let urlSession { return urlSession }
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpCookieStorage = nil
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 3600
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        let created = URLSession(configuration: config, delegate: self, delegateQueue: queue)
        urlSession = created
        return created
    }

    // MARK: - AVAssetResourceLoaderDelegate

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard let wrapped = loadingRequest.request.url,
              let upstream = JBScheme.unwrapped(wrapped) else {
            loadingRequest.finish(with: NSError(domain: "javboss", code: -1,
                                                userInfo: [NSLocalizedDescriptionKey: "无效的资源地址"]))
            return false
        }
        guard AppState.shared.cookieJar.sameOrigin(upstream) else {
            loadingRequest.finish(with: NSError(domain: "javboss", code: -2,
                                                userInfo: [NSLocalizedDescriptionKey: "资源地址与服务器不同源"]))
            return false
        }

        var request = URLRequest(url: upstream)
        request.setValue("JavBossiOS/0.1", forHTTPHeaderField: "User-Agent")
        if let cookie = AppState.shared.cookieJar.cookieHeader(for: upstream) {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")

        // 字节范围：AVPlayer 拖动 / mp4 探测依赖
        let offset = loadingRequest.dataRequest?.requestedOffset ?? 0
        let length = loadingRequest.dataRequest?.requestedLength ?? -1
        if length >= 0 && (offset > 0 || length > 0) {
            if length == 0 {
                request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
            } else {
                request.setValue("bytes=\(offset)-\(offset + length - 1)", forHTTPHeaderField: "Range")
            }
        } else if offset > 0 {
            request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
        }

        let ctx = LoadContext(loadingRequest: loadingRequest)
        let task = session.dataTask(with: request)
        ctx.task = task
        contexts[task.taskIdentifier] = ctx
        task.resume()
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        for (key, ctx) in contexts where ctx.loadingRequest === loadingRequest {
            ctx.task?.cancel()
            contexts.removeValue(forKey: key)
            break
        }
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let ctx = contexts[dataTask.taskIdentifier] {
            ctx.response = response
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if let ctx = contexts[dataTask.taskIdentifier] {
            ctx.data.append(data)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard let ctx = contexts[task.taskIdentifier] else {
            completionHandler(nil)
            return
        }
        var redirected = request
        if let url = request.url {
            // 同源才继续携带 Cookie；不同源则拒绝跟随
            if AppState.shared.cookieJar.sameOrigin(url),
               let cookie = AppState.shared.cookieJar.cookieHeader(for: url) {
                redirected.setValue(cookie, forHTTPHeaderField: "Cookie")
            } else {
                completionHandler(nil)
                return
            }
        }
        ctx.response = response
        completionHandler(redirected)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let ctx = contexts.removeValue(forKey: task.taskIdentifier) else { return }
        let loadingRequest = ctx.loadingRequest

        if let error = error {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                loadingRequest.finish(with: NSError(domain: "javboss", code: NSURLErrorCancelled,
                                                    userInfo: [NSLocalizedDescriptionKey: "已取消"]))
            } else {
                loadingRequest.finish(with: error)
            }
            return
        }

        let http = ctx.response as? HTTPURLResponse
        guard let http, (200..<300).contains(http.statusCode) else {
            loadingRequest.finish(with: NSError(domain: "javboss", code: http?.statusCode ?? -1,
                                                userInfo: [NSLocalizedDescriptionKey: "服务器返回 \(http?.statusCode ?? -1)"]))
            return
        }

        // 填充内容信息（HLS 分片和 mp4 探测都需要）
        if let infoRequest = loadingRequest.contentInformationRequest {
            infoRequest.contentType = http.mimeType
            if http.statusCode == 206, let contentRange = http.value(forHTTPHeaderField: "Content-Range") {
                // "bytes 0-999/1234567"
                if let total = contentRange.split(separator: "/").last,
                   let totalBytes = Int64(total.trimmingCharacters(in: .whitespaces)) {
                    infoRequest.contentLength = totalBytes
                }
                infoRequest.isByteRangeAccessSupported = true
            } else {
                infoRequest.contentLength = http.expectedContentLength
            }
        }

        if let dataRequest = loadingRequest.dataRequest {
            let requestedLength = dataRequest.requestedLength
            if requestedLength > 0 && ctx.data.count > requestedLength {
                // 服务器不支持 Range 返回了 200 全量：只回填请求的片段
                dataRequest.respond(with: ctx.data.prefix(requestedLength))
            } else {
                dataRequest.respond(with: ctx.data)
            }
        }
        loadingRequest.finish()
    }
}

/// AVPlayer 引擎：direct（mp4 等）与 HLS 均由系统硬解，Cookie 经 ResourceLoader 注入。
/// 所有 @Published 变更均发生在主线程（时间观察器挂 main queue，状态回调经 MainActor）。
final class AVPlayerEngine: ObservableObject {
    let player = AVPlayer()

    @Published var isPlaying = false
    @Published var isBuffering = false
    @Published var positionMs: Int64 = 0
    @Published var durationMs: Int64 = 0
    @Published var failed = false
    @Published var subtitlesAvailable = false
    @Published var subtitlesEnabled = true

    var onError: (() -> Void)?

    private var asset: AVURLAsset?
    private var loader: CookieResourceLoader?
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?

    init() {
        // 播放会话：后台静音时仍出声
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            let position = Int64(CMTimeGetSeconds(time) * 1000)
            self.positionMs = max(0, position)
            if let item = self.player.currentItem {
                let duration = CMTimeGetSeconds(item.duration)
                if duration.isFinite && duration > 0 {
                    self.durationMs = Int64(duration * 1000)
                }
                self.isBuffering = item.isPlaybackBufferEmpty
                if item.status == .failed {
                    self.failed = true
                }
                // 字幕轨检测（HLS 文本轨）
                if let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) {
                    self.subtitlesAvailable = !group.options.isEmpty
                }
            }
        }
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
    }

    func load(urlString: String) {
        failed = false
        loader = CookieResourceLoader()
        guard let wrapped = JBScheme.rewrapped(urlString) else {
            failed = true
            return
        }
        let newAsset = AVURLAsset(url: wrapped)
        newAsset.resourceLoader.setDelegate(loader, queue: DispatchQueue(label: "javboss.resourceLoader"))
        asset = newAsset
        let item = AVPlayerItem(asset: newAsset)
        statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                if item.status == .failed {
                    self.failed = true
                    self.onError?()
                }
            }
        }
        player.replaceCurrentItem(with: item)
        player.play()
        isPlaying = true
    }

    func play() {
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func seek(to ms: Int64) {
        let clamped = max(0, min(ms, durationMs))
        player.seek(to: CMTime(seconds: Double(clamped) / 1000, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        positionMs = clamped
    }

    func seek(by deltaMs: Int64) {
        seek(to: positionMs + deltaMs)
    }

    func setSpeed(_ speed: Float) {
        player.rate = speed
        isPlaying = speed > 0
    }

    func setSubtitlesEnabled(_ enabled: Bool) {
        subtitlesEnabled = enabled
        guard let item = player.currentItem else { return }
        if enabled {
            if let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible),
               let option = group.options.first {
                item.select(option, in: group)
            }
        } else {
            if let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) {
                item.select(nil, in: group)
            }
        }
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        statusObserver = nil
        loader = nil
        asset = nil
    }
}
