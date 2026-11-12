import SwiftUI
import WebKit

/// 預覽畫面：放進 16:9 的洞。效果的比例不是 16:9（直式、正方形）時，不夠的地方是底圖的奶油色
struct PreviewScreen: View {
    @ObservedObject var player: EffectPlayer

    var body: some View {
        ZStack {
            Checkerboard()
            EffectWebViewHost(player: player)
            // 攝影機開啟時，在畫面上拖移就能轉動、平移、推近拉遠
            if player.camera.on { CameraDragLayer(player: player) }
            if let error = player.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .padding(10)
                    .background(.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
                    .padding()
            }
        }
        .aspectRatio(player.renderSize.width / player.renderSize.height, contentMode: .fit)
        .overlay(alignment: .bottomTrailing) {
            AxisGizmo(pose: player.camera.on ? player.camera.pose(at: player.time) : .flat, active: player.camera.on)
                .padding(6)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 播放鍵、時間軸、時間和幀數
struct PreviewControls: View {
    @ObservedObject var player: EffectPlayer
    let reload: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            PanelButton(symbol: "backward.frame", help: L("上一幀", "Previous frame")) { player.step(-1) }
            Button(action: player.togglePlay) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(PlasticFill(shape: Circle(), top: Theme.red, bottom: Theme.redDeep))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(player.isPlaying ? L("暫停", "Pause") : L("播放", "Play"))
            PanelButton(symbol: "forward.frame", help: L("下一幀", "Next frame")) { player.step(1) }

            PlasticSlider(
                value: Binding(get: { player.time }, set: { player.seek(to: $0) }),
                range: 0...max(player.duration, 0.01)
            )
            .overlay(alignment: .top) { KeyframeTicks(player: player) }

            Text(String(format: L("%.2f / %.2f 秒", "%.2f / %.2f s"), player.time, player.duration))
                .monospacedDigit()
                .font(.caption)
            Text(L("幀 \(player.frame)/\(player.frameCount)", "Frame \(player.frame)/\(player.frameCount)"))
                .monospacedDigit()
                .font(.caption)
                .foregroundStyle(Theme.inkSoft)
                .fixedSize()
                .frame(width: 62, alignment: .leading)

            Button {
                player.loops.toggle()
            } label: {
                Image(systemName: "repeat").font(.body.bold()).foregroundStyle(player.loops ? Theme.greenDeep : Theme.inkSoft.opacity(0.6))
            }
            .buttonStyle(.borderless)
            .help(player.loops ? L("重複播放：開", "Loop: on") : L("重複播放：關", "Loop: off"))

            PanelButton(symbol: "arrow.clockwise", help: L("重新載入效果（改過 effect.html 或 effect.json 之後按）", "Reload the effect (after editing effect.html or effect.json)"), action: reload)
        }
        .disabled(player.effect == nil)
    }
}

/// 讓 WKWebView 的 CSS 畫布永遠是 renderSize（例如 1920 寬），再縮放到預覽框的大小
private struct EffectWebViewHost: NSViewRepresentable {
    let player: EffectPlayer

    func makeNSView(context: Context) -> ZoomingContainer {
        ZoomingContainer(webView: player.webView, renderWidth: player.renderSize.width)
    }

    func updateNSView(_ nsView: ZoomingContainer, context: Context) {
        nsView.renderWidth = player.renderSize.width
    }
}

private final class ZoomingContainer: NSView {
    private let webView: WKWebView
    var renderWidth: CGFloat {
        didSet { needsLayout = true }
    }

    init(webView: WKWebView, renderWidth: CGFloat) {
        self.webView = webView
        self.renderWidth = renderWidth
        super.init(frame: .zero)
        addSubview(webView)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        webView.frame = bounds
        if bounds.width > 0 { webView.pageZoom = bounds.width / renderWidth }
    }
}

/// 灰白棋盤格：一般軟體表示「透明」的樣子
private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 10
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.98)))
            for row in 0..<Int(size.height / cell) + 1 {
                for col in 0..<Int(size.width / cell) + 1 where (row + col).isMultiple(of: 2) {
                    let rect = CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
                    context.fill(Path(rect), with: .color(Color(white: 0.84)))
                }
            }
        }
    }
}


/// 時間軸上的關鍵幀標記（橘色菱形）；位置和 PlasticSlider 的旋鈕行程一致（旋鈕寬 20）
private struct KeyframeTicks: View {
    @ObservedObject var player: EffectPlayer

