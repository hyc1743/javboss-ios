import SwiftUI

final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSURL, NSData>()

    func data(for url: URL) -> Data? {
        cache.object(forKey: url as NSURL) as Data?
    }

    func set(_ data: Data, for url: URL) {
        cache.setObject(data as NSData, forKey: url as NSURL)
    }
}

/// 带会话 Cookie 的远程图片（封面/缩略图大多需要登录态）。
struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    var placeholderColor: Color = Color(white: 0.15)

    @State private var imageData: Data?
    @State private var failed = false
    @State private var loading = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                placeholderColor
                if let data = imageData, let ui = UIImage(data: data) {
                    Image(uiImage: ui)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                } else if failed {
                    VStack(spacing: 4) {
                        Image(systemName: "photo")
                            .font(.title2)
                        Text("加载失败")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                } else if loading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .task(id: url) {
            await load()
        }
    }

    private func load() async {
        guard let url = url, !url.absoluteString.isEmpty else {
            failed = true
            return
        }
        if let cached = ImageCache.shared.data(for: url) {
            imageData = cached
            return
        }
        loading = true
        do {
            let data = try await AppState.shared.api.imageData(url: url)
            if !data.isEmpty {
                ImageCache.shared.set(data, for: url)
                imageData = data
            } else {
                failed = true
            }
        } catch {
            failed = true
        }
        loading = false
    }
}
