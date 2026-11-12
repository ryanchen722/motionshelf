import AppKit
import CryptoKit
import UniformTypeIdentifiers
import WebKit

/// 匯入前的檢查結果：errors 一定不能匯入；warnings 讓使用者看過後自己決定
struct EffectCheck {
    var errors: [String] = []
    var warnings: [String] = []
}

/// 效果打包檔 .mseffect：就是 ZIP，只放 effect.html、effect.json、source.md、thumb.png 這四個檔案（平放，沒有資料夾）。
enum EffectPackage {
    static let fileExtension = "mseffect"
    static let allowedFiles: Set<String> = ["effect.html", "effect.json", "source.md", "thumb.png"]
    static let maxFileBytes = 8_000_000
    static let maxTotalBytes = 20_000_000

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static var contentType: UTType { UTType(filenameExtension: fileExtension) ?? .zip }

    // MARK: 匯出

    static func export(_ effect: Effect, to destination: URL) throws {
        let fm = FileManager.default
        let files = ["effect.html", "effect.json", "source.md", "thumb.png"].filter {
            fm.fileExists(atPath: effect.folder.appendingPathComponent($0).path)
        }
        try? fm.removeItem(at: destination)
        let result = run("/usr/bin/zip", ["-q", "-X", "-j", destination.path] + files.map { effect.folder.appendingPathComponent($0).path })
        guard result.status == 0, fm.fileExists(atPath: destination.path) else {
            throw Failure(message: L("打包失敗：\(result.output)", "Packing failed: \(result.output)"))
        }
    }

    // MARK: 解開（只做結構檢查，內容檢查在 EffectValidator）

    /// 解到暫存資料夾並回傳；壓縮檔結構不對就丟錯誤。呼叫的人要負責刪掉暫存資料夾。
    static func unpack(_ archive: URL) throws -> URL {
        let fm = FileManager.default
        let names = run("/usr/bin/unzip", ["-Z1", archive.path])
        guard names.status == 0 else {
            throw Failure(message: L("不是有效的 .mseffect（ZIP）檔案。", "This is not a valid .mseffect (ZIP) file."))
        }
        let entries = names.output.split(separator: "\n").map(String.init)
        let unknown = entries.filter { !allowedFiles.contains($0) }
        guard unknown.isEmpty else {
            throw Failure(message: L("壓縮檔含有不允許的檔案或路徑：\(unknown.prefix(3).joined(separator: "、"))。只允許 effect.html、effect.json、source.md、thumb.png。",
                                     "The archive contains files or paths that aren't allowed: \(unknown.prefix(3).joined(separator: ", ")). Only effect.html, effect.json, source.md and thumb.png are allowed."))
        }
        guard !entries.isEmpty, entries.count <= allowedFiles.count, Set(entries).count == entries.count else {
            throw Failure(message: L("壓縮檔裡的檔案數量不對，或有重複的檔名。", "The archive has the wrong number of files or duplicate names."))
        }

        // 權限欄第一個字元是 l 代表符號連結；同時用標示的大小擋掉超大檔
        var total = 0
        for line in run("/usr/bin/unzip", ["-Z", archive.path]).output.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 9, parts[0].count == 10, "-ld?".contains(parts[0].first!) else { continue }
            if parts[0].first == "l" || parts[0].first == "d" {
                throw Failure(message: L("壓縮檔含有符號連結或資料夾。", "The archive contains a symbolic link or folder."))
            }
            let size = Int(parts[3]) ?? Int.max
            total += size
            guard size <= maxFileBytes, total <= maxTotalBytes else {
                throw Failure(message: L("壓縮檔解開後太大（單一檔案上限 8 MB、總共 20 MB）。", "The archive is too large once unpacked (8 MB per file, 20 MB total)."))
            }
        }

