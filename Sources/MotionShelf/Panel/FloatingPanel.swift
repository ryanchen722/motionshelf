import AppKit
import SwiftUI

final class PanelState: ObservableObject {
    @Published var isMini = false
}

/// 永遠浮在最上層的面板，包括其他 App 全螢幕時；點它不會搶走 DaVinci 的焦點。
@MainActor
final class FloatingPanel: NSPanel {
    let state = PanelState()
    private let player: EffectPlayer

    /// 最小就是預設大小：視窗縮小時字體不會跟著縮，元件會擠在一起。螢幕高度放不下時才縮小一點。
    private static var expandedMinSize: NSSize {
        let visible = NSScreen.main?.visibleFrame.height ?? 1080
        let height = min(1012, max(694, visible - 40))
        return NSSize(width: (height * skinRatio.width / skinRatio.height).rounded(), height: height)
    }
    /// 照片外框的比例（Support/skin.png 是 1423×1422），視窗只能照這個比例縮放
    private static let skinRatio = NSSize(width: 1423, height: 1422)
    private static let miniSize = NSSize(width: 380, height: 54)
    private static let frameKey = "skinFrame"

    init(library: EffectLibrary, player: EffectPlayer) {
        let saved = UserDefaults.standard.string(forKey: Self.frameKey).map(NSRectFromString)
        var frame = saved ?? NSRect(x: 200, y: 200, width: 980, height: 1014)
        frame.size.width = max(frame.width, Self.expandedMinSize.width)
        frame.size.height = (frame.width * Self.skinRatio.height / Self.skinRatio.width).rounded()
        self.player = player
        super.init(
            contentRect: frame,
            styleMask: [.titled, .resizable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false

        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
        isOpaque = false
        backgroundColor = .clear
        // 可愛配色是照淺色設計的，不跟系統深色模式
        appearance = NSAppearance(named: .aqua)
        minSize = Self.expandedMinSize
        contentAspectRatio = Self.skinRatio

        let host = NSHostingView(rootView: RootView(
            state: state,
            library: library,
            player: player,
            actions: PanelActions(
                toggleMini: { [weak self] in self?.setMini(!(self?.state.isMini ?? false)) },
                hide: { [weak self] in self?.orderOut(nil) }
            )
        ))
        host.sizingOptions = []
        contentView = host
        setFrame(frame, display: false)

        NotificationCenter.default.addObserver(self, selector: #selector(rememberFrame), name: NSWindow.didMoveNotification, object: self)
        NotificationCenter.default.addObserver(self, selector: #selector(rememberFrame), name: NSWindow.didResizeNotification, object: self)
    }

    // 讓之後的文字輸入框可以打字
    override var canBecomeKey: Bool { true }

    /// 空白鍵播放／暫停。只在面板是目前的按鍵視窗（例如剛點過預覽畫面）時才會收到，
    /// 所以平常在 DaVinci 按空白鍵不受影響；在文字輸入框裡打字時（欄位編輯器是 NSTextView）照常輸入空白。
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let blocked: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        if event.type == .keyDown, event.keyCode == 49, event.modifierFlags.intersection(blocked).isEmpty,
           !(firstResponder is NSTextView) {
            if !event.isARepeat { player.togglePlay() }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    func toggleVisible() {
        if isVisible {
            orderOut(nil)
        } else {
            orderFrontRegardless()
        }
    }

    /// 縮成小工具列或展開；以左上角為基準，位置不會跳。
    func setMini(_ mini: Bool) {
        guard mini != state.isMini else { return }
        let top = frame.maxY
        if mini {
            rememberFrame()
            state.isMini = true
            styleMask.remove(.resizable)
            minSize = Self.miniSize
            contentAspectRatio = Self.miniSize
            let size = Self.miniSize
            setFrame(NSRect(x: frame.minX, y: top - size.height, width: size.width, height: size.height), display: true, animate: true)
        } else {
            let saved = UserDefaults.standard.string(forKey: Self.frameKey).map(NSRectFromString)
            var size = saved?.size ?? NSSize(width: 980, height: 1014)
            size.width = max(size.width, Self.expandedMinSize.width)
            size.height = (size.width * Self.skinRatio.height / Self.skinRatio.width).rounded()
            styleMask.insert(.resizable)
            minSize = Self.expandedMinSize
            contentAspectRatio = Self.skinRatio
            setFrame(NSRect(x: frame.minX, y: top - size.height, width: size.width, height: size.height), display: true, animate: true)
            state.isMini = false
        }
    }

    @objc private func rememberFrame() {
        guard !state.isMini else { return }
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: Self.frameKey)
    }
}
