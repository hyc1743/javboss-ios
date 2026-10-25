import Foundation

@MainActor
final class WatchedProgressStore: ObservableObject {
    static let shared = WatchedProgressStore()

    @Published private(set) var videoTotals: [Int64: Int64] = [:]
    @Published private(set) var javTotals: [Int64: Int64] = [:]

    private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            for await snapshot in Repository(api: AppState.shared.api).watchedTimeEventStream() {
                self.merge(snapshot)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func merge(_ snapshot: WatchedTimeSnapshot) {
        for item in snapshot.videos { videoTotals[item.id] = item.watchedMs }
        for item in snapshot.javs { javTotals[item.id] = item.watchedMs }
        objectWillChange.send()
    }

    func watchedMs(videoId: Int64, fallback: Int64) -> Int64 {
        videoTotals[videoId] ?? fallback
    }
}
