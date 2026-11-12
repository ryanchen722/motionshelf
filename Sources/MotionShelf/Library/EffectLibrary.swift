import AppKit

/// 掃描 effects/ 資料夾，並在有新資料夾放進來時自動重新掃描。
@MainActor
final class EffectLibrary: ObservableObject {
    @Published private(set) var effects: [Effect] = []
    @Published private(set) var problems: [EffectProblem] = []
    @Published private(set) var favorites: Set<String>
    /// 使用者自己建立的分類，存在 effects/_categories.json，沒有效果也會顯示
    @Published private(set) var customCategories: [String] = []
    @Published var selectedID: String? {
        didSet { UserDefaults.standard.set(selectedID, forKey: "selectedEffect") }
    }

    let folder: URL
    let inbox: Inbox
    let customize: CustomizeChat

    private var watcher: FolderWatcher?
    private var retries = 0

    var selected: Effect? { effects.first { $0.id == selectedID } }

    private var categoriesFile: URL { folder.appendingPathComponent("_categories.json") }

    /// 固定的六個分類、自訂分類，再加上 effect.json 裡寫了但不在清單中的分類
    var categories: [String] {
        var all = Effect.categories
        for name in customCategories + effects.map(\.category).sorted() where !all.contains(name) { all.append(name) }
        return all
    }

    func isCustom(_ category: String) -> Bool { customCategories.contains(category) }

    init() {
        folder = Settings.effectsFolder
        favorites = Set(UserDefaults.standard.stringArray(forKey: "favoriteEffects") ?? [])
        selectedID = UserDefaults.standard.string(forKey: "selectedEffect")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        inbox = Inbox(inboxFolder: Settings.inboxFolder)
        customize = CustomizeChat(projectFolder: Project.folder)
        reload()
        inbox.generator.onFinish = { [weak self] in
            self?.reload()
            self?.inbox.refresh()
        }
        watcher = FolderWatcher(url: folder) { [weak self] in self?.reload() }
    }

    func reload() {
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var loaded: [Effect] = []
        var failed: [EffectProblem] = []
        // 開頭是 _ 的資料夾（例如 _inbox）不是效果
        for url in folders where !url.lastPathComponent.hasPrefix("_")
            && (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            switch Effect.load(from: url) {
            case .success(let effect): loaded.append(effect)
            case .failure(let problem): failed.append(problem)
            }
        }

        if let data = try? Data(contentsOf: categoriesFile),
           let names = try? JSONDecoder().decode([String].self, from: data) {
            customCategories = names
        }
        effects = loaded
        let order = categories
        effects = loaded.sorted {
            let a = order.firstIndex(of: $0.category) ?? order.count
            let b = order.firstIndex(of: $1.category) ?? order.count
            return a != b ? a < b : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        problems = failed.sorted { $0.id < $1.id }
        // 資料夾剛建立、裡面的檔案還在寫入時會讀不到；資料夾監看只看得到第一層，所以過一下自己再掃一次
        if !failed.isEmpty && retries < 10 {
            retries += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.reload() }
        } else if failed.isEmpty {
            retries = 0
        }
        if selected == nil { selectedID = effects.first?.id }
    }

    func isFavorite(_ effect: Effect) -> Bool { favorites.contains(effect.id) }

    func toggleFavorite(_ effect: Effect) {
        if favorites.contains(effect.id) {
            favorites.remove(effect.id)
        } else {
            favorites.insert(effect.id)
        }
        UserDefaults.standard.set(Array(favorites), forKey: "favoriteEffects")
    }

    /// 「客製化」正在改的效果不能刪，避免 agent 改到一半資料夾就不見了
    func canTrash(_ effect: Effect) -> Bool {
        !(customize.isRunning && customize.effect?.id == effect.id)
    }

    /// 把效果資料夾丟到垃圾桶（可以從垃圾桶還原）。刪掉的是目前選取的效果就改選下一個。
    /// 失敗時回傳錯誤訊息
    func trash(_ effect: Effect) -> String? {
        guard canTrash(effect) else {
            return L("「客製化」正在修改這個效果，等它完成後再刪除。", "Customize is still editing this effect. Delete it after it finishes.")
        }
        let index = effects.firstIndex { $0.id == effect.id }
        do {
            try FileManager.default.trashItem(at: effect.folder, resultingItemURL: nil)
        } catch {
            return L("沒辦法丟到垃圾桶：\(error.localizedDescription)", "Couldn't move it to the Trash: \(error.localizedDescription)")
        }
        if favorites.remove(effect.id) != nil {
            UserDefaults.standard.set(Array(favorites), forKey: "favoriteEffects")
        }
        if selectedID == effect.id {
            let rest = effects.filter { $0.id != effect.id }
            selectedID = index.flatMap { rest.indices.contains($0) ? rest[$0].id : rest.last?.id }
        }
        reload()
        return nil
    }

    /// 新增分類；名稱重複或空白就不加。回傳整理過的名稱
    @discardableResult
    func addCategory(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        if !categories.contains(name) {
            customCategories.append(name)
            saveCategories()
        }
        return name
    }

    /// 只有沒有效果的自訂分類可以刪
    func removeCategory(_ name: String) {
        guard isCustom(name), !effects.contains(where: { $0.category == name }) else { return }
        customCategories.removeAll { $0 == name }
        saveCategories()
    }

    /// 改寫 effect.json 裡的 "category"，其他內容和排版都不動
    func move(_ effect: Effect, to category: String) {
        let url = effect.folder.appendingPathComponent("effect.json")
        guard category != effect.category,
              var text = try? String(contentsOf: url, encoding: .utf8),
              let range = text.range(of: #""category"\s*:\s*"(?:[^"\\]|\\.)*""#, options: .regularExpression),
              let encoded = try? JSONEncoder().encode(category),
              let value = String(data: encoded, encoding: .utf8) else { return }
        text.replaceSubrange(range, with: "\"category\": \(value)")
        try? text.write(to: url, atomically: true, encoding: .utf8)
        reload()
    }

    private func saveCategories() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        try? encoder.encode(customCategories).write(to: categoriesFile, options: .atomic)
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }
}

/// 專案資料夾（裡面有 effects/、tools/）。
/// ./run.sh 把 App 放在專案的 build/ 裡，所以從 App 的位置往上找有 Package.swift 的資料夾；
/// 找不到時用環境變數 MOTIONSHELF_HOME，再不行就用 ~/MotionShelf。
enum Project {
    static let folder: URL = {
        if let home = ProcessInfo.processInfo.environment["MOTIONSHELF_HOME"] { return URL(fileURLWithPath: home) }
        var url = Bundle.main.bundleURL
        for _ in 0..<5 {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) { return url }
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("MotionShelf")
    }()
}
