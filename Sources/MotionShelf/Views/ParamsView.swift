import SwiftUI

/// 依 effect.json 的 params 自動產生控制項
struct ParamsView: View {
    @ObservedObject var store: ParamStore
    @ObservedObject var player: EffectPlayer
    @ObservedObject var customize: CustomizeChat

    /// 一列一個參數，整行拉長，名稱才有地方完整顯示
    private let columns = [GridItem(.flexible(), alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                BubbleTitle(text: L("參數", "Params"), symbol: "slider.horizontal.3")
                Spacer()
                Button(L("重設為預設值", "Reset to defaults"), action: store.reset)
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .disabled(store.isDefault)
                Button {
                    customize.isOpen.toggle()
                } label: {
                    Label(L("客製化", "Customize"), systemImage: customize.isOpen ? "chevron.up" : "wand.and.stars")
                }
                .buttonStyle(PlasticButtonStyle())
                .disabled(customize.effect == nil)
                .help(L("請 Claude 幫這個效果加參數或調整動作（會用到 Claude 用量）", "Ask Claude to add params or change the motion of this effect (uses your Claude usage)"))
            }

            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 5) {
                    if store.definitions.isEmpty {
                        Text(L("這個效果沒有可調整的參數", "This effect has no adjustable params"))
                            .font(.caption)
                            .foregroundStyle(Theme.inkSoft)
                    }
                    ForEach(store.definitions) { param in
                        ParamRow(param: param, store: store)
                    }
                    CameraSection(player: player)
                }
                .padding(.trailing, 6)
            }
        }
    }
}

/// 3D 攝影機：開關和透視強度在這裡調；方向和位置直接在預覽畫面上拖移，記成時間軸上的關鍵幀
private struct CameraSection: View {
    @ObservedObject var player: EffectPlayer

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L("3D 攝影機", "3D camera"))
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.inkSoft)
                .padding(.top, 6)
            row(L("攝影機", "Camera")) {
                BrickMenu(title: player.camera.on ? L("開啟", "On") : L("關閉", "Off")) {
                    Picker("", selection: Binding(get: { player.camera.on }, set: { new in player.updateCamera { $0.on = new } })) {
                        Text(L("關閉", "Off")).tag(false)
                        Text(L("開啟", "On")).tag(true)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            if player.camera.on {
                row(L("透視強度", "Perspective")) {
                    HStack(spacing: 6) {
                        PlasticSlider(
                            value: Binding(get: { player.camera.depth }, set: { new in player.updateCamera { $0.depth = (new * 10).rounded() / 10 } }),
                            range: 0.5...4
                        )
                        Text(String(format: "%.1f", player.camera.depth)).monospacedDigit().font(.caption).frame(width: 42, alignment: .trailing)
                    }
                }
                row(L("關鍵幀", "Keyframes")) {
                    HStack(spacing: 8) {
                        Text(player.camera.keys.isEmpty ? L("還沒有", "None yet") : L("\(player.camera.keys.count) 個", "\(player.camera.keys.count)"))
                            .font(.caption)
                            .foregroundStyle(Theme.inkSoft)
                        Spacer(minLength: 0)
                        Button(L("刪除這一幀", "Delete this one")) {
                            player.updateCamera { $0.removeKey(at: player.time, tolerance: player.keyTolerance) }
                        }
                        .buttonStyle(PlasticButtonStyle(tone: .gray))
                        .disabled(!player.camera.hasKey(at: player.time, tolerance: player.keyTolerance))
                        Button(L("全部清除", "Clear all")) {
                            player.updateCamera { $0.keys = [] }
                        }
                        .buttonStyle(PlasticButtonStyle(tone: .gray))
                        .disabled(player.camera.keys.isEmpty)
                    }
                }
                Text(L("在預覽畫面上拖移：旋轉（左右拖＝Y 軸、上下拖＝X 軸）。⇧ 拖移＝畫面傾斜（Z 軸）、⌥ 拖移＝平移、滾輪或雙指縮放＝推近拉遠、雙擊＝回正。每次調整會在目前時間點記一個關鍵幀，關鍵幀之間會平滑過渡。",
                       "Drag on the preview: rotate (left-right = Y axis, up-down = X axis). ⇧-drag = roll (Z axis), ⌥-drag = move, scroll or pinch = dolly in/out, double-click = reset. Each change records a keyframe at the current time and the camera eases between keyframes."))
                    .font(.caption)
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Seam()
        }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 5) {
            HStack(alignment: .center, spacing: 8) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(width: 150, alignment: .leading)
                VSeam().frame(height: 22)
                content()
            }
            .controlSize(.small)
            Seam()
        }
    }
}

private struct ParamRow: View {
    let param: EffectParam
    @ObservedObject var store: ParamStore

    var body: some View {
        VStack(spacing: 5) {
            row
            Seam()
        }
    }

