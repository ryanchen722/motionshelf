import AppKit
import SwiftUI

/// 設定視窗：第一次開啟時選 AI 和資料夾，之後從齒輪按鈕也能打開。
/// Settings window: shown on first launch to pick the AI and folders; reopen from the gear button.
@MainActor
final class SetupWindow {
    private static var window: NSWindow?

    static func show(firstRun: Bool) {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 640), styleMask: [.titled, .closable], backing: .buffered, defer: false)
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

    /// 常見的非互動寫法（Codex、Gemini 沒有實測過，請自己對照官方文件）
    var presetCommand: String {
        switch self {
        case .codex: return "codex exec --full-auto {prompt}"
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
            Text(firstRun ? L("歡迎使用 MotionShelf", "Welcome to MotionShelf") : L("設定", "Settings"))
                .font(.title2.weight(.heavy))
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
                    if choice == .codex || choice == .gemini || choice == .custom {
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
                    if let exe = choice.executable, let installed {
                        Label(installed ? L("在這台電腦找到 \(exe)", "Found \(exe) on this computer")
                                        : L("找不到 \(exe) 指令，請先安裝並在終端機登入", "Can't find \(exe); install it and sign in from Terminal first"),
                              systemImage: installed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(installed ? .green : .orange)
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
                    .disabled((choice == .codex || choice == .gemini || choice == .custom) && command.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 560, height: 640)
        .fontDesign(.rounded)
        .onAppear(perform: detect)
    }

    private var foldersChanged: Bool {
        effects.standardizedFileURL != Settings.effectsFolder.standardizedFileURL
            || inbox.standardizedFileURL != Settings.inboxFolder.standardizedFileURL
    }

    private func detect() {
        guard let exe = choice.executable else { installed = nil; return }
        installed = nil
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
            config.command = command.trimmingCharacters(in: .whitespaces)
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
