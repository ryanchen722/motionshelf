import AppKit

/// 在背景執行 Claude Code（claude -p）的一段對話：顯示過程與錯誤，使用者回覆時用 --resume 接著同一段對話。
/// 收件匣的「統一生成」和參數區的「客製化」都用這個。
@MainActor
class ClaudeChat: ObservableObject {
    enum State: Equatable {
        case idle
        case running
        case finished(String)
        case failed(String)
    }

    struct Line: Identifiable {
        enum Kind { case claude, user, tool, error, info }
        let id = UUID()
        let kind: Kind
        let text: String
    }

    @Published private(set) var state: State = .idle
    /// 這段對話的完整紀錄：Claude 說的話、使用者的回覆、用了哪些工具、錯誤
    @Published private(set) var lines: [Line] = []
    @Published private(set) var startedAt: Date?
    @Published var draft = ""
    /// 跑完時呼叫（不論成功失敗），讓效果清單重新掃描
    var onFinish: (() -> Void)?
    /// 還沒有對話時，把使用者打的字包成第一則訊息；nil 表示一定要先用 begin(prompt:) 開始
    var firstPrompt: ((String) -> String)?
    var cancelNote: () -> String = { L("已取消。", "Cancelled.") }

    let projectFolder: URL
    private var process: Process?
    private var buffer = Data()
    private(set) var sessionID: String?
    /// 自訂 agent 沒有「接續對話」：記下第一則訊息，回覆時把先前的對話一起再送一次
    private var firstSent: String?
    private var plainOutput = false

    init(projectFolder: URL) {
        self.projectFolder = projectFolder
    }

    var isRunning: Bool { state == .running }
    var hasConversation: Bool { !lines.isEmpty }
    var canReply: Bool {
        !isRunning && (sessionID != nil || firstPrompt != nil || firstSent != nil) && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 開一段新對話
    func begin(prompt: String, note: String? = nil) {
        guard !isRunning else { return }
        lines = []
        sessionID = nil
        firstSent = nil
        if let note { add(.info, note) }
        run(prompt: prompt, resume: nil)
    }

    /// 送出輸入框的文字：有對話就接著回覆，沒有就用 firstPrompt 開始
    func reply() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canReply else { return }
        draft = ""
        if let session = sessionID {
            add(.user, text)
            run(prompt: text, resume: session)
        } else if let firstSent {
            // 自訂 agent：把原本的任務、到目前為止的對話和新的訊息一起送
            let transcript = lines.filter { $0.kind == .claude || $0.kind == .user }
                .map { ($0.kind == .user ? "User: " : "Agent: ") + $0.text }.joined(separator: "\n").suffix(6000)
            add(.user, text)
            run(prompt: "\(firstSent)\n\n## Conversation so far\n\(transcript)\n\n## New message from the user\n\(text)", resume: nil, remember: false)
        } else if let firstPrompt {
            add(.user, text)
            run(prompt: firstPrompt(text), resume: nil)
        }
    }

    func cancel() {
        process?.terminate()
        process = nil
        state = .failed(cancelNote())
        add(.error, cancelNote())
    }

    /// 清掉紀錄，重新開始
    func newConversation() {
        guard !isRunning else { return }
        state = .idle
        lines = []
        sessionID = nil
        firstSent = nil
        draft = ""
    }

    func fail(_ message: String) {
        state = .failed(message)
        add(.error, message)
    }

