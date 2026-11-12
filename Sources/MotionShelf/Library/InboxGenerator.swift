import Foundation

/// 「統一生成」：在背景執行 Claude Code，把收件匣每一筆做成效果資料夾。
/// 做法寫在 skills/process-inbox/SKILL.md（Claude Code plugin 也用同一份），要調整就改那個檔案。
@MainActor
final class InboxGenerator: ClaudeChat {
    override init(projectFolder: URL) {
        super.init(projectFolder: projectFolder)
        cancelNote = { L("已取消。做到一半的效果資料夾可能還在 effects/ 裡。", "Cancelled. Half-finished effect folders may still be in effects/.") }
    }

    /// 開一段新對話，照 skills/process-inbox/SKILL.md 處理收件匣
    func start() {
        guard FileManager.default.fileExists(atPath: projectFolder.appendingPathComponent("skills/process-inbox/SKILL.md").path) else {
            return fail(L("找不到 skills/process-inbox/SKILL.md", "skills/process-inbox/SKILL.md not found"))
        }
        let prompt = L(
            "請用繁體中文（台灣用語）回覆，effect.json 的 name 和 label 也用繁體中文。你在 MotionShelf 專案資料夾裡。請照 skills/process-inbox/SKILL.md 的步驟處理收件匣。",
            "Reply in English, and write effect.json names and labels in English. You are in the MotionShelf project folder. Process the inbox by following skills/process-inbox/SKILL.md."
        )
        begin(prompt: prompt, note: L("開始處理收件匣…", "Processing the inbox…"))
    }
}
