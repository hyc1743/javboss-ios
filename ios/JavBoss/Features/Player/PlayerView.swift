import SwiftUI
import AVFoundation
import MediaPlayer

// MARK: - 播放页模型

enum SeekSensitivity: String, CaseIterable {
    case low
    case medium
    case high

    var label: String {
        switch self {
        case .low: return "低"
        case .medium: return "中"
        case .high: return "高"
        }
    }

    var factor: Double {
        switch self {
        case .low: return 0.25
        case .medium: return 1.0
        case .high: return 2.0
        }
    }
}

enum PanMode {
    case idle
    case pending
    case seek
    case brightness
    case volume
}

@MainActor
final class PlayerModel: ObservableObject {
    private(set) var videoId: Int64
    private(set) var locationId: Int64?
    private(set) var initialWatchedMs: Int64

    @Published var engine: AVPlayerEngine?
    @Published var loading = true
    @Published var errorMessage: String?
    @Published var controlsVisible = true
    @Published var locked = false
    @Published var showResumePrompt = false
    @Published var showSettings = false
    @Published var seekSensitivity: SeekSensitivity = .medium

    // 手势预览
    @Published var panMode: PanMode = .idle
    @Published var seekPreviewMs: Int64 = 0
    @Published var brightnessPreview: Double = 0
    @Published var volumePreview: Float = 0
    @Published var speedBoost = false
    @Published var sliderOverride: Double?

    private var urls: [String] = []
    private var urlIndex = 0
    private var resumePositionMs: Int64 = 0
    private var sessionId: String?
    private var lastReportedTotalMs: Int64 = 0
    private var reportTask: Task<Void, Never>?

    // 手势状态
    private var panStartPositionMs: Int64 = 0
    private var panStartBrightness: Double = 0
    private var panStartVolume: Float = 0
    private var panStartLocation: CGPoint = .zero

    private let repo: Repository
    var onEnded: (() -> Void)?

    init(videoId: Int64, locationId: Int64? = nil, initialWatchedMs: Int64) {
        self.videoId = videoId
        self.locationId = locationId
        self.initialWatchedMs = initialWatchedMs
        self.repo = Repository(api: AppState.shared.api)
        self.seekSensitivity = SeekSensitivity(rawValue: UserDefaults.standard.string(forKey: "player_seek_sensitivity") ?? "") ?? .medium
    }

