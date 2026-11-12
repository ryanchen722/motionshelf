import SwiftUI

/// 照片外框 Support/skin.png 的尺寸（整個 UI 就是這張圖的大小，沒有外圍），和裡面挖的洞（單位都是這張圖的像素）。
/// 真正的元件照洞的位置按比例排進去，照片疊在最上面。要改洞的位置，先改圖再改這裡。
enum SkinLayout {
    static let size = CGSize(width: 1423, height: 1422)
    /// 標題列是一整條面板，不挖洞：標誌和按鈕直接畫在底圖上面，左右各一塊
    static let header = CGRect(x: 14, y: 44, width: 560, height: 101)
    static let tools = CGRect(x: 1180, y: 44, width: 230, height: 101)
    static let sidebar = CGRect(x: 16, y: 169, width: 380, height: 1078)
    static let footer = CGRect(x: 16, y: 1254, width: 380, height: 145)
    static let params = CGRect(x: 428, y: 170, width: 977, height: 499)
    static let preview = CGRect(x: 508, y: 719, width: 818, height: 460)
    static let transport = CGRect(x: 428, y: 1184, width: 977, height: 93)
    static let bottom = CGRect(x: 428, y: 1312, width: 977, height: 88)
    /// 蓋在底圖上面的卡片：收件匣蓋住參數到傳輸列，客製化對話框蓋住預覽到傳輸列
    static let inbox = CGRect(x: 432, y: 174, width: 969, height: 1099)
    static let chat = CGRect(x: 432, y: 677, width: 969, height: 596)
}

/// 整個視窗：先放洞後面的底色和真正的元件，再疊上照片（不擋滑鼠）
struct SkinView: View {
    @ObservedObject var library: EffectLibrary
    // 收件匣和客製化是另外的物件，要自己訂閱，不然 isOpen 變了畫面也不會更新
    @ObservedObject var inbox: Inbox
    @ObservedObject var customize: CustomizeChat
    let player: EffectPlayer
    let actions: PanelActions

    private static let image = load("skin")
    /// 洞後面的底圖：用洞周圍的照片平滑填出來的，所以洞裡露出來的顏色和磚面一致
    private static let backing = load("skin_back")

    private static func load(_ name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / SkinLayout.size.width, geo.size.height / SkinLayout.size.height)
            ZStack(alignment: .topLeading) {
                if let backing = Self.backing {
                    Image(nsImage: backing)
                        .resizable()
                        .frame(width: SkinLayout.size.width * s, height: SkinLayout.size.height * s)
                        .allowsHitTesting(false)
                }
                slot(SkinLayout.sidebar, s, inset: 10) { SidebarView(library: library) }
                slot(SkinLayout.footer, s) { SidebarFooter(library: library) }
                slot(SkinLayout.params, s, inset: 10) { ParamsView(store: player.params, player: player, customize: customize) }
                slot(SkinLayout.preview, s) { PreviewScreen(player: player) }
                slot(SkinLayout.transport, s, inset: 8) {
                    PreviewControls(player: player) {
                        library.reload()
                        player.load(library.selected, force: true)
                    }
                }
                slot(SkinLayout.bottom, s, inset: 8) { ExportBar(player: player, exporter: player.exporter) }

                if let image = Self.image {
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: SkinLayout.size.width * s, height: SkinLayout.size.height * s)
                        .allowsHitTesting(false)
                }

                slot(SkinLayout.header, s) { headerContent }
                slot(SkinLayout.tools, s) { toolsContent }

                if inbox.isOpen {
                    card(SkinLayout.inbox, s) { InboxView(inbox: inbox, generator: inbox.generator) }
                } else if customize.isOpen {
                    card(SkinLayout.chat, s) { CustomizePanel(customize: customize) }
                }
            }
            .frame(width: SkinLayout.size.width * s, height: SkinLayout.size.height * s, alignment: .topLeading)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        // 把 .mseffect 檔案拖進視窗就能匯入
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.pathExtension.lowercased() == EffectPackage.fileExtension else { return }
                    Task { @MainActor in
                        NSApp.activate(ignoringOtherApps: true)
                        await EffectTransfer.importFile(url, into: library)
                    }
                }
            }
            return true
        }
    }

    /// 放進一個洞（洞後面的底色由底圖負責）
    private func slot<V: View>(_ rect: CGRect, _ s: CGFloat, inset: CGFloat = 0, @ViewBuilder _ content: () -> V) -> some View {
        content()
            .padding(inset)
            .frame(width: rect.width * s, height: rect.height * s)
            .offset(x: rect.minX * s, y: rect.minY * s)
    }

    private func card<V: View>(_ rect: CGRect, _ s: CGFloat, @ViewBuilder _ content: () -> V) -> some View {
        content()
            .tile(padding: 14)
            .frame(width: rect.width * s, height: rect.height * s, alignment: .top)
            .offset(x: rect.minX * s, y: rect.minY * s)
    }

    private var headerContent: some View {
        HStack(spacing: 10) {
            // 圖標放大、厚邊加深、再加一圈高光和落影，看起來是凸起的按鈕
            ZStack {
                PlasticFill(shape: Circle(), top: Color(rgb: 0x6FCB74), bottom: Theme.greenDeep, depth: 8)
                    .frame(width: 50, height: 50)
                Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.75), .clear], startPoint: .top, endPoint: .center), lineWidth: 2)
                    .frame(width: 46, height: 46)
                Image(systemName: "leaf.fill").font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 2)
            }
            .frame(width: 54, height: 60)
            .padding(.trailing, 2)
            Text("MotionShelf").font(.system(.title2, design: .rounded).weight(.heavy))
                .lineLimit(1)
                .fixedSize()
            Text(L("動態小屋", "Motion House")).font(.caption.bold()).foregroundStyle(Theme.redDeep)
                .padding(.horizontal, 9).padding(.vertical, 2)
                .background(Theme.red.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.red.opacity(0.5), lineWidth: 1))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
    }

    private var toolsContent: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            LanguageButton()
            PanelButton(symbol: "gearshape", help: L("設定（AI 與資料夾）", "Settings (AI and folders)")) { SetupWindow.show(firstRun: false) }
            PanelButton(symbol: "rectangle.compress.vertical", help: L("縮小成工具列", "Shrink to a toolbar"), action: actions.toggleMini)
            PanelButton(symbol: "xmark", help: L("隱藏（⌥Space 叫回）", "Hide (⌥Space to bring back)"), action: actions.hide)
        }
        .padding(.horizontal, 6)
    }
}
