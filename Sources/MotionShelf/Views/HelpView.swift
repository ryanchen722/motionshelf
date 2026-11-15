import AppKit
import SwiftUI

/// 官方的安裝指令（Claude：code.claude.com/docs/en/setup；Codex：learn.chatgpt.com/docs/codex/cli）
enum InstallCommand {
    static let claude = "curl -fsSL https://claude.ai/install.sh | bash"
    static let codex = "curl -fsSL https://chatgpt.com/codex/install.sh | sh"
}

/// 說明視窗（工具列和設定視窗的「?」按鈕）。
/// Help window opened from the "?" buttons in the toolbar and the settings window.
@MainActor
enum HelpWindow {
    private static var window: NSWindow?

    static func show() {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 720), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = L("MotionShelf 說明", "MotionShelf Help")
        window.isReleasedWhenClosed = false
        window.level = .modalPanel
        window.contentView = NSHostingView(rootView: HelpView())
        window.center()
        self.window = window
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated { HelpWindow.window = nil }
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section(L("這個 App 在做什麼", "What this app does"), icon: "sparkles", color: Color(rgb: 0xD9692C)) {
                    para(L("MotionShelf 收集可以直接丟進剪輯軟體的動態效果：挑一個效果、調參數、預覽，輸出成透明背景的影片。",
                           "MotionShelf collects motion effects you can drop into an editor: pick one, tweak it, preview it and export a video with a transparent background."))
                    para(L("按 ⌥Space（Option + 空白鍵）可以隨時叫出或隱藏視窗。沒有 AI 也能瀏覽、預覽和輸出現成的效果。",
                           "Press ⌥Space (Option + Space) to show or hide the window anytime. Without an AI you can still browse, preview and export existing effects."))
                }

                section(L("連接 AI（選用）", "Connect an AI (optional)"), icon: "terminal", color: Theme.greenDeep) {
                    para(L("要讓 AI 幫你做效果，需要在電腦上裝好終端機版的指令，並登入一次。桌面版 App 的登入不算。",
                           "To let an AI build effects, install its terminal command and sign in once. Signing in to the desktop app doesn't count."))
                    para(L("Claude Code 支援完整流程（修改、檢查、更新縮圖）；Codex 目前只會修改檔案，不會自動檢查效果和更新縮圖。",
                           "Claude Code supports the full flow (edit, check, refresh the thumbnail); Codex only edits files for now and doesn't check the effect or refresh its thumbnail."))
                    step(L("1. 開啟「終端機」App，貼上安裝指令：", "1. Open the Terminal app and paste the install command:"), color: Theme.greenDeep)
                    command("Claude Code", InstallCommand.claude)
                    command("Codex", InstallCommand.codex)
                    para(L("Codex 安裝完問「Start Codex now?」時輸入 N；在安裝程式裡啟動會出現 stdin is not a terminal，那不是安裝失敗。",
                           "If the Codex installer asks \"Start Codex now?\", type N. Starting it there shows \"stdin is not a terminal\"; the install itself worked."))
                    step(L("2. 開一個新的終端機視窗，執行一次來登入：", "2. Open a new Terminal window and run it once to sign in:"), color: Theme.greenDeep)
                    command("Claude Code", "claude")
                    command("Codex", "codex")
                    para(L("Codex 第一次會問登入方式，選「Sign in with ChatGPT」；如果直接進到可以輸入的畫面，代表這台電腦已經登入過了。",
                           "Codex asks how to sign in the first time; choose \"Sign in with ChatGPT\". If it goes straight to the prompt, you're already signed in."))
                    step(L("3. 回到設定視窗（齒輪按鈕），按「重新檢查」，變成綠色就可以了。", "3. Back in Settings (the gear button), press Check again. When it turns green you're set."), color: Theme.greenDeep)
                }

