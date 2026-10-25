import Foundation

@MainActor
final class PlaybackQueue: ObservableObject {
    static let shared = PlaybackQueue()

    @Published private(set) var items: [Video] = []

    func add(_ video: Video) {
        guard !items.contains(where: { $0.id == video.id }) else { return }
        items.append(video)
    }

    func remove(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
    }

    func remove(_ video: Video) {
        items.removeAll { $0.id == video.id }
    }

    func clear() { items.removeAll() }
}