    private var row: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(param.displayLabel)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .frame(width: 150, alignment: .leading)
                .help(param.displayLabel)
            VSeam().frame(height: 22)
            control
        }
        .controlSize(.small)
    }

    @ViewBuilder
    private var control: some View {
        switch param.type {
        case .text:
            PlasticTextField(text: stringBinding, axis: .vertical)
                .lineLimit(1...3)
        case .font:
            FontPicker(selection: stringBinding)
        case .color:
            ColorControl(hex: stringBinding)
        case .number:
            NumberControl(param: param, value: numberBinding)
        case .select:
            BrickMenu(title: param.displayOption(stringBinding.wrappedValue)) {
                Picker("", selection: stringBinding) {
                    ForEach(param.options ?? [], id: \.self) { Text(param.displayOption($0)).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        }
    }

    private var stringBinding: Binding<String> {
        Binding(
            get: { store.values[param.key]?.string ?? param.default.string ?? "" },
            set: { store.values[param.key] = .string($0) }
        )
    }

    private var numberBinding: Binding<Double> {
        Binding(
            get: { store.values[param.key]?.number ?? param.default.number ?? 0 },
            set: { store.values[param.key] = .number($0) }
        )
    }
}

private struct NumberControl: View {
    let param: EffectParam
    @Binding var value: Double

    var body: some View {
        let low = param.min ?? 0
        let high = Swift.max(param.max ?? Swift.max(1, (param.default.number ?? 1) * 2), low + 0.0001)
        HStack(spacing: 6) {
            // 不用 Slider 的 step：macOS 會在每一格畫刻度，格數多時擠成一條。改成自己對齊。
            PlasticSlider(
                value: Binding(
                    get: { value },
                    set: { new in
                        guard let step = param.step, step > 0 else { value = new; return }
                        value = low + ((new - low) / step).rounded() * step
                    }
                ),
                range: low...high
            )
            Text(formatted)
                .monospacedDigit()
                .font(.caption)
                .frame(width: 42, alignment: .trailing)
        }
    }

    private var formatted: String {
        (param.step ?? 0) >= 1 ? String(format: "%.0f", value) : String(format: "%.2f", value)
    }
}

/// 色塊打開系統顏色面板；旁邊的色碼欄也可以直接輸入 #RRGGBB 後按 Return
private struct ColorControl: View {
    @Binding var hex: String
    @State private var draft = ""
    @State private var owner = UUID()

    var body: some View {
        HStack(spacing: 6) {
            Button {
                ColorPanelBridge.shared.open(color: NSColor(hex: hex) ?? .white, owner: owner) { hex = $0.hexString }
            } label: {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(nsColor: NSColor(hex: hex) ?? .white))
                    .frame(width: 28, height: 20)
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.black.opacity(0.45), lineWidth: 1.2))
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.black.opacity(0.35)).offset(y: 2.5))
            }
            .buttonStyle(.plain)
            .help(L("選擇顏色", "Choose a color"))

            PlasticTextField(placeholder: "#RRGGBB", text: $draft)
                .font(.caption.monospaced())
                .frame(width: 96)
                .onSubmit {
                    if let color = NSColor(hex: draft) { hex = color.hexString } else { draft = hex }
                }
            Spacer(minLength: 0)
        }
        .onAppear { draft = hex }
        .onChange(of: hex) { _, new in draft = new }
        .onDisappear { ColorPanelBridge.shared.close(owner: owner) }
    }
}

/// SwiftUI 的 ColorPicker 在不搶焦點的懸浮面板裡打不開（系統顏色面板會因 App 不在前景而自動隱藏），
/// 所以自己設定系統顏色面板：不自動隱藏、疊在 MotionShelf 上面、全螢幕時也看得到。
@MainActor
private final class ColorPanelBridge: NSObject {
    static let shared = ColorPanelBridge()

    private var owner: UUID?
    private var onChange: ((NSColor) -> Void)?

    func open(color: NSColor, owner: UUID, onChange: @escaping (NSColor) -> Void) {
        let panel = NSColorPanel.shared
        panel.setTarget(nil)
        panel.setAction(nil)
        panel.showsAlpha = true
        panel.isContinuous = true
        panel.hidesOnDeactivate = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.color = color

        self.owner = owner
        self.onChange = onChange
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        panel.orderFrontRegardless()
    }

    /// 換效果時，原本的色塊消失，就把面板關掉，避免改到別的效果
    func close(owner: UUID) {
        guard self.owner == owner else { return }
        self.owner = nil
        onChange = nil
        NSColorPanel.shared.setTarget(nil)
        NSColorPanel.shared.setAction(nil)
        NSColorPanel.shared.orderOut(nil)
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        onChange?(sender.color)
    }
}

/// 系統已安裝的字體；效果裡指定、但這台 Mac 沒有的字體會標示「未安裝」
private struct FontPicker: View {
    @Binding var selection: String

    private static let families = NSFontManager.shared.availableFontFamilies.filter { !$0.hasPrefix(".") }

    var body: some View {
        BrickMenu(title: Self.families.contains(selection) ? selection : L("\(selection)（未安裝）", "\(selection) (not installed)")) {
            Picker("", selection: $selection) {
                if !Self.families.contains(selection) {
                    Text(L("\(selection)（未安裝）", "\(selection) (not installed)")).tag(selection)
                    Divider()
                }
                ForEach(Self.families, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }
}

/// 「客製化」對話框：打開時蓋在預覽畫面上面，參數區還看得到
struct CustomizePanel: View {
    @ObservedObject var customize: CustomizeChat

    var body: some View {
        ClaudeChatView(chat: customize, placeholder: L("例如：加一個字距參數，用拉桿調整", "e.g. add a letter-spacing slider"), height: 200) {
            VStack(alignment: .leading, spacing: 2) {
                Label(L("客製化：", "Customize: ") + (customize.effect?.name ?? ""), systemImage: "wand.and.stars")
                    .font(.callout.bold())
                    .foregroundStyle(customize.state == .idle || customize.isRunning ? Theme.ink : Theme.greenDeep)
                Text(L("・要調整什麼：例如大小、顏色、速度、字距或圓角", "• What: e.g. size, color, speed, letter spacing, corner radius"))
                Text(L("・怎麼調：要拉桿（數字）、選單（幾個選項）、顏色，還是文字輸入", "• How: a slider (number), a menu (options), a color, or a text field"))
            }
            .font(.caption)
            .foregroundStyle(Theme.inkSoft)
        }
    }
}
