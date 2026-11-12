import AppKit

/// 目前效果的參數值。和播放時間分開，播放時參數面板才不會每幀重畫。
@MainActor
final class ParamStore: ObservableObject {
    @Published private(set) var definitions: [EffectParam] = []
    @Published var values: [String: JSONValue] = [:] {
        didSet { onChange?(values) }
    }

    var onChange: (([String: JSONValue]) -> Void)?

    var defaults: [String: JSONValue] {
        Dictionary(definitions.map { ($0.key, $0.default) }, uniquingKeysWith: { first, _ in first })
    }

    var isDefault: Bool { values == defaults }

    /// 換效果時呼叫；previous 是上次調過的值，參數 key 還在就沿用
    func configure(_ definitions: [EffectParam], keeping previous: [String: JSONValue]) {
        self.definitions = definitions
        var merged = defaults
        for param in definitions {
            if let old = previous[param.key] { merged[param.key] = old }
        }
        values = merged
    }

    func reset() {
        values = defaults
    }

    /// 給 window.setParams 的 JSON
    var json: String {
        let object = values.mapValues(\.any)
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}

extension JSONValue {
    var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var number: Double? {
        if case .number(let value) = self { return value }
        return nil
    }
}

extension NSColor {
    /// 接受 #RRGGBB 或 #RRGGBBAA
    convenience init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6 || text.count == 8, let value = UInt64(text, radix: 16) else { return nil }
        let rgba = text.count == 6 ? value << 8 | 0xFF : value
        self.init(
            srgbRed: CGFloat(rgba >> 24 & 0xFF) / 255,
            green: CGFloat(rgba >> 16 & 0xFF) / 255,
            blue: CGFloat(rgba >> 8 & 0xFF) / 255,
            alpha: CGFloat(rgba & 0xFF) / 255
        )
    }

    /// 不透明時輸出 #RRGGBB，有透明度時輸出 #RRGGBBAA
    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#FFFFFF" }
        let parts = [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent].map { Int(($0 * 255).rounded()) }
        let rgb = String(format: "#%02X%02X%02X", parts[0], parts[1], parts[2])
        return parts[3] == 255 ? rgb : rgb + String(format: "%02X", parts[3])
    }
}
