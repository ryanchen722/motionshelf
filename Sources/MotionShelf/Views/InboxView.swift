import SwiftUI

struct InboxView: View {
    @ObservedObject var inbox: Inbox
    @ObservedObject var generator: InboxGenerator

    var body: some View {
        // 分析清單和生成紀錄可能很長，整個表單可以捲動
        ScrollView {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                BubbleTitle(text: L("收件匣", "Inbox"), symbol: "envelope.fill", tone: .red)
                Text(L("還沒處理：\(inbox.pending.count) 筆", "Pending: \(inbox.pending.count)"))
                    .font(.caption.bold())
                    .foregroundStyle(inbox.pending.isEmpty ? Theme.inkSoft : Theme.redDeep)
                Spacer()
                PanelButton(symbol: "folder", help: L("在 Finder 中打開 _inbox 資料夾", "Open the _inbox folder in Finder"), action: inbox.revealInFinder)
                PanelButton(symbol: "xmark", help: L("關閉收件匣", "Close the inbox")) { inbox.isOpen = false }
            }

            Field(L("名稱（選填）", "Name (optional)")) {
                TextField(L("例如：婚禮人名字卡", "e.g. Wedding name card"), text: $inbox.name)
            }
            Field(L("原始 prompt", "Original prompt")) {
                TextEditor(text: $inbox.prompt)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(Theme.creamDeep, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .frame(minHeight: 120)
            }
            AnalysisSection(analyzer: inbox.analyzer, prompt: inbox.prompt)
            HStack(alignment: .top, spacing: 12) {
                Field(L("來源連結", "Source link")) {
                    TextField("https://…", text: $inbox.source)
                }
                Field(L("我想用在", "Use it for")) {
                    TextField(L("例如：婚禮開場人名字卡", "e.g. Name cards for a wedding intro"), text: $inbox.usage)
                }
            }
            Field(L("要能調整的參數", "Adjustable params")) {
                TextField(L("例如：文字、顏色、粒子數量、速度", "e.g. text, color, particle count, speed"), text: $inbox.params, axis: .vertical)
                    .lineLimit(1...3)
            }

            HStack {
                Button(L("儲存到收件匣", "Save to Inbox"), action: inbox.save)
                    .buttonStyle(PlasticButtonStyle(tone: .red))
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!inbox.canSave)
                Button(L("清空", "Clear"), action: inbox.clear)
                    .buttonStyle(PlasticButtonStyle(tone: .gray))
                Spacer()
                if let error = inbox.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                } else if let saved = inbox.lastSaved {
                    Text(L("已存入 \(saved)", "Saved as \(saved)")).font(.caption).foregroundStyle(Theme.greenDeep).lineLimit(1)
                }
            }

            Divider().overlay(Theme.line)
            generateSection

            if !inbox.pending.isEmpty && !generator.isRunning {
                Text(L("還沒做成效果的收件（按「統一生成」就會處理）", "Items not made into effects yet (press Generate All)")).font(.caption.bold()).foregroundStyle(Theme.inkSoft)
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(inbox.pending, id: \.self) { item in
                            Label(item, systemImage: "doc.text").font(.caption)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.trailing, 4)
        }
        .textFieldStyle(.roundedBorder)
    }
}

extension InboxView {
    @ViewBuilder
    var generateSection: some View {
        HStack(spacing: 10) {
            if generator.isRunning {
                Text(L("Claude 正在把收件匣做成效果…", "Claude is turning the inbox into effects…")).font(.caption.bold())
            } else {
                Button {
                    generator.start()
                } label: {
                    Label(L("統一生成", "Generate All"), systemImage: "wand.and.stars")
                }
                .buttonStyle(PlasticButtonStyle())
                .disabled(inbox.pending.isEmpty)
                .help(L("在背景執行 Claude Code，把收件匣每一筆做成效果（會用到 Claude 的用量）", "Runs Claude Code in the background to turn every inbox item into effects (uses your Claude usage)"))
                Text(inbox.pending.isEmpty ? L("收件匣是空的", "The inbox is empty") : L("把 \(inbox.pending.count) 筆一次做成效果，做好會自動出現在清單裡", "Turn \(inbox.pending.count) items into effects. They show up in the list when done"))
                    .font(.caption)
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer()
        }

        if generator.hasConversation {
            ClaudeChatView(chat: generator, placeholder: L("回覆，例如：title-card 的字太小，改大一點", "Reply, e.g. make the text in title-card bigger"))
        }
    }
}

/// 「分析」按鈕和結果：列出這段 prompt 拆得出的效果，可以取消勾選
private struct AnalysisSection: View {
    @ObservedObject var analyzer: PromptAnalyzer
    let prompt: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if analyzer.isRunning {
                    ProgressView().controlSize(.small)
                    Text(L("Claude 正在看這段 prompt 有幾個效果…", "Claude is checking how many effects are in this prompt…")).font(.caption.bold())
                    Button(L("取消", "Cancel"), action: analyzer.cancel)
                        .buttonStyle(PlasticButtonStyle(tone: .gray))
                } else {
                    Button {
                        analyzer.analyze(prompt)
                    } label: {
                        Label(analyzer.parts.isEmpty ? L("分析有幾個效果", "Count the effects") : L("重新分析", "Analyze again"), systemImage: "sparkle.magnifyingglass")
                    }
                    .buttonStyle(PlasticButtonStyle())
                    .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help(L("請 Claude 讀這段 prompt，列出可以拆成哪些獨立效果（約 10～20 秒，會用到 Claude 用量）", "Ask Claude which separate effects this prompt contains (takes a little while and uses your Claude usage)"))
                    if !analyzer.parts.isEmpty {
                        Text(L("共 \(analyzer.parts.count) 個效果，勾選的 \(analyzer.included.count) 個會分別做成效果", "\(analyzer.parts.count) effects found. The \(analyzer.included.count) checked will each become an effect"))
                            .font(.caption.bold())
                            .foregroundStyle(Theme.greenDeep)
                    }
                }
                Spacer()
            }

            if let error = analyzer.error {
                Text(error).font(.caption).foregroundStyle(Theme.redDeep).fixedSize(horizontal: false, vertical: true)
            }
            if !analyzer.parts.isEmpty, analyzer.analyzedPrompt != prompt, !analyzer.isRunning {
                Text(L("prompt 改過了，建議重新分析", "The prompt changed. Consider analyzing again")).font(.caption).foregroundStyle(Theme.redDeep)
            }
            if !analyzer.parts.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach($analyzer.parts) { $part in
                        Toggle(isOn: $part.included) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(part.name).font(.callout.weight(.bold))
                                Text(part.summary).font(.caption).foregroundStyle(Theme.inkSoft)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.green.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
}

private struct Field<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.bold()).foregroundStyle(Theme.inkSoft)
            content
        }
    }
}