    var body: some View {
        GeometryReader { geo in
            if player.camera.on, player.duration > 0 {
                ForEach(Array(player.camera.keys.enumerated()), id: \.offset) { _, key in
                    Rectangle()
                        .fill(Theme.red)
                        .frame(width: 8, height: 8)
                        .rotationEffect(.degrees(45))
                        .overlay(Rectangle().stroke(.white.opacity(0.8), lineWidth: 1).rotationEffect(.degrees(45)))
                        .position(x: 10 + (geo.size.width - 20) * min(max(key.t / player.duration, 0), 1), y: 3)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// 右下角的三維座標：X 紅、Y 綠、Z 藍，會跟著目前的攝影機姿勢轉動，下面是數值
private struct AxisGizmo: View {
    let pose: CameraPose
    let active: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let length: CGFloat = 30
                // CSS 的轉動順序：rotateX(-rx) rotateY(ry) rotateZ(rz)，向量先經過 Z、再 Y、最後 X
                func rotate(_ v: (x: Double, y: Double, z: Double)) -> (x: Double, y: Double, z: Double) {
                    let (fx, fy, fz) = (-pose.rx * .pi / 180, pose.ry * .pi / 180, pose.rz * .pi / 180)
                    let x1 = v.x * cos(fz) - v.y * sin(fz), y1 = v.x * sin(fz) + v.y * cos(fz), z1 = v.z
                    let x2 = x1 * cos(fy) + z1 * sin(fy), z2 = -x1 * sin(fy) + z1 * cos(fy), y2 = y1
                    let y3 = y2 * cos(fx) - z2 * sin(fx), z3 = y2 * sin(fx) + z2 * cos(fx)
                    return (x2, y3, z3)
                }
                let axes: [(String, (x: Double, y: Double, z: Double), Color)] = [
                    ("X", (1, 0, 0), Color(red: 0.86, green: 0.2, blue: 0.2)),
                    ("Y", (0, -1, 0), Color(red: 0.2, green: 0.62, blue: 0.25)),
                    ("Z", (0, 0, 1), Color(red: 0.2, green: 0.4, blue: 0.9)),
                ]
                let placed = axes.map { (name, vector, color) in (name, rotate(vector), color) }.sorted { $0.1.z < $1.1.z }
                for (name, v, color) in placed {
                    let tip = CGPoint(x: center.x + CGFloat(v.x) * length, y: center.y + CGFloat(v.y) * length)
                    var line = Path()
                    line.move(to: center)
                    line.addLine(to: tip)
                    let alpha = v.z < -0.05 ? 0.55 : 1.0   // 指向畫面後方的軸畫淡一點
                    context.stroke(line, with: .color(color.opacity(alpha)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    context.fill(Path(ellipseIn: CGRect(x: tip.x - 8, y: tip.y - 8, width: 16, height: 16)), with: .color(color.opacity(alpha)))
                    context.draw(Text(name).font(.system(size: 10, weight: .heavy)).foregroundColor(.white), at: tip)
                }
            }
            .frame(width: 78, height: 78)
            Text("X \(Int(pose.rx.rounded()))°  Y \(Int(pose.ry.rounded()))°  Z \(Int(pose.rz.rounded()))°")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .padding(5)
        .foregroundStyle(.white)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.black.opacity(active ? 0.45 : 0.22)))
        .opacity(active ? 1 : 0.7)
    }
}

/// 蓋在預覽畫面上接滑鼠：拖移轉動、⇧ 拖移傾斜、⌥ 拖移平移、滾輪或雙指縮放推近拉遠、雙擊回正。
/// 面板設了「拖背景可移動視窗」，所以用 AppKit 自己處理。
private struct CameraDragLayer: NSViewRepresentable {
    let player: EffectPlayer

    func makeNSView(context: Context) -> CameraDragView { CameraDragView(player: player) }
    func updateNSView(_ view: CameraDragView, context: Context) { view.player = player }
}

private final class CameraDragView: NSView {
    var player: EffectPlayer
    private let degreesPerPoint = 0.4

    init(player: EffectPlayer) {
        self.player = player
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { Task { @MainActor in player.editCameraPose { $0 = .flat } } }
    }

    override func mouseDragged(with event: NSEvent) {
        let dx = Double(event.deltaX), dy = Double(event.deltaY)
        let width = max(Double(bounds.width), 1), height = max(Double(bounds.height), 1)
        let flags = event.modifierFlags
        let degrees = degreesPerPoint
        Task { @MainActor in
            player.editCameraPose { pose in
                if flags.contains(.option) {
                    // 畫面跟著游標走：游標往右，攝影機就往左
                    pose.px -= dx / width * 100
                    pose.py += dy / height * 100
                } else if flags.contains(.shift) {
                    pose.rz += dx * degrees
                } else {
                    pose.ry += dx * degrees
                    pose.rx += dy * degrees
                }
            }
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = Double(event.scrollingDeltaY) * (event.hasPreciseScrollingDeltas ? 0.25 : 2)
        guard delta != 0 else { return }
        Task { @MainActor in player.editCameraPose { $0.pz += delta } }
    }

    override func magnify(with event: NSEvent) {
        let delta = Double(event.magnification) * 100
        Task { @MainActor in player.editCameraPose { $0.pz += delta } }
    }
}
