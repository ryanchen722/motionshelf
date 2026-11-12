import SwiftUI

/// 縮小後的一條工具列：目前效果、輸出按鈕、最近一次輸出的縮圖（可直接拖進 DaVinci）
struct MiniBarView: View {
    @ObservedObject var library: EffectLibrary
    let player: EffectPlayer
    @ObservedObject var exporter: Exporter
    let actions: PanelActions

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "leaf.fill").foregroundStyle(Theme.greenDeep)
            Text(library.selected?.name ?? L("尚未選擇效果", "No effect selected"))
                .font(.callout.weight(.bold))
                .lineLimit(1)
            Spacer(minLength: 4)

            switch exporter.state {
            case .exporting(let progress):
                ProgressView(value: progress).frame(width: 60)
                PanelButton(symbol: "stop.circle", help: L("取消輸出", "Cancel export"), size: 22, depth: 2, action: exporter.cancel)
            case .done(let url, let thumbnail):
                OutputThumbnail(url: url, thumbnail: thumbnail, height: 28)
                exportButton
            default:
                exportButton
            }

            PanelButton(symbol: "rectangle.expand.vertical", help: L("展開面板", "Expand the panel"), size: 22, depth: 2, action: actions.toggleMini)
            PanelButton(symbol: "xmark", help: L("隱藏（⌥Space 叫回）", "Hide (⌥Space to bring back)"), size: 22, depth: 2, action: actions.hide)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(LinearGradient(colors: [Theme.card, Color(rgb: 0xEFE8D6)], startPoint: .top, endPoint: .bottom)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.seam.opacity(0.4), lineWidth: 1))
        // 下面多留一點，按鈕的厚邊和陰影才不會超出米色小條
        .padding(.horizontal, 6)
        .padding(.top, 4)
        .padding(.bottom, 9)
        // 面板有隱藏的標題列，會在上方留約 28 點的安全區域；工具列只有 54 點高，要用整條高度置中
        .ignoresSafeArea()
    }

    private var exportButton: some View {
        PanelButton(symbol: "square.and.arrow.up", help: L("用目前的參數輸出（\(player.resolution.label)）", "Export with the current params (\(player.resolution.label))"), size: 22, depth: 2, action: player.export)
            .disabled(library.selected == nil)
    }
}