    func load() {
        Task {
            do {
                let resolved = try await repo.resolvePlayUrls(id: videoId, locationId: locationId)
                let ready = await MainActor.run {
                    self.urls = resolved
                    guard !self.urls.isEmpty else {
                        self.errorMessage = "没有可用的播放源"
                        self.loading = false
                        return false
                    }
                    let newEngine = AVPlayerEngine()
                    newEngine.onError = { [weak self] in
                        Task { @MainActor in
                            self?.tryNextSource()
                        }
                    }
                    newEngine.onEnded = { [weak self] in
                        self?.onEnded?()
                    }
                    self.engine = newEngine
                    self.tryNextSource()
                    self.loading = false
                    if self.initialWatchedMs > 30_000 {
                        self.showResumePrompt = true
                    }
                    return true
                }
                guard ready else { return }
                await repo.reportPlay(id: videoId)
                await startSession()
                startReportLoop()
            } catch let error as ApiError {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.loading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.loading = false
                }
            }
        }
    }

    private func startReportLoop() {
        reportTask?.cancel()
        reportTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard let self, !Task.isCancelled else { break }
                self.reportProgress()
                if self.engine == nil { break }
            }
        }
    }

    private func tryNextSource() {
        guard urlIndex < urls.count else {
            errorMessage = "播放失败：所有播放源均不可用"
            return
        }
        let url = urls[urlIndex]
        urlIndex += 1
        engine?.load(urlString: url)
    }

    func startFromBeginning() {
        showResumePrompt = false
        resumePositionMs = 0
        lastReportedTotalMs = initialWatchedMs
        Task { await startSession() }
    }

    func resumeFromPrevious() {
        showResumePrompt = false
        let start = min(initialWatchedMs, max(0, (engine?.durationMs ?? initialWatchedMs) - 5000))
        resumePositionMs = start
        lastReportedTotalMs = start
        engine?.seek(to: start)
        engine?.play()
        Task { await startSession() }
    }

    private func startSession() async {
        do {
            sessionId = try await repo.createPlaybackSession(videoId: videoId, locationId: locationId ?? 0)
        } catch {
            sessionId = nil
        }
    }

    /// 每 10 秒上报累计观看时长；410 时重建会话
    func reportProgress() {
        guard let engine, engine.isPlaying, let sessionId else { return }
        let position = engine.positionMs
        guard position > resumePositionMs else { return }
        let total = initialWatchedMs + (position - resumePositionMs)
        guard total > lastReportedTotalMs else { return }
        lastReportedTotalMs = total
        let sid = sessionId
        Task {
            do {
                try await repo.reportPlaybackSession(videoId: videoId, sessionId: sid, watchedMs: total)
            } catch ApiError.http(let code, _) where code == 410 {
                await MainActor.run {
                    self.sessionId = nil
                    self.resumePositionMs = engine.positionMs
                    self.lastReportedTotalMs = engine.positionMs
                }
                await startSession()
            } catch {
                // 网络抖动忽略，下次再报
            }
        }
    }

    func flushProgress() {
        reportProgress()
    }

    func captureScreenshot() {
        let second = Double(engine?.positionMs ?? 0) / 1000.0
        Task {
            do {
                _ = try await repo.createScreenshot(videoId: videoId, second: second)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func switchTo(video: Video) {
        reportTask?.cancel()
        engine?.stop()
        videoId = video.id
        locationId = video.locationId
        initialWatchedMs = video.watchedMs
        urls = []
        urlIndex = 0
        resumePositionMs = 0
        lastReportedTotalMs = 0
        sessionId = nil
        loading = true
        errorMessage = nil
        showResumePrompt = false
        load()
    }

    func setSensitivity(_ value: SeekSensitivity) {
        seekSensitivity = value
        UserDefaults.standard.set(value.rawValue, forKey: "player_seek_sensitivity")
    }

    // MARK: 手势

    func beginSliderDrag() {
        sliderOverride = Double(engine?.positionMs ?? 0)
    }

    func updateSlider(_ value: Double) {
        sliderOverride = value
    }

    func commitSlider() {
        if let override = sliderOverride {
            engine?.seek(to: Int64(override))
        }
        sliderOverride = nil
    }

    func handleSingleTap() {
        withAnimation(.easeInOut(duration: 0.15)) {
            controlsVisible.toggle()
        }
    }

    func handleDoubleTap(at location: CGPoint) {
        guard let engine else { return }
        let width = UIScreen.main.bounds.width
        let delta: Int64 = location.x < width / 3 ? -10_000 : (location.x > width * 2 / 3 ? 10_000 : 0)
        if delta == 0 {
            engine.togglePlayPause()
        } else {
            engine.seek(by: delta)
        }
    }

    func handleLongPressStart() {
        guard let engine else { return }
        speedBoost = true
        engine.setSpeed(2.0)
    }

    func handleLongPressEnd() {
        guard let engine else { return }
        speedBoost = false
        engine.setSpeed(1.0)
    }

    func handlePanStart(location: CGPoint) {
        guard let engine else { return }
        panMode = .pending
        panStartLocation = location
        panStartPositionMs = engine.positionMs
        panStartBrightness = UIScreen.main.brightness
        panStartVolume = VolumeControl.shared.current()
    }

    func handlePanChange(translation: CGPoint, location: CGPoint) {
        guard let engine else { return }
        switch panMode {
        case .pending:
            if abs(translation.x) > 10 || abs(translation.y) > 10 {
                if abs(translation.x) > abs(translation.y) {
                    panMode = .seek
                    seekPreviewMs = panStartPositionMs
                } else {
                    panMode = panStartLocation.x < UIScreen.main.bounds.width / 2 ? .brightness : .volume
                    brightnessPreview = panStartBrightness
                    volumePreview = panStartVolume
                }
            }
        case .seek:
            let width = max(UIScreen.main.bounds.width, 1)
            let ratio = Double(translation.x / width)
            let duration = Double(max(engine.durationMs, 1))
            let delta = ratio * duration * seekSensitivity.factor
            let target = Double(panStartPositionMs) + delta
            seekPreviewMs = Int64(max(0, min(target, Double(engine.durationMs))))
        case .brightness:
            let height = max(UIScreen.main.bounds.height, 1)
            let delta = Double(-translation.y / height)
            brightnessPreview = max(0.05, min(1, panStartBrightness + delta))
            UIScreen.main.brightness = brightnessPreview
        case .volume:
            let height = max(UIScreen.main.bounds.height, 1)
            let delta = Float(-translation.y / height)
            volumePreview = max(0, min(1, panStartVolume + delta))
            VolumeControl.shared.set(volumePreview)
        case .idle:
            break
        }
    }

    func handlePanEnd() {
        if panMode == .seek {
            engine?.seek(to: seekPreviewMs)
        }
        panMode = .idle
    }

    func teardown() {
        reportTask?.cancel()
        reportTask = nil
        flushProgress()
        engine?.stop()
    }
}

// MARK: - 音量控制

final class VolumeControl {
    static let shared = VolumeControl()
    private weak var slider: UISlider?

    func attach(slider: UISlider) {
        self.slider = slider
    }

    func current() -> Float {
        slider?.value ?? AVAudioSession.sharedInstance().outputVolume
    }

    func set(_ value: Float) {
        let clamped = max(0, min(1, value))
        slider?.value = clamped
        if let slider {
            slider.sendActions(for: .valueChanged)
        }
    }
}

struct VolumeCaptureView: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.alpha = 0.01
        view.isUserInteractionEnabled = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            attachSlider(from: view)
        }
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}

    private func attachSlider(from view: UIView) {
        for subview in view.subviews {
            if let slider = subview as? UISlider {
                VolumeControl.shared.attach(slider: slider)
                return
            }
            attachSlider(from: subview)
        }
    }
}

