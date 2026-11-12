import SwiftUI

/// 右欄下方：解析度、輸出按鈕、進度，完成後顯示可拖進 DaVinci 的縮圖
struct ExportBar: View {
    @ObservedObject var player: EffectPlayer
    @ObservedObject var exporter: Exporter

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(Resolution.allCases) { resolution in
                    Button {
                        player.resolution = resolution
                    } label: {
                        if resolution == player.resolution { Label(resolution.label, systemImage: "checkmark") } else { Text(resolution.label) }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.ratio.16.to.9.fill")
                    Text(player.resolution.label)
                    Image(systemName: "chevron.down").font(.caption2.bold())
                }
                .font(.system(.callout, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(PlasticFill(shape: RoundedRectangle(cornerRadius: 11, style: .continuous), top: Theme.green, bottom: Theme.greenDeep))
                .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(exporter.isExporting)
            .help(L("輸出的解析度", "Export resolution"))

            status
            Spacer(minLength: 0)

            if exporter.isExporting {
                Button(L("取消", "Cancel"), action: exporter.cancel)
                    .buttonStyle(PlasticButtonStyle(tone: .gray))
            } else {
                Button(action: player.export) {
                    Label(L("輸出", "Export"), systemImage: "square.and.arrow.up")
                }
                .buttonStyle(PlasticButtonStyle(tone: .red))
                .keyboardShortcut("e", modifiers: .command)
                .disabled(player.effect == nil)
            }
            PanelButton(symbol: "folder", help: L("在 Finder 中打開輸出資料夾（\(Exporter.outputFolder.abbreviatedPath)）", "Open the output folder in Finder (\(Exporter.outputFolder.abbreviatedPath))"), action: exporter.revealInFinder)
        }
        .frame(height: 44)
    }

    @ViewBuilder
    private var status: some View {
        switch exporter.state {
        case .idle:
            Text(L("ProRes 4444 · 透明背景", "ProRes 4444 · transparent")).font(.caption).foregroundStyle(Theme.inkSoft)
        case .exporting(let progress):
            ProgressView(value: progress)
                .frame(width: 140)
            Text("\(Int(progress * 100))%").font(.caption).monospacedDigit()
        case .done(let url, let thumbnail):
            OutputThumbnail(url: url, thumbnail: thumbnail)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent).font(.caption).lineLimit(1).truncationMode(.middle)
                Text(L("把縮圖拖進 DaVinci 的時間軸或媒體池", "Drag the thumbnail into a DaVinci timeline or media pool")).font(.caption2).foregroundStyle(Theme.inkSoft)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }
}

/// 輸出完成的影片縮圖，可以直接拖曳到 DaVinci 或 Finder。
/// 面板設了「拖背景可移動視窗」，SwiftUI 的 onDrag 會被搶走變成移動視窗，所以用 AppKit 自己處理拖曳。
struct OutputThumbnail: View {
    let url: URL
    let thumbnail: NSImage
    var height: CGFloat = 36

    var body: some View {
        FileDragView(url: url, image: thumbnail)
            .frame(width: height * 16 / 9, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.greenDeep, lineWidth: 1.5))
            .help(L("拖曳到 DaVinci Resolve 的時間軸或媒體池", "Drag into a DaVinci Resolve timeline or media pool"))
    }
}

private struct FileDragView: NSViewRepresentable {
    let url: URL
    let image: NSImage

    func makeNSView(context: Context) -> FileDragSourceView {
        FileDragSourceView(url: url, image: image)
    }

    func updateNSView(_ view: FileDragSourceView, context: Context) {
        view.url = url
        view.image = image
        view.needsDisplay = true
    }
}

final class FileDragSourceView: NSView, NSDraggingSource {
    var url: URL
    var image: NSImage
    private var dragStarted = false

    init(url: URL, image: NSImage) {
        self.url = url
        self.image = image
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    // 按在縮圖上不會移動視窗
    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.3, alpha: 1).setFill()
        bounds.fill()
        let size = image.size
        guard size.width > 0, size.height > 0 else { return }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let drawSize = NSSize(width: size.width * scale, height: size.height * scale)
        let rect = NSRect(x: bounds.midX - drawSize.width / 2, y: bounds.midY - drawSize.height / 2, width: drawSize.width, height: drawSize.height)
        image.draw(in: rect)
    }

    override func mouseDown(with event: NSEvent) {
        dragStarted = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragStarted else { return }
        dragStarted = true
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }
}