                section(L("收件匣：把 prompt 做成效果", "Inbox: turn a prompt into effects"), icon: "tray.and.arrow.down.fill", color: Theme.redDeep) {
                    para(L("手上有一段動態效果的 prompt，想變成可以用的效果時，用左上角紅色的「收件匣」。需要先連接 Claude Code（見上一段）。",
                           "Got a prompt for a motion effect and want a working effect? Use the red Inbox button at the top left. Connect Claude Code first (see above)."))
                    step(L("1. 按左上角的「收件匣」，貼上原始 prompt。", "1. Press Inbox at the top left and paste the original prompt."), color: Theme.redDeep)
                    para(L("名稱、來源連結、我想用在、要能調整的參數都是選填，寫得越清楚，做出來越貼近你要的。",
                           "Name, source link, what you'll use it for and adjustable params are optional. The clearer they are, the closer the result."))
                    step(L("2. （選用）按「分析有幾個效果」。", "2. (Optional) Press Count the effects."), color: Theme.redDeep)
                    para(L("一段 prompt 裡可能有好幾個效果，分析後勾選要做的，每個會各自做成一個效果。",
                           "One prompt may hold several effects. After analyzing, tick the ones you want and each becomes its own effect."))
                    step(L("3. 按「儲存到收件匣」。", "3. Press Save to Inbox."), color: Theme.redDeep)
                    para(L("每一筆會存成 effects/_inbox 裡的一個資料夾，可以連續存很多筆，上方會顯示還沒處理幾筆。",
                           "Each item is saved as a folder in effects/_inbox. You can save many in a row; the top shows how many are pending."))
                    step(L("4. 按「統一生成」。", "4. Press Generate All."), color: Theme.redDeep)
                    para(L("Claude Code 會在背景把每一筆做成效果，做好的會自動出現在左邊清單，處理完的收件會丟進垃圾桶。過程中會用到 Claude 的用量。",
                           "Claude Code works in the background and turns each item into an effect. Finished effects appear in the list on the left and processed items go to the Trash. It uses your Claude usage."))
                    para(L("做完後可以直接在下方對話框回覆修改，例如「字太小，改大一點」；中途想停可以按取消。",
                           "When it's done you can reply in the chat box to adjust, for example \"make the text bigger\". Press Cancel to stop midway."))
                }

                section(L("Node.js 和 Chrome", "Node.js and Chrome"), icon: "shippingbox", color: Color(rgb: 0x4A7FA8)) {
                    para(L("AI 做好效果後，會用 Node.js（22 以上）和 Google Chrome 檢查效果並產生縮圖。沒裝的話 AI 功能不完整，但不影響瀏覽、預覽和輸出。",
                           "After the AI builds an effect, Node.js (22 or newer) and Google Chrome check it and make its thumbnail. Without them the AI features are incomplete, but browsing, previewing and exporting still work."))
                    link(L("下載 Node.js（選 LTS 的 .pkg）", "Get Node.js (LTS .pkg)"), "https://nodejs.org/")
                    link(L("下載 Google Chrome", "Get Google Chrome"), "https://www.google.com/chrome/")
                    para(L("用 nvm、fnm 或 Volta 裝的 Node.js 也找得到。", "Node.js installed with nvm, fnm or Volta is found too."))
                }

                section(L("常見問題", "Troubleshooting"), icon: "questionmark.circle", color: Color(rgb: 0x8A6A4A)) {
                    question(L("已經裝了，設定視窗還是顯示找不到？", "Installed it but Settings still says it can't find it?"),
                             L("關掉舊的終端機、開新視窗確認指令能執行（claude --version、codex --version、node -v），再按「重新檢查」。",
                               "Open a new Terminal window and check the command runs (claude --version, codex --version, node -v), then press Check again."))
                    question(L("AI 功能說還沒登入？", "The AI says you're not signed in?"),
                             L("在終端機執行一次 claude 或 codex 完成登入。", "Run claude or codex once in Terminal and finish signing in."))
                    question(L("視窗太大或工具列太擠？", "Window too big or toolbar too cramped?"),
                             L("按工具列的縮小按鈕變成小工具列；螢幕小時工具列會自動縮小。", "Use the shrink button to turn it into a small bar; on small screens the toolbar scales down by itself."))
                    question(L("介面想換成英文或中文？", "Want the other language?"),
                             L("按工具列左邊的 EN／中文 按鈕。", "Press the EN / 中文 button in the toolbar."))
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 540, minHeight: 460)
        .background(Color(rgb: 0xFAF0DC))
        .foregroundStyle(Theme.ink)
        .environment(\.colorScheme, .light)
        .fontDesign(.rounded)
    }

    /// 每個區塊一張有顏色的卡片：標題列上色、底色淡淡的，一眼分得出段落
    private func section<V: View>(_ title: String, icon: String, color: Color, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 18, weight: .bold))
                Text(title).font(.system(size: 20, weight: .heavy, design: .rounded))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background(color)
            VStack(alignment: .leading, spacing: 12) { content() }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(color.opacity(0.10))
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(color.opacity(0.45), lineWidth: 1.5))
    }

    private func para(_ text: String) -> some View {
        Text(text).font(.system(size: 15)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
    }

    private func step(_ text: String, color: Color) -> some View {
        Text(text).font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
    }

    private func command(_ name: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Text(name).font(.system(size: 14, weight: .bold)).frame(width: 92, alignment: .leading)
            Text(text)
                .font(.system(size: 14, design: .monospaced))
                .textSelection(.enabled)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Color.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.black.opacity(0.12)))
            Button(L("複製", "Copy")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            .font(.system(size: 13, weight: .semibold))
        }
    }

    @ViewBuilder
    private func link(_ title: String, _ url: String) -> some View {
        if let destination = URL(string: url) { Link(title, destination: destination).font(.system(size: 15, weight: .semibold)) }
    }

    private func question(_ q: String, _ a: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(q).font(.system(size: 15, weight: .heavy, design: .rounded))
            para(a)
        }
    }
}
