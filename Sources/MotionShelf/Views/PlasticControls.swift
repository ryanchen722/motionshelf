import SwiftUI

/// 立體滑桿：凹下去的槽、藍色填充、凸起的圓形旋鈕
struct PlasticSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    private let knob: CGFloat = 20
    private let groove: CGFloat = 9

    private var fraction: CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat(min(max((value - range.lowerBound) / span, 0), 1))
    }

    var body: some View {
        GeometryReader { geo in
            let travel = max(geo.size.width - knob, 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color(rgb: 0xD2CAB4))
                    .frame(height: groove)
                    .overlay(Capsule().strokeBorder(LinearGradient(colors: [.black.opacity(0.35), .white.opacity(0.7)], startPoint: .top, endPoint: .bottom), lineWidth: 2))
                    .overlay(Capsule().stroke(Theme.seam.opacity(0.35), lineWidth: 1))

                Capsule().fill(LinearGradient(colors: [Theme.blue, Theme.blueDeep], startPoint: .top, endPoint: .bottom))
                    .frame(width: knob / 2 + travel * fraction, height: groove - 2)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1).padding(.horizontal, 1))
                    .padding(.leading, 1)

                PlasticFill(shape: Circle(), top: Color(rgb: 0xFFFBF2), bottom: Color(rgb: 0xDDD3B8), depth: 3)
                    .frame(width: knob, height: knob)
                    .overlay(Circle().fill(.black.opacity(0.07)).frame(width: 8, height: 8))
                    .offset(x: travel * fraction)
            }
            .frame(height: geo.size.height)
            .overlay(SliderDragCatcher(knob: knob) { fraction in
                value = range.lowerBound + (range.upperBound - range.lowerBound) * Double(fraction)
            })
        }
        .frame(height: knob + 6)
    }
}

/// 接住滑桿上的滑鼠。面板設了「拖背景可移動視窗」，SwiftUI 的拖曳手勢會被搶走，所以用 AppKit 自己處理。
private struct SliderDragCatcher: NSViewRepresentable {
    let knob: CGFloat
    let onChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.knob = knob
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.knob = knob
        view.onChange = onChange
    }
}

private final class CatcherView: NSView {
    var knob: CGFloat = 20
    var onChange: ((CGFloat) -> Void)?

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { update(event) }
    override func mouseDragged(with event: NSEvent) { update(event) }

    private func update(_ event: NSEvent) {
        let x = convert(event.locationInWindow, from: nil).x
        let travel = max(bounds.width - knob, 1)
        onChange?(min(max((x - knob / 2) / travel, 0), 1))
    }
}

/// 凹下去的灰色輸入欄；點進去會變成藍色。yellow 是搜尋欄用的黃色。
struct PlasticTextField: View {
    var placeholder = ""
    @Binding var text: String
    var axis: Axis = .horizontal
    var yellow = false
    @FocusState private var focused: Bool

    private var highlighted: Bool { focused && !yellow }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        TextField(placeholder, text: $text, axis: axis)
            .textFieldStyle(.plain)
            .focused($focused)
            .foregroundStyle(highlighted ? Color.white : (yellow ? Color(rgb: 0x4A3A05) : Theme.ink))
            .tint(highlighted ? .white : Theme.blue)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.8), .black.opacity(0.18)], startPoint: .top, endPoint: .bottom), lineWidth: 1.5))
            .overlay(shape.stroke(.black.opacity(0.22), lineWidth: 1))
            .background(shape.fill(.black.opacity(0.22)).offset(y: 2.5))
            .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 3)
    }

    private var fill: LinearGradient {
        let colors: [Color] = yellow ? [Theme.yellow, Theme.yellowDeep]
            : focused ? [Theme.blue, Theme.blueDeep]
            : [Color(rgb: 0xEEEEEA), Color(rgb: 0xD6D6D0)]
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
}

/// 磚塊樣式的下拉選單：灰色凸起的塑膠塊加一個小三角。內容放 Picker（.inline）或按鈕。
struct BrickMenu<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        Menu {
            content
        } label: {
            HStack(spacing: 6) {
                Text(title).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "arrowtriangle.down.fill").font(.system(size: 8))
            }
            .font(.system(.callout, design: .rounded).weight(.semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(PlasticFill(shape: shape, top: Color(rgb: 0xF2F0EA), bottom: Color(rgb: 0xCFCDC5), depth: 3))
            .contentShape(shape)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }
}
