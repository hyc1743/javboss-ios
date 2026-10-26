import Foundation

enum PlaybackProgress {
    static func total(initialWatchedMs: Int64, resumePositionMs: Int64, positionMs: Int64) -> Int64? {
        guard positionMs > resumePositionMs else { return nil }
        return initialWatchedMs + (positionMs - resumePositionMs)
    }
}
