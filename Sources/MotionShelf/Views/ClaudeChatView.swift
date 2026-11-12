import SwiftUI

/// 和 Claude 的對話：過程、錯誤，以及回覆框（接著同一段對話）。收件匣和客製化共用。
struct ClaudeChatView<Header: View>: View {
    @ObservedObject var chat: ClaudeChat
    var placeholder: String
    var height: CGFloat = 240
    /// 標題列左邊；預設顯示目前狀態
    @ViewBuilder var header: Header

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                header
                Spacer()
                if chat.isRunning {
                    ProgressView().controlSize(.small)
                    if let start = chat.startedAt {
                        Text(timerInterval: start...Date.distantFuture, countsDown: false)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.inkSoft)
                    }
                    Button(L("取消", "Cancel"), action: chat.cancel)
                        .buttonStyle(PlasticButtonStyle(tone: .gray))
                } else if chat.hasConversation {
                    Button(L("開新對話", "New chat"), action: chat.newConversation)
                        .buttonStyle(PlasticButtonStyle(tone: .gray))
                        .help(L("清掉這段紀錄，重新開始", "Clear this chat and start over"))
                }
            }
            if chat.hasConversation {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(chat.lines) { line in
                                ChatBubble(line: line).id(line.id)
                            }
                        }
                        .padding(8)
                    }
                    .frame(height: height)
                    .background(Theme.creamDeep.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .onChange(of: chat.lines.last?.id) { _, id in
                        if let id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
                    }
                    .onAppear { if let id = chat.lines.last?.id { proxy.scrollTo(id, anchor: .bottom) } }
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField(chat.isRunning ? L("Claude 工作中，完成後就可以回覆…", "Claude is working. You can reply when it's done…") : placeholder, text: $chat.draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .disabled(chat.isRunning)
                    .onSubmit(chat.reply)
                Button {
                    chat.reply()
                } label: {
                    Label(L("送出", "Send"), systemImage: "paperplane.fill")
                }
                .buttonStyle(PlasticButtonStyle(tone: .red))
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .disabled(!chat.canReply)
                .help(L("送出（⇧⌘Return）", "Send (⇧⌘Return)"))
            }
        }
        .padding(10)
        .background(Theme.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

extension ClaudeChatView where Header == ChatStatusLabel {
    init(chat: ClaudeChat, placeholder: String, height: CGFloat = 240) {
        self.init(chat: chat, placeholder: placeholder, height: height) { ChatStatusLabel(chat: chat) }
    }
}

struct ChatStatusLabel: View {
    @ObservedObject var chat: ClaudeChat

    var body: some View {
        switch chat.state {
        case .idle, .running:
            Label(L("和 Claude 的對話", "Chat with Claude"), systemImage: "bubble.left.and.bubble.right.fill")
                .font(.callout.bold()).foregroundStyle(Theme.ink)
        case .finished:
            Label(L("完成了！有需要修改可以直接回覆", "Done! Reply here if you want changes"), systemImage: "checkmark.seal.fill")
                .font(.callout.bold()).foregroundStyle(Theme.greenDeep)
        case .failed:
            Label(L("沒有完成，可以回覆 Claude 請它修正", "Not finished. Reply to ask Claude to fix it"), systemImage: "exclamationmark.triangle.fill")
                .font(.callout.bold()).foregroundStyle(Theme.redDeep)
        }
    }
}

/// 一則對話：Claude 綠色泡泡、自己粉紅色靠右、工具是小字、錯誤是紅字
private struct ChatBubble: View {
    let line: ClaudeChat.Line

    var body: some View {
        switch line.kind {
        case .claude:
            bubble(color: Theme.green.opacity(0.45))
                .frame(maxWidth: .infinity, alignment: .leading)
        case .user:
            bubble(color: Theme.yellow.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .trailing)
        case .tool:
            Label(line.text, systemImage: "wrench.and.screwdriver.fill")
                .font(.caption2.monospaced())
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(2)
        case .error:
            Label {
                Text(line.text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.caption)
            .foregroundStyle(Color(rgb: 0xD9534F))
        case .info:
            Text(line.text).font(.caption.bold()).foregroundStyle(Theme.inkSoft)
        }
    }

    private func bubble(color: Color) -> some View {
        Text(line.text)
            .font(.callout)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .frame(maxWidth: 520, alignment: .leading)
    }
}
