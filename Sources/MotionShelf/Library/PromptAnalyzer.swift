import Foundation

/// 「分析」：請 Claude 讀一段 motion prompt，列出拆得出幾個獨立效果。
/// 結果讓使用者勾選，存檔時寫進 source.md 的「拆分清單」，統一生成時照清單一個一個做。
@MainActor
final class PromptAnalyzer: ObservableObject {
    struct Part: Identifiable, Decodable {
        let id = UUID()
        let name: String
        let summary: String
        var included = true

        enum CodingKeys: String, CodingKey { case name, summary }
    }

    @Published var parts: [Part] = []
    @Published private(set) var isRunning = false
    @Published private(set) var error: String?
    /// 分析時的 prompt；之後 prompt 被改過就提示重新分析
    @Published private(set) var analyzedPrompt: String?

    private var process: Process?

    private static var instruction: String {
        L("""
        你是動態設計助理。下面是一段收集來的 motion prompt，裡面可能描述了好幾個動畫。
        請把它拆成「可以單獨疊在影片上的獨立效果」：每個 UI 元件、每個轉場、每個字卡各算一個；
        同一個元件的連續動作（例如按鈕按下再彈回）算同一個。不要使用任何工具。
        只回覆 JSON 陣列，不要其他文字，格式：
        [{"name": "繁體中文短名稱", "summary": "一句繁體中文說明這個效果的動作"}]

        motion prompt：

        """, """
        You are a motion design assistant. Below is a motion prompt that may describe several animations.
        Split it into separate effects that can each be layered over a video on their own: every UI element,
        every transition and every title card counts as one; consecutive moves of the same element
        (e.g. a button pressing down and springing back) count as one. Don't use any tools.
        Reply with a JSON array only, nothing else, in this format:
        [{"name": "short English name", "summary": "one English sentence describing the motion"}]

        motion prompt:

        """)
    }

    func analyze(_ prompt: String) {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isRunning, !text.isEmpty else { return }
        if Agent.isDisabled {
            error = Agent.disabledMessage
            return
        }
        let process: Process
        if Agent.isCustom {
            process = Agent.customProcess(prompt: Self.instruction + text, folder: Project.folder)
        } else {
            guard let claude = ClaudeCLI.url else {
                error = ClaudeCLI.notFound
                return
            }
            process = Process()
            process.executableURL = claude
            process.arguments = ["-p", Self.instruction + text, "--output-format", "json"] + Agent.claudeModelArguments
            process.environment = ClaudeCLI.environment
        }
        let out = Pipe()
        process.standardOutput = out
        process.standardError = out
        process.terminationHandler = { [weak self] _ in
            let data = out.fileHandleForReading.readDataToEndOfFile()
            Task { @MainActor in self?.finish(data, prompt: prompt) }
        }

        isRunning = true
        error = nil
        do {
            try process.run()
            self.process = process
        } catch {
            isRunning = false
            self.error = L("無法啟動 Claude：\(error.localizedDescription)", "Could not start Claude: \(error.localizedDescription)")
        }
    }

    func cancel() {
        process?.terminate()
    }

    func reset() {
        parts = []
        error = nil
        analyzedPrompt = nil
    }

    var included: [Part] { parts.filter(\.included) }

    private func finish(_ data: Data, prompt: String) {
        isRunning = false
        process = nil
        let raw = String(data: data, encoding: .utf8) ?? ""
        // --output-format json：{"result": "Claude 的回覆", "is_error": false, ...}
        let envelope = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let reply = envelope?["result"] as? String ?? raw
        if !Agent.isCustom, ClaudeCLI.isLoginError(raw) {
            ClaudeCLI.openLoginInTerminal()
            error = ClaudeCLI.loginHelp
            return
        }
        guard envelope?["is_error"] as? Bool != true,
              let start = reply.firstIndex(of: "["), let end = reply.lastIndex(of: "]"),
              let list = try? JSONDecoder().decode([Part].self, from: Data(reply[start...end].utf8)),
              !list.isEmpty else {
            error = L("分析失敗：\(reply.prefix(200))", "Analysis failed: \(reply.prefix(200))")
            return
        }
        parts = list
        analyzedPrompt = prompt
    }
}
