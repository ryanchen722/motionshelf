import AppKit

/// 收件匣：把收集到的 motion prompt 存成 effects/_inbox/<時間戳>-<名稱>/source.md。
/// 按「統一生成」時由 InboxGenerator 在背景執行 Claude Code，把每一筆做成效果資料夾並從這裡移除。
@MainActor
final class Inbox: ObservableObject {
    @Published var isOpen = false
    @Published private(set) var pending: [String] = []
    @Published private(set) var lastSaved: String?
    @Published private(set) var errorMessage: String?

    // 表單草稿；縮成小工具列或關掉收件匣都不會清掉
    @Published var name = ""
    @Published var prompt = ""
    @Published var source = ""
    @Published var usage = ""
    @Published var params = ""

    let folder: URL
    let generator: InboxGenerator
    let analyzer = PromptAnalyzer()
    private var watcher: FolderWatcher?

    init(inboxFolder: URL) {
        folder = inboxFolder
        generator = InboxGenerator(projectFolder: Project.folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        refresh()
        watcher = FolderWatcher(url: folder) { [weak self] in self?.refresh() }
    }

    var canSave: Bool { !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func refresh() {
        let fm = FileManager.default
        let items = ((try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        // 統一生成做完的那筆會留一個 DONE 檔；背景執行的 Claude 沒有權限碰垃圾桶，由 App 丟進去
        for item in items where fm.fileExists(atPath: item.appendingPathComponent("DONE").path) {
            try? fm.trashItem(at: item, resultingItemURL: nil)
        }
        pending = items
            .filter { fm.fileExists(atPath: $0.path) }
            .map(\.lastPathComponent)
            .sorted()
    }

    func save() {
        guard canSave else { return }
        let title = displayName
        let stamp = Self.stampFormatter.string(from: Date())
        let itemFolder = folder.appendingPathComponent("\(stamp)-\(Self.slug(title))", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: itemFolder, withIntermediateDirectories: true)
            try markdown(title: title).write(to: itemFolder.appendingPathComponent("source.md"), atomically: true, encoding: .utf8)
        } catch {
            errorMessage = L("儲存失敗：\(error.localizedDescription)", "Save failed: \(error.localizedDescription)")
            return
        }
        errorMessage = nil
        lastSaved = itemFolder.lastPathComponent
        clear()
        refresh()
    }

    func clear() {
        name = ""
        prompt = ""
        source = ""
        usage = ""
        params = ""
        analyzer.reset()
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    /// 沒填名稱時，用「我想用在」或 prompt 的第一行
    private var displayName: String {
        let candidates = [name, usage, prompt.components(separatedBy: .newlines).first ?? ""]
        let first = candidates.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty } ?? L("未命名", "untitled")
        return String(first.prefix(24))
    }

    /// 和 effects/sample-text/source.md 相同的格式，多了「我想用在」與「要能調整的參數」
    private func markdown(title: String) -> String {
        func section(_ heading: String, _ body: String) -> String {
            "## \(heading)\n\(body.trimmingCharacters(in: .whitespacesAndNewlines))\n"
        }
        return [
            "# \(title)\n",
            section(L("原始 prompt", "Original prompt"), prompt),
            section(L("來源", "Source"), source),
            section(L("我想用在", "Use it for"), usage),
            section(L("要能調整的參數", "Adjustable params"), params),
            splitSection,
            section(L("備註", "Notes"), L("- 收件時間：\(Self.noteFormatter.string(from: Date()))", "- Received: \(Self.noteFormatter.string(from: Date()))")),
        ].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// 分析後勾選的效果；統一生成時每一項各做成一個效果資料夾
    private var splitSection: String {
        let parts = analyzer.included
        guard !parts.isEmpty else { return "" }
        let lines = parts.enumerated().map { "\($0.offset + 1). \($0.element.name)：\($0.element.summary)" }
        return L("## 拆分清單\n", "## Breakdown\n") + lines.joined(separator: "\n") + "\n"
    }

    /// 資料夾名稱不能有 / 和 :，空白換成 -
    private static func slug(_ text: String) -> String {
        let cleaned = text.unicodeScalars.map { scalar -> String in
            if CharacterSet.whitespacesAndNewlines.contains(scalar) || "/:\\?*\"<>|".unicodeScalars.contains(scalar) { return "-" }
            return String(scalar)
        }.joined()
        let collapsed = cleaned.split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")
        return collapsed.isEmpty ? L("未命名", "untitled") : String(collapsed.prefix(24))
    }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    private static let noteFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()
}
