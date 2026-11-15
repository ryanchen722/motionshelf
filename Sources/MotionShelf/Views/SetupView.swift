import AppKit
import SwiftUI

/// 設定視窗：第一次開啟時選 AI 和資料夾，之後從齒輪按鈕也能打開。
/// Settings window: shown on first launch to pick the AI and folders; reopen from the gear button.
@MainActor
final class SetupWindow {
    private static var window: NSWindow?

    static func show(firstRun: Bool) {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 720), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = L("MotionShelf 設定", "MotionShelf Settings")
        window.isReleasedWhenClosed = false
        window.level = .modalPanel
        window.contentView = NSHostingView(rootView: SetupView(firstRun: firstRun) { close() })
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    static func close() {
        window?.close()
        window = nil
    }
}

private enum AgentChoice: String, CaseIterable, Identifiable {
    case claude, codex, gemini, custom, none
    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex CLI"
        case .gemini: return "Gemini CLI"
        case .custom: return L("自訂指令", "Custom command")
        case .none: return L("先不使用 AI", "No AI for now")
        }
    }

    /// 要在終端機找的指令名稱
    var executable: String? {
        switch self {
        case .claude: return "claude"
        case .codex: return "codex"
        case .gemini: return "gemini"
        default: return nil
        }
    }

    /// 官方的安裝指令（Claude：code.claude.com/docs/en/setup；Codex：learn.chatgpt.com/docs/codex/cli）
    var installCommand: String? {
        switch self {
        case .claude: return InstallCommand.claude
        case .codex: return InstallCommand.codex
        default: return nil
        }
    }

    /// 常見的非互動寫法（Codex 依官方文件；Gemini 沒有實測過，請自己對照官方文件）
    var presetCommand: String {
        switch self {
        case .codex: return Agent.codexCommand
        case .gemini: return "gemini --yolo -p {prompt}"
        default: return ""
        }
    }
}

private struct SetupView: View {
    let firstRun: Bool
    let onClose: () -> Void

    @State private var choice: AgentChoice
    @State private var modelPreset: String
    @State private var customModel: String
    @State private var command: String
    @State private var installed: Bool?
    @State private var nodeStatus: NodeStatus?
    @State private var chromeFound: Bool?
    @State private var effects = Settings.effectsFolder
    @State private var inbox = Settings.inboxFolder
    @State private var export = Settings.exportFolder

    private static let models = ["", "opus", "sonnet", "haiku"]

