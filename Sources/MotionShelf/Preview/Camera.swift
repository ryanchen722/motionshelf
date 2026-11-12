import Foundation

/// 攝影機的一個姿勢：三軸轉動（度）和三軸位置（X、Y 是畫面寬高的百分比，Z 是推近的程度，正值推近）
struct CameraPose: Codable, Equatable {
    var rx = 0.0   // 上下俯仰
    var ry = 0.0   // 左右轉
    var rz = 0.0   // 畫面傾斜
    var px = 0.0   // 攝影機往右
    var py = 0.0   // 攝影機往上
    var pz = 0.0   // 推近（正）／拉遠（負）

    static let flat = CameraPose()

    func mixed(with other: CameraPose, _ k: Double) -> CameraPose {
        func m(_ a: Double, _ b: Double) -> Double { a + (b - a) * k }
        return CameraPose(rx: m(rx, other.rx), ry: m(ry, other.ry), rz: m(rz, other.rz), px: m(px, other.px), py: m(py, other.py), pz: m(pz, other.pz))
    }

    mutating func clamp() {
        rx = min(max(rx, -90), 90)
        ry = min(max(ry, -90), 90)
        rz = min(max(rz, -180), 180)
        px = min(max(px, -100), 100)
        py = min(max(py, -100), 100)
        pz = min(max(pz, -100), 80)
    }
}

struct CameraKey: Codable, Equatable {
    var t: Double
    var pose: CameraPose
}

/// 一個效果的攝影機：開關、透視強度、關鍵幀。像 After Effects：在時間軸上某個時間點擺出姿勢就記成一個關鍵幀，
/// 關鍵幀之間平滑過渡，第一個之前和最後一個之後維持原姿勢。
/// A per-effect 3D camera with keyframes. The picture is tilted with a CSS perspective transform derived from t alone,
/// so preview and export match frame for frame and the transparent background is untouched.
struct CameraState: Codable, Equatable {
    var on = false
    var depth = 1.2
    var keys: [CameraKey] = []

    /// 時間 t 的姿勢：只由 t 決定，所以預覽和輸出每一幀一致
    func pose(at t: Double) -> CameraPose {
        guard let first = keys.first, let last = keys.last else { return .flat }
        if t <= first.t { return first.pose }
        if t >= last.t { return last.pose }
        for index in 1..<keys.count where t <= keys[index].t {
            let a = keys[index - 1], b = keys[index]
            let k = min(max((t - a.t) / max(b.t - a.t, 0.0001), 0), 1)
            return a.pose.mixed(with: b.pose, k * k * (3 - 2 * k))
        }
        return last.pose
    }

    func hasKey(at t: Double, tolerance: Double) -> Bool {
        keys.contains { abs($0.t - t) <= tolerance }
    }

    /// 在時間 t 記下姿勢；那一幀已經有關鍵幀就取代。第一次記在 0 秒之後時，順便在 0 秒放一個正面平視的關鍵幀。
    mutating func setKey(at t: Double, pose: CameraPose, tolerance: Double) {
        if keys.isEmpty && t > tolerance { keys.append(CameraKey(t: 0, pose: .flat)) }
        keys.removeAll { abs($0.t - t) <= tolerance }
        keys.append(CameraKey(t: t, pose: pose))
        keys.sort { $0.t < $1.t }
    }

    mutating func removeKey(at t: Double, tolerance: Double) {
        keys.removeAll { abs($0.t - t) <= tolerance }
    }

    /// 每次 seek(t) 之後要執行的 JavaScript；關閉時把透視清掉
    func script(at t: Double) -> String {
        guard on else {
            return "(()=>{var e=document.documentElement;if(e.dataset.msCam){e.style.transform='';e.style.transformOrigin='';delete e.dataset.msCam}})();0"
        }
        let p = pose(at: t)
        // 位置：攝影機往右，畫面就往左。推近用縮放表現（translateZ 在輸出擷取時位置會偏掉）
        let scale = 1 / (1 - min(max(p.pz, -100), 80) / 100)
        return """
        (()=>{var e=document.documentElement;e.dataset.msCam='1';
        e.style.transformOrigin='50vw 50vh';
        e.style.transform='perspective('+(innerWidth*\(depth))+'px) translate('+(-innerWidth*\(p.px / 100))+'px,'+(innerHeight*\(p.py / 100))+'px) scale(\(scale)) rotateX(\(-p.rx)deg) rotateY(\(p.ry)deg) rotateZ(\(p.rz)deg)';})();0
        """
    }
}

/// 每個效果各自的攝影機設定，存在 UserDefaults
enum CameraStore {
    private static let key = "cameraStates"

    static func load(_ effectID: String) -> CameraState {
        guard let all = UserDefaults.standard.dictionary(forKey: key) as? [String: Data],
              let data = all[effectID],
              let state = try? JSONDecoder().decode(CameraState.self, from: data) else { return CameraState() }
        return state
    }

    static func save(_ state: CameraState, for effectID: String) {
        var all = (UserDefaults.standard.dictionary(forKey: key) as? [String: Data]) ?? [:]
        if state == CameraState() {
            all.removeValue(forKey: effectID)
        } else if let data = try? JSONEncoder().encode(state) {
            all[effectID] = data
        }
        UserDefaults.standard.set(all, forKey: key)
    }
}