// MARK: - 手势捕获

struct GestureOverlayView: UIViewRepresentable {
    var onSingleTap: @MainActor () -> Void
    var onDoubleTap: @MainActor (CGPoint) -> Void
    var onLongPressStart: @MainActor () -> Void
    var onLongPressEnd: @MainActor () -> Void
    var onPanStart: @MainActor (CGPoint) -> Void
    var onPanChange: @MainActor (CGPoint, CGPoint) -> Void
    var onPanEnd: @MainActor () -> Void

    func makeUIView(context: Context) -> GestureCaptureView {
        let view = GestureCaptureView()
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: GestureCaptureView, context: Context) {
        uiView.onSingleTap = onSingleTap
        uiView.onDoubleTap = onDoubleTap
        uiView.onLongPressStart = onLongPressStart
        uiView.onLongPressEnd = onLongPressEnd
        uiView.onPanStart = onPanStart
        uiView.onPanChange = onPanChange
        uiView.onPanEnd = onPanEnd
    }
}

final class GestureCaptureView: UIView {
    var onSingleTap: (@MainActor () -> Void)?
    var onDoubleTap: (@MainActor (CGPoint) -> Void)?
    var onLongPressStart: (@MainActor () -> Void)?
    var onLongPressEnd: (@MainActor () -> Void)?
    var onPanStart: (@MainActor (CGPoint) -> Void)?
    var onPanChange: (@MainActor (CGPoint, CGPoint) -> Void)?
    var onPanEnd: (@MainActor () -> Void)?

    private var singleTap: UITapGestureRecognizer!
    private var doubleTap: UITapGestureRecognizer!
    private var longPress: UILongPressGestureRecognizer!
    private var pan: UIPanGestureRecognizer!