    init(firstRun: Bool, onClose: @escaping () -> Void) {
        self.firstRun = firstRun
        self.onClose = onClose
        let config = Agent.config
        let known: AgentChoice = {
            switch config.agent {
            case "custom":
                let command = config.command ?? ""
                if command.hasPrefix("codex") { return .codex }
                if command.hasPrefix("gemini") { return .gemini }
                return .custom
            case "none": return .none
            default: return .claude
            }
        }()
        _choice = State(initialValue: known)
        let model = config.model ?? ""
        _modelPreset = State(initialValue: Self.models.contains(model) ? model : "custom")
        _customModel = State(initialValue: Self.models.contains(model) ? "" : model)
        _command = State(initialValue: config.command ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(firstRun ? L("歡迎使用 MotionShelf", "Welcome to MotionShelf") : L("設定", "Settings"))
                    .font(.title2.weight(.heavy))
                Spacer()
                Button { HelpWindow.show() } label: { Image(systemName: "questionmark.circle") }
                    .buttonStyle(.plain).font(.title3)
                    .help(L("說明：怎麼安裝和登入 AI", "Help: installing and signing in to an AI"))
            }
            if firstRun {
                Text(L("先選你要用哪一個 AI 來做效果，以及檔案要放在哪裡。這些之後都可以從齒輪按鈕改。", "Pick which AI builds your effects and where files are kept. You can change all of this later from the gear button."))
                    .foregroundStyle(.secondary)
            }

            GroupBox(L("AI（統一生成、分析、客製化會用到）", "AI (used by Generate All, Analyze and Customize)")) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("", selection: $choice) {
                        ForEach(AgentChoice.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .onChange(of: choice) { _, new in
                        if !new.presetCommand.isEmpty { command = new.presetCommand }
                        if new == .custom, command.hasPrefix("codex") || command.hasPrefix("gemini") { command = "" }
                        detect()
                    }

                    if choice == .claude {
                        Picker(L("模型", "Model"), selection: $modelPreset) {
                            Text(L("你帳號的預設模型", "Your account's default")).tag("")
                            Text("Opus").tag("opus")
                            Text("Sonnet").tag("sonnet")
                            Text("Haiku").tag("haiku")
                            Text(L("自己輸入…", "Type my own…")).tag("custom")
                        }
                        if modelPreset == "custom" {
                            TextField(L("模型名稱，例如 claude-sonnet-5-5", "Model name, e.g. claude-sonnet-5-5"), text: $customModel)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    // Codex 用內建的預設指令，不用自己填；Gemini 和自訂才需要
                    if choice == .gemini || choice == .custom {
                        TextField(L("指令，用 {prompt} 代表提示詞", "Command; {prompt} stands for the prompt"), text: $command)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                        if choice != .custom {
                            Text(L("⚠️ 這個指令是常見寫法，我沒有實測過，請對照該工具的官方文件確認。", "⚠️ This command is a common form but untested; check the tool's documentation."))
                                .font(.caption).foregroundStyle(.orange)
                        }
                        Text(L("它必須能不經確認就讀寫專案資料夾裡的檔案；輸出會以純文字顯示。", "It must be able to read and write files in the project folder without asking; its output is shown as plain text."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if choice == .codex {
                        Text(L("Codex 目前只會修改檔案，不會自動檢查效果和更新縮圖；要完整流程請用 Claude Code。",
                               "Codex only edits files for now; it doesn't check the effect or refresh its thumbnail. Use Claude Code for the full flow."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let exe = choice.executable, let installed {
                        Label(installed ? L("在這台電腦找到 \(exe)", "Found \(exe) on this computer")
                                        : L("找不到 \(exe) 指令，請先安裝並在終端機登入", "Can't find \(exe); install it and sign in from Terminal first"),
                              systemImage: installed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(installed ? .green : .orange)
                        if !installed, let command = choice.installCommand { installHelp(command, exe: exe) }
                    }
                    if choice != .none, let nodeStatus, let chromeFound {
                        toolChecks(nodeStatus, chromeFound)
                    }
                    if choice == .none {
                        Text(L("沒有 AI 時仍然可以瀏覽、調參數、輸出和匯入匯出效果。", "Without an AI you can still browse, tweak, export, import and share effects."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox(L("資料夾", "Folders")) {
                VStack(alignment: .leading, spacing: 10) {
                    FolderRow(title: L("效果", "Effects"), url: $effects, reset: Settings.defaultEffects)
                    FolderRow(title: L("收件匣", "Inbox"), url: $inbox, reset: effects.appendingPathComponent("_inbox", isDirectory: true))
                    FolderRow(title: L("輸出影片", "Exported videos"), url: $export, reset: Settings.defaultExport)
                    if foldersChanged {
                        Text(L("儲存後 MotionShelf 會重新啟動。舊資料夾裡的效果不會自動搬過去，需要的話請自己在 Finder 搬移。", "MotionShelf restarts after saving. Effects in the old folder are not moved; move them in Finder if you want them."))
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                .padding(6)
            }

            Spacer(minLength: 0)
            HStack {
                Spacer()
                if !firstRun { Button(L("取消", "Cancel"), action: onClose) }
                Button(L("儲存", "Save"), action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled((choice == .gemini || choice == .custom) && command.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 560, height: 720)
        .fontDesign(.rounded)
        .onAppear(perform: detect)
    }

    private var foldersChanged: Bool {
        effects.standardizedFileURL != Settings.effectsFolder.standardizedFileURL
            || inbox.standardizedFileURL != Settings.inboxFolder.standardizedFileURL
    }

    /// 找不到指令時：給官方的安裝指令，可以一鍵複製
    private func installHelp(_ command: String, exe: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("開啟「終端機」App，貼上這行指令安裝，裝完再開一個新的終端機視窗執行 \(exe) 登入，然後按「重新檢查」：",
                   "Open the Terminal app, paste this command to install, then open a new Terminal window, run \(exe) to sign in, and press Check again:"))
                .font(.caption).foregroundStyle(.secondary)
            if exe == "codex" {
                Text(L("安裝程式問「Start Codex now?」時輸入 N（在這裡啟動會出現 stdin is not a terminal，不是安裝失敗）。",
                       "If the installer asks \"Start Codex now?\", type N (starting it there shows \"stdin is not a terminal\"; the install itself worked)."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Text(command)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                Button(L("複製", "Copy")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                }
                .font(.caption)
                Button(L("重新檢查", "Check again"), action: detect).font(.caption)
            }
        }
    }

    /// AI 做完效果後會用 Node.js 和 Chrome 驗證、產生縮圖（tools/check-effects.mjs）；沒裝只是 AI 功能不完整，不擋儲存
    @ViewBuilder
    private func toolChecks(_ node: NodeStatus, _ chrome: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("AI 做好效果後，會用 Node.js 和 Chrome 檢查並產生縮圖：", "After the AI builds an effect, Node.js and Chrome check it and make its thumbnail:"))
                .font(.caption).foregroundStyle(.secondary)
            toolRow(ok: node.isOK,
                    text: node.message,
                    linkTitle: L("下載 Node.js（選 LTS 的 .pkg）", "Get Node.js (LTS .pkg)"), url: "https://nodejs.org/")
            toolRow(ok: chrome,
                    text: chrome ? L("找到 Google Chrome", "Found Google Chrome")
                                 : L("找不到 Google Chrome", "Can't find Google Chrome"),
                    linkTitle: L("下載 Chrome", "Get Chrome"), url: "https://www.google.com/chrome/")
            if !node.isOK || !chrome {
                HStack(spacing: 10) {
                    Text(L("沒裝也能瀏覽、預覽、輸出現成的效果。", "Without them you can still browse, preview and export existing effects."))
                        .font(.caption).foregroundStyle(.secondary)
                    Button(L("重新檢查", "Check again"), action: detect)
                        .font(.caption)
                }
            }
        }
    }

    private func toolRow(ok: Bool, text: String, linkTitle: String, url: String) -> some View {
        HStack(spacing: 8) {
            Label(text, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(ok ? .green : .orange)
            if !ok, let link = URL(string: url) {
                Link(linkTitle, destination: link).font(.caption)
            }
        }
    }

    private func detectTools() {
        DispatchQueue.global().async {
            var status = NodeStatus.missing
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", "node -p process.versions.node"]
            process.environment = ClaudeCLI.environment
            let output = Pipe()
            process.standardOutput = output
            process.standardError = Pipe()
            if (try? process.run()) != nil {
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    let version = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    status = (Int(version.split(separator: ".").first ?? "") ?? 0) >= 22 ? .ok(version) : .old(version)
                }
            }
            let fm = FileManager.default
            let chrome = ["/Applications/Google Chrome.app", "\(ClaudeCLI.home)/Applications/Google Chrome.app"].contains { fm.fileExists(atPath: $0) }
                || (ProcessInfo.processInfo.environment["CHROME"].map { fm.isExecutableFile(atPath: $0) } ?? false)
            DispatchQueue.main.async {
                nodeStatus = status
                chromeFound = chrome
            }
        }
    }

    private func detect() {
        guard let exe = choice.executable else { installed = nil; nodeStatus = nil; chromeFound = nil; return }
        installed = nil
        nodeStatus = nil
        chromeFound = nil
        detectTools()
        DispatchQueue.global().async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", "command -v \(exe)"]
            process.environment = ClaudeCLI.environment
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try? process.run()
            process.waitUntilExit()
            let found = process.terminationStatus == 0
            DispatchQueue.main.async { installed = found }
        }
    }

    private func save() {
        var config = AgentConfig()
        switch choice {
        case .claude:
            config.agent = "claude"
            config.model = modelPreset == "custom" ? customModel.trimmingCharacters(in: .whitespaces) : modelPreset
        case .codex, .gemini, .custom:
            config.agent = "custom"
            config.name = choice == .custom ? L("自訂 agent", "Custom agent") : choice.title
            config.command = choice == .codex ? choice.presetCommand : command.trimmingCharacters(in: .whitespaces)
        case .none:
            config.agent = "none"
        }
        Agent.save(config)

        // 收件匣一直跟著效果資料夾（預設 effects/_inbox）時，效果資料夾換了，收件匣也跟著換
        if inbox.standardizedFileURL == Settings.defaultInbox.standardizedFileURL {
            inbox = effects.appendingPathComponent("_inbox", isDirectory: true)
        }
        let changed = foldersChanged
        for folder in [effects, inbox, export] { try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        Settings.save(effects: effects, inbox: inbox, export: export)
        Settings.setupDone = true
        onClose()
        if changed { Settings.relaunch() }
    }
}

private struct FolderRow: View {
    let title: String
    @Binding var url: URL
    let reset: URL

    var body: some View {
        HStack {
            Text(title).frame(width: 80, alignment: .leading)
            Text(url.abbreviatedPath)
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(.secondary)
            Button(L("選擇…", "Choose…")) {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.canCreateDirectories = true
                panel.directoryURL = url
                if panel.runModal() == .OK, let picked = panel.url { url = picked }
            }
            Button(L("預設", "Default")) { url = reset }
                .disabled(url.standardizedFileURL == reset.standardizedFileURL)
        }
    }
}

/// Node.js 的偵測結果：AI 的驗證腳本需要 22 以上（內建 WebSocket）
private enum NodeStatus {
    case missing
    case old(String)
    case ok(String)

    var isOK: Bool { if case .ok = self { return true } else { return false } }

    var message: String {
        switch self {
        case .missing: return L("找不到 Node.js（需要 22 以上）", "Can't find Node.js (22 or later is needed)")
        case .old(let version): return L("Node.js \(version) 版本太舊（需要 22 以上）", "Node.js \(version) is too old (22 or later is needed)")
        case .ok(let version): return L("找到 Node.js \(version)", "Found Node.js \(version)")
        }
    }
}
