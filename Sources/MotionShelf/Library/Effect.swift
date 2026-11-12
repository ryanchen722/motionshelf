import AppKit

/// effects/<資料夾>/ 裡的一個效果
struct Effect: Identifiable {
    let id: String            // 資料夾名稱
    let folder: URL
    let manifest: EffectManifest
    let source: String        // source.md 內容，搜尋時也會比對
    let thumbnail: NSImage?

    /// effect.json 有 name_en 時，英文介面顯示英文名稱
    var name: String { Lang.isEnglish ? manifest.name_en ?? manifest.name : manifest.name }
    var category: String { Self.canonical(manifest.category) }
    var htmlURL: URL { folder.appendingPathComponent("effect.html") }

    /// 內建分類。effect.json 裡寫中文或英文都可以，內部一律用中文當代號
    static let categories = ["字卡", "轉場", "粒子", "拼貼", "分割", "UI"]
    private static let english = ["字卡": "Titles", "轉場": "Transitions", "粒子": "Particles", "拼貼": "Collage", "分割": "Split screen", "UI": "UI"]

    static func canonical(_ category: String) -> String {
        english.first { $0.value.caseInsensitiveCompare(category) == .orderedSame }?.key ?? category
    }

    /// 依介面語言顯示分類名稱；自訂分類照原樣顯示
    static func displayName(_ category: String) -> String {
        Lang.isEnglish ? english[category] ?? category : category
    }
}

extension URL {
    /// 家目錄縮寫成 ~ 的路徑，給人看的
    var abbreviatedPath: String { (path as NSString).abbreviatingWithTildeInPath }
}

/// effect.json 的內容
struct EffectManifest: Decodable {
    let name: String
    let name_en: String?
    let category: String
    let duration: Double
    let fps: Int
    let params: [EffectParam]
}

struct EffectParam: Decodable, Identifiable {
    enum Kind: String, Decodable {
        case text, font, color, number, select
    }

    let key: String
    let type: Kind
    let label: String?
    let label_en: String?
    let `default`: JSONValue
    let min: Double?
    let max: Double?
    let step: Double?
    let options: [String]?
    /// select 選項在英文介面的顯示文字，順序和 options 一樣；存進參數的值還是 options
    let options_en: [String]?

    var id: String { key }

    var displayLabel: String { (Lang.isEnglish ? label_en ?? label : label) ?? key }

    func displayOption(_ option: String) -> String {
        guard Lang.isEnglish, let english = options_en, let index = options?.firstIndex(of: option), index < english.count else { return option }
        return english[index]
    }
}

enum JSONValue: Decodable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }
}

/// 讀不進來的效果資料夾，顯示在清單下方，方便找錯
struct EffectProblem: Identifiable, Error {
    let id: String
    let message: String
}

extension Effect {
    static func load(from folder: URL) -> Result<Effect, EffectProblem> {
        let id = folder.lastPathComponent
        let fail = { (message: String) in Result<Effect, EffectProblem>.failure(EffectProblem(id: id, message: message)) }
        let fm = FileManager.default

        guard fm.fileExists(atPath: folder.appendingPathComponent("effect.html").path) else {
            return fail(L("找不到 effect.html", "effect.html not found"))
        }
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("effect.json")) else {
            return fail(L("找不到 effect.json", "effect.json not found"))
        }

        let manifest: EffectManifest
        do {
            manifest = try JSONDecoder().decode(EffectManifest.self, from: data)
        } catch {
            return fail("effect.json：" + describe(error))
        }

        let source = (try? String(contentsOf: folder.appendingPathComponent("source.md"), encoding: .utf8)) ?? ""
        let thumbnail = NSImage(contentsOf: folder.appendingPathComponent("thumb.png"))
        return .success(Effect(id: id, folder: folder, manifest: manifest, source: source, thumbnail: thumbnail))
    }

    private static func describe(_ error: Error) -> String {
        guard let error = error as? DecodingError else { return error.localizedDescription }
        func path(_ context: DecodingError.Context) -> String {
            context.codingPath.map { $0.intValue.map { L("第 \($0 + 1) 項", "item \($0 + 1)") } ?? $0.stringValue }.joined(separator: " → ")
        }
        switch error {
        case .keyNotFound(let key, let context):
            let at = path(context)
            return at.isEmpty ? L("缺少欄位「\(key.stringValue)」", "Missing the field \"\(key.stringValue)\"") : L("\(at) 缺少欄位「\(key.stringValue)」", "\(at) is missing the field \"\(key.stringValue)\"")
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            return L("「\(path(context))」的值類型不對", "\"\(path(context))\" has the wrong value type")
        case .dataCorrupted(let context):
            return context.codingPath.isEmpty
                ? L("JSON 格式錯誤（常見原因：少了逗號、括號，或多了最後一個逗號）", "Invalid JSON (common causes: a missing comma or bracket, or a trailing comma)")
                : L("「\(path(context))」的值不正確（type 只能是 text / font / color / number / select）", "\"\(path(context))\" has an invalid value (type must be text / font / color / number / select)")
        @unknown default:
            return error.localizedDescription
        }
    }
}
