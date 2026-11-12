import AppKit

@main
enum MotionShelfApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // accessory：沒有 Dock 圖示，面板才能出現在別的 App 的全螢幕空間
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