    private func run(prompt: String, resume: String?, remember: Bool = true) {
        // 新對話開頭附上資料夾位置；之後的回覆（含自訂 agent 重送的內容）已經包含了
        if Agent.isDisabled { return fail(Agent.disabledMessage) }
        let prompt = (resume == nil && remember) ? prompt + Agent.pathNote : prompt
        let process: Process
        if Agent.isCustom {
            process = Agent.customProcess(prompt: prompt, folder: projectFolder)
            plainOutput = true
            if remember { firstSent = prompt }
        } else {
            guard let claude = ClaudeCLI.url else { return fail(ClaudeCLI.notFound) }
            process = Process()
            process.executableURL = claude
            process.currentDirectoryURL = projectFolder
            process.arguments = ["-p", prompt] + (resume.map { ["--resume", $0] } ?? []) + Agent.claudeModelArguments + Agent.addDirArguments + [
                "--output-format", "stream-json", "--verbose",
                "--permission-mode", "acceptEdits",
                "--allowedTools", "Read", "Write", "Edit", "Glob", "Grep",
                "Bash(ls:*)", "Bash(cat:*)", "Bash(mkdir:*)", "Bash(cp:*)", "Bash(mv:*)", "Bash(node:*)", "Bash(ffmpeg:*)",
            ]
            process.environment = ClaudeCLI.environment
            plainOutput = false
        }

        let out = Pipe()
        process.standardOutput = out
        process.standardError = out
        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor in self?.consume(data) }
        }
        process.terminationHandler = { [weak self] proc in
            Task { @MainActor in self?.finish(status: proc.terminationStatus) }
        }

        buffer = Data()
        startedAt = Date()
        state = .running
        do {
            try process.run()
            self.process = process
        } catch {
            fail(L("無法啟動 \(Agent.name)：\(error.localizedDescription)", "Could not start \(Agent.name): \(error.localizedDescription)"))
        }
    }

    /// stream-json：一行一個 JSON 事件
    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            handle(line: Data(line))
        }
    }

    private func handle(line: Data) {
        if plainOutput {
            // 自訂 agent：輸出當成純文字，連續的幾行併成同一個泡泡
            guard let text = String(data: line, encoding: .utf8), !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            if let last = lines.last, last.kind == .claude, last.text.count < 4000 {
                lines[lines.count - 1] = Line(kind: .claude, text: last.text + "\n" + text)
            } else {
                add(.claude, text)
            }
            return
        }
        guard let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            if let text = String(data: line, encoding: .utf8)?.trimmingCharacters(in: .whitespaces), !text.isEmpty { add(.error, text) }
            return
        }
        if let id = event["session_id"] as? String { sessionID = id }
        let content = (event["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
        switch event["type"] as? String {
        case "assistant":
            for item in content {
                if item["type"] as? String == "text", let text = item["text"] as? String {
                    add(.claude, text)
                } else if item["type"] as? String == "tool_use", let name = item["name"] as? String {
                    add(.tool, describeTool(name, input: item["input"] as? [String: Any] ?? [:]))
                }
            }
        case "user":
            // 工具執行失敗（例如權限被拒、指令出錯）也顯示出來
            for item in content where item["type"] as? String == "tool_result" && item["is_error"] as? Bool == true {
                add(.error, Self.text(of: item["content"]).prefix(400).description)
            }
        case "result":
            let text = event["result"] as? String ?? ""
            let failed = event["is_error"] as? Bool ?? false
            state = failed ? .failed(text.isEmpty ? L("Claude 回報錯誤", "Claude reported an error") : text) : .finished(text)
            if failed { add(.error, text.isEmpty ? L("Claude 回報錯誤", "Claude reported an error") : text) }
        default:
            break
        }
    }

    private static func text(of content: Any?) -> String {
        if let text = content as? String { return text }
        let items = content as? [[String: Any]] ?? []
        return items.compactMap { $0["text"] as? String }.joined(separator: "\n")
    }

    private func describeTool(_ name: String, input: [String: Any]) -> String {
        if let path = input["file_path"] as? String { return "\(name) \(URL(fileURLWithPath: path).lastPathComponent)" }
        if let command = input["command"] as? String { return "\(name) \(command.prefix(80))" }
        return name
    }

    private func add(_ kind: Line.Kind, _ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lines.append(Line(kind: kind, text: trimmed))
        if lines.count > 500 { lines.removeFirst(lines.count - 500) }
    }

    private func finish(status: Int32) {
        process = nil
        defer { onFinish?() }
        if plainOutput, !buffer.isEmpty { handle(line: buffer); buffer = Data() }
        if state == .running {
            let message = status == 0 ? L("完成", "Done") : L("\(Agent.name) 結束時回傳錯誤碼 \(status)", "\(Agent.name) exited with code \(status)")
            state = status == 0 ? .finished(message) : .failed(message)
            if status != 0 { add(.error, message) }
        }
        if !plainOutput, case .failed(let message) = state, ClaudeCLI.isLoginError(message + lines.map(\.text).joined()) {
            ClaudeCLI.openLoginInTerminal()
            fail(ClaudeCLI.loginHelp)
        }
    }
}

/// 找到終端機版的 claude 指令，並準備 GUI App 執行它需要的環境
enum ClaudeCLI {
    static let home = FileManager.default.homeDirectoryForCurrentUser.path
    private static let searchPaths = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]

    static var url: URL? {
        searchPaths.map { URL(fileURLWithPath: $0).appendingPathComponent("claude") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (searchPaths + [env["PATH"] ?? ""]).joined(separator: ":")
        env["MOTIONSHELF_EFFECTS"] = Settings.effectsFolder.path
        env["MOTIONSHELF_INBOX"] = Settings.inboxFolder.path
        return env
    }

    static var notFound: String { L("找不到 claude 指令（Claude Code）。請先在終端機確認 claude 可以執行，或在 agent.json 設定其他 agent（見 README）。", "Can't find the claude command (Claude Code). Make sure `claude` runs in Terminal, or set another agent in agent.json (see the README).") }
    // 終端機版 Claude Code 和桌面 App 的登入是分開的
    static var loginHelp: String { L("終端機版的 Claude Code 還沒登入（桌面 App 的登入不算）。已經幫你打開終端機並執行 claude auth login，請在跳出的瀏覽器登入，完成後再試一次。", "Claude Code in the terminal is not signed in (signing in to the desktop app doesn't count). Terminal has been opened with `claude auth login`; sign in in the browser, then try again.") }
    static func isLoginError(_ text: String) -> Bool { text.localizedCaseInsensitiveContains("not logged in") }

    /// 寫一個 .command 檔交給 Finder 打開：終端機會開新視窗執行它，不需要「自動化」權限
    static func openLoginInTerminal() {
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("MotionShelf-Claude-login.command")
        let body = """
        #!/bin/zsh
        export PATH="\(searchPaths.joined(separator: ":")):$PATH"
        echo "\(L("MotionShelf：幫你登入終端機版的 Claude Code，瀏覽器會跳出登入頁面。", "MotionShelf: signing in to Claude Code in the terminal. A browser sign-in page will open."))"
        echo
        claude auth login
        echo
        echo "\(L("完成後可以關掉這個視窗，回到 MotionShelf 再試一次。", "When it's done, close this window and try again in MotionShelf."))"
        """
        do {
            try body.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
            NSWorkspace.shared.open(script)
        } catch {
            NSLog("MotionShelf: could not open Terminal to sign in: \(error)")
        }
    }
}