    override init(frame: CGRect) {
        super.init(frame: frame)
        singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        singleTap.require(toFail: doubleTap)
        longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.5
        longPress.allowableMovement = 30
        pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(singleTap)
        addGestureRecognizer(doubleTap)
        addGestureRecognizer(longPress)
        addGestureRecognizer(pan)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc @MainActor private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
        onSingleTap?()
    }

    @objc @MainActor private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        onDoubleTap?(gesture.location(in: self))
    }

    @objc @MainActor private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            onLongPressStart?()
        case .ended, .cancelled, .failed:
            onLongPressEnd?()
        default:
            break
        }
    }

    @objc @MainActor private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self)
        let location = gesture.location(in: self)
        switch gesture.state {
        case .began:
            onPanStart?(location)
        case .changed:
            onPanChange?(translation, location)
        case .ended, .cancelled:
            onPanEnd?()
        default:
            break
        }
    }
}

// MARK: - 视频渲染层

final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

struct VideoLayer: UIViewRepresentable {
    let engine: AVPlayerEngine

    func makeUIView(context: Context) -> UIView {
        engine.videoView
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        uiView.backgroundColor = .black
    }
}

// MARK: - 播放页

struct PlayerView: View {
    let videoId: Int64
    let locationId: Int64?
    let watchedMs: Int64
    let playlist: [Video]

    @StateObject private var model: PlayerModel
    @State private var currentIndex = 0
    @Environment(\.dismiss) private var dismiss

    init(videoId: Int64, locationId: Int64? = nil, watchedMs: Int64, playlist: [Video] = []) {
        self.videoId = videoId
        self.locationId = locationId
        self.watchedMs = watchedMs
        self.playlist = playlist
        _model = StateObject(wrappedValue: PlayerModel(videoId: videoId, locationId: locationId, initialWatchedMs: watchedMs))
    }

