import SwiftUI

/// 強烈樂高玩具風：厚實積木、明顯凸點、高對比原色
enum Theme {
    static let cream = Color(rgb: 0xF9F0DC)
    static let creamDeep = Color(rgb: 0xE4D5B0)
    static let card = Color(rgb: 0xFFF9EB)
    static let green = Color(rgb: 0x4CAF50)
    static let greenDeep = Color(rgb: 0x2E7D32)
    static let red = Color(rgb: 0xEF5350)
    static let redDeep = Color(rgb: 0xC62828)
    static let yellow = Color(rgb: 0xFFCA28)
    static let yellowDeep = Color(rgb: 0xF9A825)
    static let blue = Color(rgb: 0x42A5F5)
    static let blueDeep = Color(rgb: 0x1565C0)
    static let ink = Color(rgb: 0x2A261F)
    static let inkSoft = Color(rgb: 0x6E6555)
    static let seam = Color(rgb: 0x5C4B2E)
    static let line = Color(rgb: 0xD0C29E)
}

extension Color {
    init(rgb: UInt32) {
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

/// 厚實樂高磁磚
struct Tile: ViewModifier {
    var padding: CGFloat = 10

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)

        content
            .padding(padding)
            .background(
                ZStack {
                    // 底部厚度
                    shape
                        .fill(Color(rgb: 0xB8AB88))
                        .offset(y: 4.5)

                    // 主體
                    shape
                        .fill(
                            LinearGradient(
                                colors: [Theme.card, Color(rgb: 0xF3E9D0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            shape.fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.5), .clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                        )
                        .overlay(
                            shape.strokeBorder(.white.opacity(0.8), lineWidth: 1.4).padding(1)
                        )
                        .overlay(
                            shape.stroke(Theme.seam.opacity(0.55), lineWidth: 1.3)
                        )
                }
            )
            .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 3)
    }
}

extension View {
    func tile(padding: CGFloat = 10) -> some View {
        modifier(Tile(padding: padding))
    }
}

/// 磁磚縫
struct Seam: View {
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.seam.opacity(0.38)).frame(height: 1.2)
            Rectangle().fill(.white.opacity(0.75)).frame(height: 1.2)
        }
    }
}

/// 直縫
struct VSeam: View {
    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(Theme.seam.opacity(0.38)).frame(width: 1.2)
            Rectangle().fill(.white.opacity(0.75)).frame(width: 1.2)
        }
    }
}

enum Tone {
    case green, red, yellow, blue, gray

    var top: Color {
        switch self {
        case .green: Theme.green
        case .red: Theme.red
        case .yellow: Theme.yellow
        case .blue: Theme.blue
        case .gray: Color(rgb: 0xEDEBE4)
        }
    }

    var bottom: Color {
        switch self {
        case .green: Theme.greenDeep
        case .red: Theme.redDeep
        case .yellow: Theme.yellowDeep
        case .blue: Theme.blueDeep
        case .gray: Color(rgb: 0xC2C0B8)
        }
    }

    var text: Color {
        switch self {
        case .yellow: Color(rgb: 0x3F3204)
        case .gray: Theme.ink
        default: .white
        }
    }
}

/// 超厚塑膠積木填充（按下去會明顯下沉）
struct PlasticFill<S: InsettableShape>: View {
    let shape: S
    var top: Color
    var bottom: Color
    var pressed = false
    /// 底下厚邊的高度；小零件（旋鈕、選單、小圓鈕）用薄一點的
    var depth: CGFloat = 6

    var body: some View {
        ZStack {
            // 厚度層
            shape
                .fill(.black.opacity(0.5))
                .offset(y: pressed ? 1.5 : depth)

            // 主體
            shape
                .fill(LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom))
                .overlay(
                    shape.fill(
                        LinearGradient(
                            colors: [.white.opacity(0.42), .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                )
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.75), .black.opacity(0.3)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.8
                    )
                )
                .overlay(
                    shape.stroke(.black.opacity(0.32), lineWidth: 1.1)
                )
        }
        .shadow(color: .black.opacity(pressed ? 0.18 : 0.42), radius: pressed ? 1.5 : depth, x: 0, y: pressed ? 1 : depth + 1)
    }
}

/// 樂高積木風格按鈕（比較方、厚度大）
struct PlasticButtonStyle: ButtonStyle {
    var tone: Tone = .green
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        configuration.label
            .font(.system(.callout, design: .rounded).weight(.heavy))
            .foregroundStyle(tone.text)
            .padding(.horizontal, 15)
            .padding(.vertical, 8)
            .background(
                PlasticFill(shape: shape, top: tone.top, bottom: tone.bottom, pressed: configuration.isPressed)
            )
            .opacity(isEnabled ? 1 : 0.65)
            .offset(y: configuration.isPressed ? 4 : 0)
            .contentShape(shape)
    }
}

/// 標題藥丸
struct BubbleTitle: View {
    let text: String
    var symbol: String = "leaf.fill"
    var tone: Tone = .green

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.caption.bold())
            Text(text).font(.system(.callout, design: .rounded).weight(.heavy))
        }
        .foregroundStyle(tone.text)
        .padding(.horizontal, 13)
        .padding(.vertical, 6)
        .background(
            PlasticFill(
                shape: RoundedRectangle(cornerRadius: 9, style: .continuous),
                top: tone.top,
                bottom: tone.bottom
            )
        )
    }
}