        let temp = fm.temporaryDirectory.appendingPathComponent("MotionShelf-import-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        let result = run("/usr/bin/unzip", ["-q", "-o", "-d", temp.path, archive.path])
        guard result.status == 0 else {
            try? fm.removeItem(at: temp)
            throw Failure(message: L("解開失敗：\(result.output)", "Unpacking failed: \(result.output)"))
        }
        // 解開後再確認一次：只能是普通檔案，大小也要符合
        for url in (try? fm.contentsOfDirectory(at: temp, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey])) ?? [] {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey])
            if !allowedFiles.contains(url.lastPathComponent) || values?.isRegularFile != true || values?.isSymbolicLink == true
                || (values?.fileSize ?? 0) > maxFileBytes {
                try? fm.removeItem(at: temp)
                throw Failure(message: L("壓縮檔內容不符合規定。", "The archive contents are not allowed."))
            }
        }
        return temp
    }

    private static func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (-1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    }
}

/// 檢查一個解開後的效果資料夾：格式對不對、有沒有可疑的程式碼、能不能真的畫出畫面
enum EffectValidator {
    /// 靜態掃描 effect.html：效果只該用 window.seek(t) 畫畫面，不需要這些能力
    private static let suspicious: [(pattern: String, zh: String, en: String)] = [
        (#"\bfetch\s*\("#, "用 fetch 連網", "makes network requests with fetch"),
        (#"XMLHttpRequest"#, "用 XMLHttpRequest 連網", "makes network requests with XMLHttpRequest"),
        (#"\bWebSocket\b|\bEventSource\b"#, "使用 WebSocket／EventSource 連線", "opens a WebSocket / EventSource connection"),
        (#"sendBeacon"#, "用 sendBeacon 傳送資料", "sends data with sendBeacon"),
        (#"\beval\s*\(|new\s+Function\s*\(|\bFunction\s*\(\s*['\"`]"#, "用 eval／new Function 執行動態產生的程式碼", "runs generated code with eval / new Function"),
        (#"\bimport\s*\(|\bimportScripts\s*\("#, "動態載入其他程式碼", "dynamically loads other code"),
        (#"<script[^>]+src\s*="#, "載入外部 script 檔案", "loads an external script file"),
        (#"<iframe|<object|<embed|<form"#, "含有 iframe／object／embed／form 元素", "contains an iframe / object / embed / form element"),
        (#"window\.open|location\s*\.\s*(href|assign|replace)\s*=|location\.(assign|replace)\s*\(|document\.location"#, "嘗試開新視窗或跳轉頁面", "tries to open a window or navigate away"),
        (#"document\.cookie|localStorage|sessionStorage|indexedDB"#, "讀寫 cookie 或瀏覽器儲存空間", "reads or writes cookies or browser storage"),
        (#"navigator\.(clipboard|geolocation|mediaDevices|sendBeacon)"#, "使用剪貼簿、定位或相機麥克風", "uses the clipboard, location, camera or microphone"),
        (#"document\.write\s*\("#, "用 document.write 改寫頁面", "rewrites the page with document.write"),
        (#"\batob\s*\(|fromCharCode\s*\([^)]{40,}"#, "含有疑似編碼過的內容（atob／大量 fromCharCode）", "contains what looks like encoded content (atob / long fromCharCode)"),
    ]

    /// 官方 Three.js r160（skills/make-effect/vendor/three.min.js，去掉頭尾空白後的 SHA-256）。
    /// 內容完全相同的 script 區塊不掃描，因為裡面本來就有網址和 console.warn；只要差一個字就照常掃描。
    private static let knownThreeHash = "18122954124850625d374069e394974bf78768c747390b807c9d0800f121ffd8"

    private static func removingKnownLibraries(from html: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"<script>([\s\S]*?)</script>"#) else { return html }
        var result = html
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).reversed() {
            guard let whole = Range(match.range, in: html), let body = Range(match.range(at: 1), in: html) else { continue }
            let text = html[body].trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count > 100_000 else { continue }
            let digest = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
            if digest == knownThreeHash, let range = Range(NSRange(whole, in: html), in: result) { result.removeSubrange(range) }
        }
        return result
    }

    static func check(folder: URL) -> EffectCheck {
        var result = EffectCheck()
        let fm = FileManager.default

        // effect.json
        guard let jsonData = try? Data(contentsOf: folder.appendingPathComponent("effect.json")) else {
            result.errors.append(L("缺少 effect.json。", "effect.json is missing."))
            return result
        }
        do {
            let manifest = try JSONDecoder().decode(EffectManifest.self, from: jsonData)
            if manifest.name.trimmingCharacters(in: .whitespaces).isEmpty { result.errors.append(L("effect.json 的 name 是空的。", "The name in effect.json is empty.")) }
            if !(0.1...600).contains(manifest.duration) { result.errors.append(L("duration 必須在 0.1 到 600 秒之間。", "duration must be between 0.1 and 600 seconds.")) }
            if !(1...120).contains(manifest.fps) { result.errors.append(L("fps 必須在 1 到 120 之間。", "fps must be between 1 and 120.")) }
            if manifest.params.count > 60 { result.errors.append(L("參數太多（上限 60 個）。", "Too many params (max 60).")) }
            var seen = Set<String>()
            for param in manifest.params {
                if param.key.isEmpty || param.key.count > 60 { result.errors.append(L("有參數的 key 是空的或太長。", "A param key is empty or too long.")); continue }
                if !seen.insert(param.key).inserted { result.errors.append(L("參數 key 重複：\(param.key)", "Duplicate param key: \(param.key)")) }
                if param.type == .select, (param.options ?? []).isEmpty {
                    result.errors.append(L("選單參數「\(param.key)」沒有 options。", "Select param \"\(param.key)\" has no options."))
                }
                if let min = param.min, let max = param.max, min > max {
                    result.errors.append(L("參數「\(param.key)」的 min 比 max 大。", "Param \"\(param.key)\" has min greater than max."))
                }
            }
        } catch {
            result.errors.append(L("effect.json 格式不正確：\(error.localizedDescription)", "effect.json is not valid: \(error.localizedDescription)"))
        }

        // effect.html
        guard let html = try? String(contentsOf: folder.appendingPathComponent("effect.html"), encoding: .utf8) else {
            result.errors.append(L("缺少 effect.html，或不是 UTF-8 文字。", "effect.html is missing or isn't UTF-8 text."))
            return result
        }
        if !html.contains("seek") || !html.contains("setParams") {
            result.errors.append(L("effect.html 沒有定義 window.seek 或 window.setParams。", "effect.html doesn't define window.seek or window.setParams."))
        }
        let scanned = removingKnownLibraries(from: html)
        for rule in suspicious where scanned.range(of: rule.pattern, options: .regularExpression) != nil {
            result.warnings.append(L(rule.zh, rule.en))
        }
        // 外部網址（SVG／XML 的命名空間不算）
        let regex = try? NSRegularExpression(pattern: #"https?://[^\s"'<>)\\]+"#)
        let whole = NSRange(scanned.startIndex..., in: scanned)
        let urls = (regex?.matches(in: scanned, range: whole) ?? []).compactMap { Range($0.range, in: scanned).map { String(scanned[$0]) } }
            .filter { !$0.contains("w3.org") }
        if !urls.isEmpty {
            result.warnings.append(L("含有外部網址：\(Array(Set(urls)).sorted().prefix(3).joined(separator: "、"))", "Contains external URLs: \(Array(Set(urls)).sorted().prefix(3).joined(separator: ", "))"))
        }

        // thumb.png 要真的是 PNG；source.md 只是文字
        if let thumb = try? Data(contentsOf: folder.appendingPathComponent("thumb.png")),
           !thumb.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            result.errors.append(L("thumb.png 不是真的 PNG 圖片。", "thumb.png is not a real PNG image."))
        }
        if fm.fileExists(atPath: folder.appendingPathComponent("source.md").path),
           (try? String(contentsOf: folder.appendingPathComponent("source.md"), encoding: .utf8)) == nil {
            result.errors.append(L("source.md 不是 UTF-8 文字。", "source.md isn't UTF-8 text."))
        }
        return result
    }

    /// 真的載入一次：能執行、有 window.seek／setParams、用預設參數畫第 0 秒不出錯。網路已封鎖。
    @MainActor
    static func probe(folder: URL) async -> String? {
        let configuration = WKWebViewConfiguration()
        NetworkBlock.install(on: configuration)
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 640, height: 360), configuration: configuration)
        let loader = ProbeLoader()
        webView.navigationDelegate = loader
        webView.loadFileURL(folder.appendingPathComponent("effect.html"), allowingReadAccessTo: folder)
        guard await loader.waitForLoad(timeout: 8) else {
            return L("effect.html 載入失敗或逾時。", "effect.html failed to load or timed out.")
        }
        var defaults: [String: Any] = [:]
        if let data = try? Data(contentsOf: folder.appendingPathComponent("effect.json")),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for param in json["params"] as? [[String: Any]] ?? [] {
                if let key = param["key"] as? String, let value = param["default"] { defaults[key] = value }
            }
        }
        let paramsJSON = (try? JSONSerialization.data(withJSONObject: defaults)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let script = """
        (function() {
          if (typeof window.seek !== 'function') return 'window.seek is not a function';
          if (typeof window.setParams !== 'function') return 'window.setParams is not a function';
          try { window.setParams(\(paramsJSON)); window.seek(0); window.seek(0.5); } catch (e) { return 'error: ' + e; }
          return 'ok';
        })()
        """
        let output = try? await webView.evaluateJavaScript(script) as? String
        if output == "ok" { return nil }
        return L("這個效果沒辦法正常畫出畫面：\(output ?? "沒有回應")", "This effect can't draw a frame: \(output ?? "no response")")
    }
}

@MainActor
private final class ProbeLoader: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Bool, Never>?

    func waitForLoad(timeout: Double) async -> Bool {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in self?.finish(false) }
        }
    }

    private func finish(_ ok: Bool) {
        continuation?.resume(returning: ok)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(true) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(false) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(false) }
}

/// 匯入／匯出的操作流程：選檔、檢查、警告、處理重複名稱
@MainActor
enum EffectTransfer {
    static func export(_ effect: Effect) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [EffectPackage.contentType]
        panel.nameFieldStringValue = "\(effect.id).\(EffectPackage.fileExtension)"
        panel.message = L("匯出「\(effect.name)」，把檔案傳給別人就能使用。", "Export \"\(effect.name)\". Send the file to anyone to share it.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try EffectPackage.export(effect, to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            alert(L("匯出失敗", "Export failed"), error.localizedDescription, style: .warning)
        }
    }

    static func chooseAndImport(into library: EffectLibrary) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [EffectPackage.contentType]
        panel.allowsMultipleSelection = true
        panel.message = L("選擇要匯入的效果檔（.mseffect）", "Choose effect files to import (.mseffect)")
        guard panel.runModal() == .OK else { return }
        Task { for url in panel.urls { await importFile(url, into: library) } }
    }

    static func importFile(_ archive: URL, into library: EffectLibrary) async {
        guard archive.pathExtension.lowercased() == EffectPackage.fileExtension else {
            return alert(L("無法匯入", "Can't import"), L("只能匯入 .mseffect 檔案。", "Only .mseffect files can be imported."), style: .warning)
        }
        let temp: URL
        do { temp = try EffectPackage.unpack(archive) } catch {
            return alert(L("無法匯入「\(archive.lastPathComponent)」", "Can't import \"\(archive.lastPathComponent)\""), error.localizedDescription, style: .critical)
        }
        defer { try? FileManager.default.removeItem(at: temp) }

        var check = EffectValidator.check(folder: temp)
        if check.errors.isEmpty, let problem = await EffectValidator.probe(folder: temp) { check.errors.append(problem) }
        if !check.errors.isEmpty {
            return alert(L("這個效果沒有通過檢查，沒有匯入", "This effect failed the checks and was not imported"),
                         check.errors.map { "• " + $0 }.joined(separator: "\n"), style: .critical)
        }
        if !check.warnings.isEmpty {
            let message = L("這個效果的程式碼有以下可疑的地方：", "This effect's code has the following suspicious things:")
                + "\n\n" + check.warnings.map { "• " + $0 }.joined(separator: "\n")
                + "\n\n" + L("效果是會執行的程式碼。預覽和輸出時網路已被封鎖，但只有信任來源的檔案才建議匯入。", "Effects are code that runs. The network is blocked during preview and export, but only import files from sources you trust.")
            guard confirm(L("匯入有風險的效果嗎？", "Import this risky effect?"), message, ok: L("仍要匯入", "Import anyway"), cancel: L("取消", "Cancel")) else { return }
        }

        let base = slug(archive.deletingPathExtension().lastPathComponent)
        var id = base
        let destination = { library.folder.appendingPathComponent($0, isDirectory: true) }
        if FileManager.default.fileExists(atPath: destination(id).path) {
            switch conflict(id) {
            case .cancel: return
            case .replace:
                do { try FileManager.default.trashItem(at: destination(id), resultingItemURL: nil) } catch {
                    return alert(L("無法覆蓋", "Can't replace"), error.localizedDescription, style: .warning)
                }
            case .keepBoth:
                var n = 2
                while FileManager.default.fileExists(atPath: destination("\(base)-\(n)").path) { n += 1 }
                id = "\(base)-\(n)"
            }
        }

        // 在 source.md 記下來源，之後分得出哪些是別人的
        let note = "\n\n---\n" + L("匯入自 \(archive.lastPathComponent)（\(Date().formatted(date: .abbreviated, time: .omitted))）", "Imported from \(archive.lastPathComponent) (\(Date().formatted(date: .abbreviated, time: .omitted)))") + "\n"
        let sourceURL = temp.appendingPathComponent("source.md")
        let existing = (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""
        try? (existing + note).write(to: sourceURL, atomically: true, encoding: .utf8)

        do {
            try FileManager.default.copyItem(at: temp, to: destination(id))
        } catch {
            return alert(L("匯入失敗", "Import failed"), error.localizedDescription, style: .warning)
        }
        library.reload()
        library.selectedID = id
        library.inbox.isOpen = false
    }

    /// 資料夾名稱：只留英數、底線和連字號
    private static func slug(_ name: String) -> String {
        let cleaned = name.lowercased().map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" }
        let text = String(cleaned).split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")
        return text.isEmpty ? "imported" : String(text.prefix(60))
    }

    private enum Conflict { case replace, keepBoth, cancel }

    private static func conflict(_ id: String) -> Conflict {
        let alert = NSAlert()
        alert.messageText = L("已經有同名的效果「\(id)」", "An effect named \"\(id)\" already exists")
        alert.informativeText = L("要怎麼處理？覆蓋的舊效果會移到垃圾桶。", "What should happen? A replaced effect goes to the Trash.")
        alert.addButton(withTitle: L("兩個都留（另存新名）", "Keep both"))
        alert.addButton(withTitle: L("覆蓋舊的", "Replace"))
        alert.addButton(withTitle: L("取消", "Cancel"))
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .keepBoth
        case .alertSecondButtonReturn: return .replace
        default: return .cancel
        }
    }

    private static func confirm(_ title: String, _ message: String, ok: String, cancel: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: cancel)   // 預設按鈕是取消
        alert.addButton(withTitle: ok)
        return alert.runModal() == .alertSecondButtonReturn
    }

    private static func alert(_ title: String, _ message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: L("好", "OK"))
        alert.runModal()
    }
}