    private func advancePlaylist() {
        guard currentIndex + 1 < playlist.count else { return }
        currentIndex += 1
        model.switchTo(video: playlist[currentIndex])
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let engine = model.engine {
                VideoLayer(engine: engine)
                    .ignoresSafeArea()

                if !model.locked {
                    GestureOverlayView(
                        onSingleTap: { model.handleSingleTap() },
                        onDoubleTap: { location in model.handleDoubleTap(at: location) },
                        onLongPressStart: { model.handleLongPressStart() },
                        onLongPressEnd: { model.handleLongPressEnd() },
                        onPanStart: { location in model.handlePanStart(location: location) },
                        onPanChange: { translation, location in model.handlePanChange(translation: translation, location: location) },
                        onPanEnd: { model.handlePanEnd() }
                    )
                    .ignoresSafeArea()
                }

                if model.controlsVisible {
                    controls(engine)
                }

                // 顶部常驻返回/锁定
                topBar(engine)

                // 状态指示
                indicators(engine)
            }

            if model.loading {
                ProgressView("加载播放源…")
                    .foregroundStyle(.white)
            }

            if let error = model.errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.yellow)
                    Text(error)
                        .foregroundStyle(.white)
                    Button("返回") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
            }

            VolumeCaptureView()
                .frame(width: 1, height: 1)
                .opacity(0.01)

            if model.showSettings {
                settingsPanel()
            }
        }
        .statusBarHidden(true)
        .onAppear {
            OrientationLock.shared.enterPlayer()
            UIApplication.shared.isIdleTimerDisabled = true
            model.onEnded = { advancePlaylist() }
            model.load()
        }
        .onDisappear {
            model.teardown()
            OrientationLock.shared.exitPlayer()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .alert("继续播放", isPresented: $model.showResumePrompt) {
            Button("从头播放") { model.startFromBeginning() }
            Button("从上次位置继续") { model.resumeFromPrevious() }
        } message: {
            Text("上次看到 \(Fmt.ms(watchedMs))，是否继续？")
        }
    }

    private func topBar(_ engine: AVPlayerEngine) -> some View {
        VStack {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.black.opacity(0.4), in: Circle())
                }
                Spacer()
                Button {
                    model.locked.toggle()
                    if model.locked {
                        model.controlsVisible = false
                    }
                } label: {
                    Image(systemName: model.locked ? "lock.fill" : "lock.open")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.black.opacity(0.4), in: Circle())
                }
            }
            .padding(.horizontal)
            Spacer()
        }
        .padding(.top, 8)
    }

    private func indicators(_ engine: AVPlayerEngine) -> some View {
        ZStack {
            if engine.isBuffering {
                ProgressView()
                    .tint(.white)
            }
            if model.speedBoost {
                Text("2x")
                    .font(.headline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.orange, in: RoundedRectangle(cornerRadius: 8))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 60)
            }
            // 手势预览
            switch model.panMode {
            case .seek:
                VStack(spacing: 4) {
                    Text("\(Fmt.ms(model.seekPreviewMs)) / \(Fmt.ms(engine.durationMs))")
                        .font(.subheadline.monospacedDigit())
                    Image(systemName: model.seekPreviewMs > engine.positionMs ? "goforward" : "gobackward")
                }
                .foregroundStyle(.white)
                .padding(14)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
            case .brightness:
                VStack(spacing: 8) {
                    Image(systemName: "sun.max")
                    Text("\(Int(model.brightnessPreview * 100))%")
                }
                .foregroundStyle(.white)
                .padding(14)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
            case .volume:
                VStack(spacing: 8) {
                    Image(systemName: "speaker.wave.2")
                    Text("\(Int(model.volumePreview * 100))%")
                }
                .foregroundStyle(.white)
                .padding(14)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
            default:
                EmptyView()
            }
        }
    }

    private func controls(_ engine: AVPlayerEngine) -> some View {
        VStack {
            Spacer()
            VStack(spacing: 8) {
                Slider(
                    value: Binding(
                        get: { model.sliderOverride ?? Double(engine.positionMs) },
                        set: { model.updateSlider($0) }
                    ),
                    in: 0...max(Double(engine.durationMs), 1),
                    onEditingChanged: { editing in
                        if editing {
                            model.beginSliderDrag()
                        } else {
                            model.commitSlider()
                        }
                    }
                )
                .tint(.orange)

                HStack {
                    Button {
                        engine.togglePlayPause()
                    } label: {
                        Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
                    Text("\(Fmt.ms(Int64(model.sliderOverride ?? Double(engine.positionMs)))) / \(Fmt.ms(engine.durationMs))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white)
                    Spacer()
                    if engine.subtitlesAvailable {
                        Button {
                            engine.setSubtitlesEnabled(!engine.subtitlesEnabled)
                        } label: {
                            Image(systemName: engine.subtitlesEnabled ? "captions.bubble.fill" : "captions.bubble")
                                .font(.subheadline)
                                .foregroundStyle(engine.subtitlesEnabled ? .orange : .white)
                        }
                    }
                    Button {
                        model.captureScreenshot()
                    } label: {
                        Image(systemName: "camera")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                    }
                    Button {
                        model.showSettings.toggle()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                    }
                }
                Text("KSPlayer ? FFmpeg ? direct/HLS")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.black.opacity(0.55))
        }
    }

    private func settingsPanel() -> some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture {
                    model.showSettings = false
                }
            VStack(alignment: .leading, spacing: 16) {
                Text("播放设置")
                    .font(.headline)
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 6) {
                    Text("拖动灵敏度")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("灵敏度", selection: Binding(
                        get: { model.seekSensitivity },
                        set: { model.setSensitivity($0) }
                    )) {
                        ForEach(SeekSensitivity.allCases, id: \.self) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("引擎")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("AVPlayer（系统硬解）")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("手势")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("单击 控制条 · 双击 快进/退 10s · 长按 2x\n横滑 进度 · 左竖滑 亮度 · 右竖滑 音量")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(20)
            .frame(width: 280, alignment: .leading)
            .background(.black.opacity(0.85))
        }
    }
}
