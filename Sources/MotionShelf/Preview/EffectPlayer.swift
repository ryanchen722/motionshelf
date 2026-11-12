import WebKit

/// 用 WKWebView 載入 effect.html，透過 window.seek(t) 與 window.setParams(params) 控制畫面。
@MainActor
final class EffectPlayer: NSObject, ObservableObject, WKNavigationDelegate {
    @Published private(set) var time: Double = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var error: String?
    @Published var loops = true
    /// 目前效果的 3D 攝影機（每個效果各自存在 UserDefaults）
    @Published private(set) var camera = CameraState()

    /// 輸出解析度；預覽的 CSS 畫布也跟著用這個大小
    @Published var resolution = Resolution(rawValue: UserDefaults.standard.string(forKey: "resolution") ?? "") ?? .landscape {
        didSet {
            UserDefaults.standard.set(resolution.rawValue, forKey: "resolution")
            render(time)
        }
    }
    var renderSize: CGSize { resolution.size }

    let webView: WKWebView
    let params = ParamStore()
    let exporter = Exporter()

    private(set) var effect: Effect?
    /// 每個效果最後一次調整的參數，切換效果再切回來時沿用
    private var savedValues: [String: [String: JSONValue]] = [:]
    private var ready = false
    private var timer: Timer?
    private var playStart: (date: Date, time: Double)?
    private var seekInFlight = false
    private var pendingSeek: Double?

    var duration: Double { effect?.manifest.duration ?? 0 }
    var fps: Int { effect?.manifest.fps ?? 30 }
    var frame: Int { Int((time * Double(fps)).rounded(.down)) }
    var frameCount: Int { Int((duration * Double(fps)).rounded()) }

    override init() {
        let configuration = WKWebViewConfiguration()
        NetworkBlock.install(on: configuration)
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        webView.navigationDelegate = self
        params.onChange = { [weak self] values in self?.pushParams(values) }
    }

    /// 換效果；force 用在 effect.html 改過之後重新載入（會保留目前時間）
    func load(_ effect: Effect?, force: Bool = false) {
        guard force || effect?.id != self.effect?.id else { return }
        pause()
        if !force { time = 0 }
        self.effect = effect
        camera = effect.map { CameraStore.load($0.id) } ?? CameraState()
        ready = false
        error = nil
        params.configure(effect?.manifest.params ?? [], keeping: effect.flatMap { savedValues[$0.id] } ?? [:])
        if let effect {
            webView.loadFileURL(effect.htmlURL, allowingReadAccessTo: effect.folder)
        } else {
            webView.loadHTMLString("", baseURL: nil)
        }
    }

    func export() {
        guard let effect else { return }
        pause()
        exporter.start(effect: effect, paramsJSON: params.json, resolution: resolution, camera: camera)
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard effect != nil, duration > 0, !isPlaying else { return }
        if time >= duration { time = 0 }
        isPlaying = true
        playStart = (Date(), time)
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func pause() {
        timer?.invalidate()
        timer = nil
        playStart = nil
        isPlaying = false
    }

    /// 拖曳時間軸時呼叫；時間對齊到幀，和輸出的畫面一致
    func seek(to t: Double) {
        pause()
        let snapped = (min(max(t, 0), duration) * Double(fps)).rounded() / Double(fps)
        time = snapped
        render(snapped)
    }

    func step(_ frames: Int) {
        seek(to: time + Double(frames) / Double(fps))
    }

    // MARK: - 3D 攝影機

    /// 一幀的長度的一半：時間差在這個範圍內視為同一個關鍵幀
    var keyTolerance: Double { 0.5 / Double(max(fps, 1)) }

    /// 改攝影機設定（開關、透視強度、關鍵幀），存起來並重畫
    func updateCamera(_ change: (inout CameraState) -> Void) {
        guard let effect else { return }
        change(&camera)
        CameraStore.save(camera, for: effect.id)
        render(time)
    }

    /// 在目前時間點改姿勢（拖移預覽畫面時用）：從目前看到的姿勢出發，改完記成這一幀的關鍵幀
    func editCameraPose(_ change: (inout CameraPose) -> Void) {
        pause()
        updateCamera { state in
            var pose = state.pose(at: time)
            change(&pose)
            pose.clamp()
            state.setKey(at: time, pose: pose, tolerance: keyTolerance)
        }
    }

    /// 參數面板改了值：記下來，並立刻重畫目前的時間點
    private func pushParams(_ values: [String: JSONValue]) {
        guard let effect else { return }
        savedValues[effect.id] = values
        guard ready else { return }
        webView.evaluateJavaScript("window.setParams(\(params.json)); 0") { [weak self] _, error in
            guard let self else { return }
            if let error { self.error = L("setParams 發生錯誤：\(Self.message(error))", "setParams error: \(Self.message(error))") }
        }
        render(time)
    }

    private func tick() {
        guard let start = playStart else { return }
        var t = start.time + Date().timeIntervalSince(start.date)
        if t >= duration {
            if loops {
                t = t.truncatingRemainder(dividingBy: duration)
            } else {
                t = duration
                pause()
            }
        }
        time = t
        render(t)
    }

    /// 上一次 seek 還沒畫完時，只保留最新的時間點，避免排隊延遲
    private func render(_ t: Double) {
        guard ready else { return }
        if seekInFlight {
            pendingSeek = t
            return
        }
        seekInFlight = true
        webView.evaluateJavaScript("window.seek(\(t)); " + camera.script(at: t)) { [weak self] _, error in
            guard let self else { return }
            seekInFlight = false
            if let error { self.error = L("seek(t) 發生錯誤：\(Self.message(error))", "seek(t) error: \(Self.message(error))") }
            if let next = pendingSeek {
                pendingSeek = nil
                render(next)
            }
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard effect != nil else { return }
        let json = params.json
        let script = """
        (() => {
          if (typeof window.seek !== 'function' || typeof window.setParams !== 'function') return 'missing';
          window.setParams(\(json));
          return 'ok';
        })()
        """
        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self else { return }
            if let error {
                self.error = L("setParams 發生錯誤：\(Self.message(error))", "setParams error: \(Self.message(error))")
            } else if result as? String != "ok" {
                self.error = L("effect.html 必須提供 window.seek(t) 與 window.setParams(params)", "effect.html must provide window.seek(t) and window.setParams(params)")
            } else {
                ready = true
                render(time)
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.error = L("載入失敗：\(error.localizedDescription)", "Failed to load: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.error = L("載入失敗：\(error.localizedDescription)", "Failed to load: \(error.localizedDescription)")
    }

    /// 取出 JavaScript 錯誤的實際訊息（例如 ReferenceError: x is not defined）
    private static func message(_ error: Error) -> String {
        let info = (error as NSError).userInfo
        return info["WKJavaScriptExceptionMessage"] as? String ?? error.localizedDescription
    }
}

extension JSONValue {
    var any: Any {
        switch self {
        case .string(let value): value
        case .number(let value): value
        case .bool(let value): value
        }
    }
}
