import SwiftUI

struct PanelActions {
    let toggleMini: () -> Void
    let hide: () -> Void
}

struct RootView: View {
    @ObservedObject var state: PanelState
    @ObservedObject var library: EffectLibrary
    let player: EffectPlayer
    let actions: PanelActions
    @AppStorage(Lang.key) private var english = Lang.isEnglish

    var body: some View {
        Group {
            if state.isMini {
                MiniBarView(library: library, player: player, exporter: player.exporter, actions: actions)
                    .background(Color.black.opacity(0.55))
            } else {
                MainView(library: library, player: player, actions: actions)
            }
        }
        // 換語言時整個畫面重新產生，所有 L(...) 文字才會跟著換
        .id(english)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 面板有隱藏的標題列，內容要延伸到最上面
        .ignoresSafeArea()
        .fontDesign(.rounded)
        .foregroundStyle(Theme.ink)
        .tint(Theme.greenDeep)
        .environment(\.colorScheme, .light)
    }
}

struct MainView: View {
    @ObservedObject var library: EffectLibrary
    let player: EffectPlayer
    let actions: PanelActions

    var body: some View {
        SkinView(library: library, inbox: library.inbox, customize: library.customize, player: player, actions: actions)
            .task(id: library.selected?.id) {
                player.load(library.selected)
                library.customize.select(library.selected)
            }
            .onAppear {
                // 客製化改完效果：重新掃描並重新載入預覽，新參數馬上出現
                library.customize.onFinish = { [library, player] in
                    library.reload()
                    player.load(library.selected, force: true)
                }
            }
            .onChange(of: library.inbox.isOpen) { _, open in if open { player.pause() } }
    }
}

struct PanelButton: View {
    let symbol: String
    let help: String
    /// 縮小工具列空間小，用小一點、厚邊薄一點的按鈕
    var size: CGFloat = 26
    var depth: CGFloat = 3
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .frame(width: size, height: size)
                .background(PlasticFill(shape: Circle(), top: Color(rgb: 0xFFFBF2), bottom: Color(rgb: 0xDDD3B8), depth: depth))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.ink)
        .help(help)
    }
}

/// 中／EN 切換：顯示的是按下去之後會換成的語言
struct LanguageButton: View {
    @AppStorage(Lang.key) private var english = Lang.isEnglish

    var body: some View {
        Button {
            english.toggle()
        } label: {
            Text(english ? "中文" : "EN")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(PlasticFill(shape: Capsule(), top: Color(rgb: 0xFFFBF2), bottom: Color(rgb: 0xDDD3B8), depth: 3))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.ink)
        .help(english ? "切換成繁體中文" : "Switch to English")
    }
}
