import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: FloatingPanel!
    private var hotKey: HotKey?
    private var statusItem: NSStatusItem!
    private let library = EffectLibrary()
    private let player = EffectPlayer()

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = FloatingPanel(library: library, player: player)
        hotKey = HotKey(keyCode: kVK_Space, modifiers: optionKey) { [weak self] in
            self?.panel.toggleVisible()
        }
        setUpMainMenu()
        setUpStatusItem()
        panel.orderFrontRegardless()
        // 第一次開啟：先選 AI 和資料夾
        if !Settings.setupDone { SetupWindow.show(firstRun: true) }
    }

    // 選單列圖示：快捷鍵失效時的備用入口
    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: "MotionShelf")

        let menu = NSMenu()
        let toggle = NSMenuItem(title: L("顯示／隱藏面板（⌥Space）", "Show / Hide Panel (⌥Space)"), action: #selector(toggleVisible), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        let mini = NSMenuItem(title: L("切換小工具列", "Toggle Mini Bar"), action: #selector(toggleMini), keyEquivalent: "")
        mini.target = self
        menu.addItem(mini)
        if hotKey == nil {
            menu.addItem(NSMenuItem(title: L("⚠️ ⌥Space 已被其他 App 佔用", "⚠️ ⌥Space is used by another app"), action: nil, keyEquivalent: ""))
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("結束 MotionShelf", "Quit MotionShelf"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    // 看不到，但讓 ⌘Q、⌘C、⌘V 等快捷鍵在面板裡有效
    private func setUpMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: L("結束 MotionShelf", "Quit MotionShelf"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: L("編輯", "Edit"))
        editMenu.addItem(NSMenuItem(title: L("還原", "Undo"), action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: L("剪下", "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: L("拷貝", "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: L("貼上", "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: L("全選", "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu
        main.addItem(editItem)

        NSApp.mainMenu = main
    }

    @objc private func toggleVisible() { panel.toggleVisible() }
    @objc private func toggleMini() { panel.setMini(!panel.state.isMini) }
}
