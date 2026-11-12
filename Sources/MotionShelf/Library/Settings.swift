import AppKit
import WebKit

/// 使用者可以自己決定的資料夾。存在 UserDefaults；沒設定過就用預設位置。
/// Folders the user can choose. Stored in UserDefaults; defaults apply until set.
enum Settings {
    private static let effectsKey = "effectsFolder"
    private static let inboxKey = "inboxFolder"
    private static let exportKey = "exportFolder"
    private static let setupKey = "setupDone"

    static var defaultEffects: URL { Project.folder.appendingPathComponent("effects", isDirectory: true) }
    static var defaultInbox: URL { effectsFolder.appendingPathComponent("_inbox", isDirectory: true) }
    static var defaultExport: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies/MotionShelf", isDirectory: true)
    }

    static var effectsFolder: URL { stored(effectsKey) ?? defaultEffects }
    static var inboxFolder: URL { stored(inboxKey) ?? defaultInbox }
    static var exportFolder: URL { stored(exportKey) ?? defaultExport }

    static var isEffectsCustom: Bool { effectsFolder.standardizedFileURL != defaultEffects.standardizedFileURL }
    static var isInboxCustom: Bool { inboxFolder.standardizedFileURL != defaultInbox.standardizedFileURL }

    static var setupDone: Bool {
        get { UserDefaults.standard.bool(forKey: setupKey) }
        set { UserDefaults.standard.set(newValue, forKey: setupKey) }
    }

    /// 存起來；跟預設一樣就清掉，之後預設位置改變時才會跟著走
    static func save(effects: URL, inbox: URL, export: URL) {
        set(effectsKey, effects, default: defaultEffects)
        set(inboxKey, inbox, default: effects.appendingPathComponent("_inbox", isDirectory: true))
        set(exportKey, export, default: defaultExport)
    }

    private static func stored(_ key: String) -> URL? {
        guard let path = UserDefaults.standard.string(forKey: key), !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private static func set(_ key: String, _ url: URL, default fallback: URL) {
        if url.standardizedFileURL == fallback.standardizedFileURL {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(url.path, forKey: key)
        }
    }

    /// 重新啟動 App（資料夾換了，要重新掃描）
    @MainActor
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.6; open \"$0\"", path]
        try? task.run()
        NSApp.terminate(nil)
    }
}

/// 預覽和輸出時封鎖所有網路連線：效果只該靠自己的檔案畫出畫面，不能把資料送出去，也不能載入遠端程式碼。
/// Blocks every network request while previewing/exporting, so an effect can neither send data out nor load remote code.
@MainActor
enum NetworkBlock {
    private static var compiled: WKContentRuleList?

    /// 第一次用時編譯規則（幾毫秒），之後共用
    static func install(on configuration: WKWebViewConfiguration) {
        if compiled == nil {
            let rules = #"[{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}},{"trigger":{"url-filter":"^wss?://"},"action":{"type":"block"}},{"trigger":{"url-filter":"^ftp://"},"action":{"type":"block"}}]"#
            var done = false
            WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "MotionShelfNoNetwork", encodedContentRuleList: rules) { list, _ in
                compiled = list
                done = true
            }
            let deadline = Date().addingTimeInterval(3)
            while !done && Date() < deadline { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
        }
        if let compiled { configuration.userContentController.add(compiled) }
    }
}
