import Foundation

/// 「客製化」：請 Claude 修改目前選取的效果，例如加參數、調整動作。
/// 對話跟著效果走：換效果就開新對話，避免改到別的效果。
@MainActor
final class CustomizeChat: ClaudeChat {
    /// 目前要改的效果；跑到一半換效果時不會切換，標題仍顯示原本那個
    @Published private(set) var effect: Effect?
    /// 參數區的對話框是否展開
    @Published var isOpen = false

    override init(projectFolder: URL) {
        super.init(projectFolder: projectFolder)
        firstPrompt = { [weak self] text in self?.instruction(for: text) ?? text }
    }

    func select(_ effect: Effect?) {
        guard effect?.id != self.effect?.id, !isRunning else { return }
        self.effect = effect
        newConversation()
    }

    private func instruction(for request: String) -> String {
        guard let effect else { return request }
        let id = effect.id
        return L("""
        請用繁體中文（台灣用語）回覆。你在 MotionShelf 專案資料夾裡，要幫我客製化效果「\(effect.name)」，資料夾是 effects/\(id)/。
        先讀 skills/make-effect/effect-format.md 了解效果格式。

        ## 規則
        - 只能修改 effects/\(id)/ 裡的檔案。不要動其他效果和 App 原始碼，不要安裝套件、不要連網。
        - 新增參數時，effect.json 和 effect.html 兩邊都要改，而且參數要真的用在畫面上。label 用繁體中文；有英文翻譯時也加上 label_en。
        - 參數之間要連動：例如框變大時，裡面的字和元素要跟著一起出現、一起移動，不能各做各的。
        - 改完執行 node tools/check-effects.mjs \(id) 驗證並更新縮圖；沒通過就修正，同一個問題失敗 2 次就停下來說明。
        - 驗證腳本不會看畫面。通過之後照 effect-format.md 最後一段，用極端的參數值在開始、中間、結束各截一張圖自己看，有問題就修好再看一次。
        - 最後用幾行說明改了什麼、新參數叫什麼、怎麼調。

        ## 我的需求
        \(request)
        """, """
        Reply in English. You are in the MotionShelf project folder. Customize the effect "\(effect.name)" in effects/\(id)/.
        Read skills/make-effect/effect-format.md first for the effect format.

        ## Rules
        - Only change files in effects/\(id)/. Don't touch other effects or the app's source code, don't install packages and don't go online.
        - When adding a param, update both effect.json and effect.html, and actually use the param in the frame. Write labels in English.
        - Params must work together: for example, when a box gets bigger, the text and elements inside it should grow, move and appear with it.
        - When done, run node tools/check-effects.mjs \(id) to check it and refresh the thumbnail. If it fails, fix it; if the same problem fails twice, stop and explain.
        - The check doesn't look at the picture. After it passes, follow the end of effect-format.md: take screenshots with extreme params at the start, middle and end, look at them and fix anything wrong.
        - Finish with a few lines: what changed, what the new params are called and how to use them.

        ## What I want
        \(request)
        """)
    }
}
