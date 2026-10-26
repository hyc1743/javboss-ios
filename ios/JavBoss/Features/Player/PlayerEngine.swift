import AVFoundation
import Foundation
import KSPlayer
import UIKit

/// KSPlayer/FFmpeg playback adapter.
///
/// The server still supplies direct and HLS sources through the existing
/// /videos/{id}/streams contract. KSPlayer owns demuxing, decoding, buffering,
/// and HTTP header forwarding; this adapter exposes the small surface used by
/// the existing SwiftUI controls.
@MainActor
final class AVPlayerEngine: NSObject, ObservableObject, KSPlayerLayerDelegate {
    let videoView = UIView()
    private var layer: KSPlayerLayer?

    @Published var isPlaying = false
    @Published var isBuffering = false
    @Published var positionMs: Int64 = 0
    @Published var durationMs: Int64 = 0
    @Published var failed = false
    @Published var subtitlesAvailable = false
    @Published var subtitlesEnabled = true

    var onError: (() -> Void)?
    var onEnded: (() -> Void)?

    override init() {
        super.init()
        videoView.backgroundColor = .black
        videoView.clipsToBounds = true
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func load(urlString: String) {
        failed = false
        guard let url = URL(string: urlString),
              AppState.shared.cookieJar.sameOrigin(url) else {
            failed = true
            onError?()
            return
        }

        layer?.stop()
        layer?.delegate = nil
        layer = nil
        videoView.subviews.forEach { $0.removeFromSuperview() }

        let options = KSOptions()
        options.userAgent = "JavBossiOS/0.1"
        var headers = ["User-Agent": "JavBossiOS/0.1"]
        if let cookie = AppState.shared.cookieJar.cookieHeader(for: url) {
            headers["Cookie"] = cookie
        }
        options.appendHeader(headers)
        options.isAccurateSeek = true
        options.isSeekedAutoPlay = true

        let newLayer = KSPlayerLayer(url: url, options: options, delegate: self)
        layer = newLayer
        if let playerView = newLayer.player.view {
            playerView.translatesAutoresizingMaskIntoConstraints = false
            videoView.addSubview(playerView)
            NSLayoutConstraint.activate([
                playerView.leadingAnchor.constraint(equalTo: videoView.leadingAnchor),
                playerView.trailingAnchor.constraint(equalTo: videoView.trailingAnchor),
                playerView.topAnchor.constraint(equalTo: videoView.topAnchor),
                playerView.bottomAnchor.constraint(equalTo: videoView.bottomAnchor),
            ])
        }
        newLayer.play()
    }

    func play() {
        layer?.play()
        isPlaying = true
    }

    func pause() {
        layer?.pause()
        isPlaying = false
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    func seek(to ms: Int64) {
        let clamped = max(0, min(ms, durationMs))
        layer?.seek(time: Double(clamped) / 1000, autoPlay: isPlaying) { [weak self] _ in
            Task { @MainActor in self?.positionMs = clamped }
        }
        positionMs = clamped
    }

    func seek(by deltaMs: Int64) {
        seek(to: positionMs + deltaMs)
    }

    func setSpeed(_ speed: Float) {
        layer?.player.playbackRate = speed
        isPlaying = speed > 0
    }

    func setSubtitlesEnabled(_ enabled: Bool) {
        subtitlesEnabled = enabled
        let tracks = layer?.player.tracks(mediaType: .text) ?? []
        subtitlesAvailable = !tracks.isEmpty
        guard let track = tracks.first else { return }
        track.isEnabled = enabled
    }

    func stop() {
        layer?.stop()
        layer?.delegate = nil
        layer = nil
        videoView.subviews.forEach { $0.removeFromSuperview() }
        isPlaying = false
        isBuffering = false
    }

    func player(layer: KSPlayerLayer, state: KSPlayerState) {
        switch state {
        case .readyToPlay:
            durationMs = Int64(max(0, layer.player.duration) * 1000)
            isBuffering = false
            isPlaying = true
            let tracks = layer.player.tracks(mediaType: .text)
            subtitlesAvailable = !tracks.isEmpty
        case .buffering:
            isBuffering = true
        case .bufferFinished:
            isBuffering = false
            isPlaying = true
        case .paused:
            isPlaying = false
        case .playedToTheEnd:
            isPlaying = false
            isBuffering = false
            onEnded?()
        case .error:
            failPlayback(for: layer)
        default:
            break
        }
    }

    func player(layer: KSPlayerLayer, currentTime: TimeInterval, totalTime: TimeInterval) {
        positionMs = Int64(max(0, currentTime) * 1000)
        durationMs = Int64(max(0, totalTime) * 1000)
    }

    func player(layer: KSPlayerLayer, finish error: Error?) {
        if let error {
            failPlayback(for: layer)
            NSLog("KSPlayer playback failed: %@", error.localizedDescription)
        }
    }

    private func failPlayback(for layer: KSPlayerLayer) {
        guard self.layer === layer, !failed else { return }
        failed = true
        isPlaying = false
        isBuffering = false
        onError?()
    }

    func player(layer: KSPlayerLayer, bufferedCount: Int, consumeTime: TimeInterval) {
        isBuffering = bufferedCount <= 0
    }
}
