import Foundation

/// 要用哪個 AI agent 來做效果，寫在專案資料夾的 agent.json（沒有這個檔案就用 Claude Code）。
/// Which AI agent builds the effects. Set in agent.json in the project folder; without it, Claude Code is used.
///
///     { "agent": "claude", "model": "opus" }
///     { "agent": "custom", "name": "Codex", "command": "codex exec {prompt}" }
struct AgentConfig: Codable {
    var agent: String?
    /// 只給 Claude Code 用；不填就用帳號的預設模型
    var model: String?
    /// 自訂 agent 顯示在對話框的名稱
    var name: String?
    /// 自訂指令。{prompt} 會換成提示詞（已加引號，不用自己加）
    var command: String?
}

enum Agent {
    /// 每次都重新讀檔，改了 agent.json 不用重開 App
    static var config: AgentConfig {
        let url = Project.folder.appendingPathComponent("agent.json")
        guard let data = try? Data(contentsOf: url), let config = try? JSONDecoder().decode(AgentConfig.self, from: data) else {
            return AgentConfig()
        }
        return config
    }

    static var isCustom: Bool {
        let config = config
        return config.agent == "custom" && !(config.command ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 設定畫面存檔：寫回 agent.json
    @discardableResult
    static func save(_ config: AgentConfig) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(config) else { return false }
        return (try? data.write(to: Project.folder.appendingPathComponent("agent.json"), options: .atomic)) != nil
    }

    /// 效果或收件匣不在預設位置時，要告訴 agent 實際在哪（skills 裡寫的是 effects/）
    static var pathNote: String {
        guard Settings.isEffectsCustom || Settings.isInboxCustom else { return "" }
        return "\n\n" + L(
            "【資料夾位置】效果資料夾的實際位置是 \(Settings.effectsFolder.path)（取代說明裡的 effects/），收件匣的實際位置是 \(Settings.inboxFolder.path)（取代 effects/_inbox/）。驗證指令照常執行 node tools/check-effects.mjs，已經設定好環境變數。",
            "[Folder locations] The real effects folder is \(Settings.effectsFolder.path) (use it wherever the instructions say effects/), and the real inbox is \(Settings.inboxFolder.path) (instead of effects/_inbox/). Run the check as usual with node tools/check-effects.mjs; the environment variable is already set."
        )
    }

    /// 讓 Claude Code 可以讀寫專案資料夾以外的效果和收件匣資料夾
    static var addDirArguments: [String] {
        var dirs: [String] = []
        if Settings.isEffectsCustom { dirs.append(Settings.effectsFolder.path) }
        if Settings.isInboxCustom { dirs.append(Settings.inboxFolder.path) }
        return dirs.isEmpty ? [] : ["--add-dir"] + dirs
    }

    /// 設定成「先不使用 AI」
    static var isDisabled: Bool { config.agent == "none" }

    static var disabledMessage: String {
        L("目前設定為「先不使用 AI」。按右上角的齒輪選擇要用的 AI。", "The AI is set to \"No AI for now\". Click the gear button to choose one.")
    }

    static var name: String { isCustom ? (config.name ?? "Agent") : "Claude" }

    static var claudeModelArguments: [String] {
        guard let model = config.model, !model.isEmpty else { return [] }
        return ["--model", model]
    }

    /// 自訂指令：用登入 shell 執行，所以找得到使用者 PATH 裡的指令。
    /// 提示詞放在環境變數 MOTIONSHELF_PROMPT，指令裡的 {prompt} 換成 "$MOTIONSHELF_PROMPT"，不會有引號跳脫的問題。
    static func customProcess(prompt: String, folder: URL) -> Process {
        let command = (config.command ?? "").replacingOccurrences(of: "{prompt}", with: "\"$MOTIONSHELF_PROMPT\"")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = folder
        var env = ClaudeCLI.environment
        env["MOTIONSHELF_PROMPT"] = prompt
        process.environment = env
        return process
    }
}
