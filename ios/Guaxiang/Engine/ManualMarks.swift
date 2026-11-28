import Foundation

/// 確認標註頁：使用者把標歪的點拖回去（2026-11-28 多米：怕標錯位置，最後讓人再拉一下）。
///
/// 換算方法：
/// 1. 拖的是最正的那一張照片。那張畫面每個網格頂點在照片上和臉平面上的位置都知道（`BestShot.mesh`），
///    照片上的起點、終點各換成臉平面上的位置，相減就是這一點在臉上偏了多少。
/// 2. 臉平面是貼著臉的座標（ARKit 臉的座標攤平），頭怎麼轉都不變，所以同一個位移直接加到 30 張畫面的同一個點。
/// 3. 加完照原本的流程算特徵、取中位數。沒拖的點一個位元都不動，沒拖任何點時結果跟以前完全一樣。
///
/// 特徵只讀叫得出名字的點（`FaceFrame`），不讀 Vision 的整圈輪廓，所以眉頭、眉尾、眼角、嘴角這些代表點
/// 移了，用到它的特徵就跟著變；輪廓上其他點只拿來畫圖。
enum ManualMarks {
    /// 每一點最多能從原位移多遠，以眼長（內眼角到外眼角，兩眼平均）為單位。
    /// 暫定 0.25（一般人約 7 公釐）：夠把歪掉的眉尾、嘴角拉回去，不夠把長相改成另一種。等真機看到平常歪多少再定
    static let reachInEyes = 0.25
    /// 眼睛沒量到時改用臉寬。暫定 0.06（約 8 公釐，跟上一個差不多大）
    static let reachInFaceWidth = 0.06
    /// 拖完離原位不到可移範圍的 2%，當作沒動（手指點一下會抖一點點，不該算成調過）
    static let still = 0.02

    /// 確認標註頁可以拖的點，由上到下。只放特徵真的會用到、照片上看得出位置的點：
    /// 眉心、鼻底、下巴（三段、臉長、下顎角、人中）；眉頭、眉尾（眉長、眉尾高低、兩眉距離）；
    /// 內外眼角（眼睛長寬、眉長、兩眉距離）；嘴角（嘴寬、嘴角、唇厚）
    static let draggable: [LM] = [
        .glabella,
        .browTailR, .browHeadR, .browHeadL, .browTailL,
        .eyeOuterR, .eyeInnerR, .eyeInnerL, .eyeOuterL,
        .subnasale,
        .mouthR, .mouthL,
        .chin
    ]

    /// 這一點從哪裡來：網格上找的，還是 Vision 輪廓上的某一點
    enum Source {
        case mesh, brow, eye, lips
    }

    static func source(_ lm: LM) -> Source {
        switch lm {
        case .browHeadR, .browTailR, .browHeadL, .browTailL: return .brow
        case .eyeOuterR, .eyeInnerR, .eyeOuterL, .eyeInnerL, .eyeTopR, .eyeBottomR, .eyeTopL, .eyeBottomL: return .eye
        case .mouthR, .mouthL, .lipTop, .lipInnerTop, .lipInnerBottom, .lipBottom: return .lips
        default: return .mesh
        }
    }

    /// 給人看的名字。左右是本人的左右（照片跟照鏡子一樣左右相反，所以看到的也是這一邊）
    static func name(_ lm: LM) -> String {
        switch lm {
        case .glabella: return "眉心"
        case .subnasale: return "鼻子底"
        case .chin: return "下巴"
        case .browHeadR: return "右眉頭"
        case .browTailR: return "右眉尾"
        case .browHeadL: return "左眉頭"
        case .browTailL: return "左眉尾"
        case .eyeInnerR: return "右眼內眼角"
        case .eyeOuterR: return "右眼外眼角"
        case .eyeInnerL: return "左眼內眼角"
        case .eyeOuterL: return "左眼外眼角"
        case .mouthR: return "右嘴角"
        case .mouthL: return "左嘴角"
        default: return lm.rawValue
        }
    }

    /// 可移範圍（臉平面的單位）。眼睛和臉寬都沒量到就是 nil，那一次不給拖
    static func reach(_ frame: FaceFrame) -> Double? {
        if let oR = frame[.eyeOuterR], let iR = frame[.eyeInnerR], let oL = frame[.eyeOuterL],
            let iL = frame[.eyeInnerL]
        {
            let eye = (Geometry.dist(oR, iR) + Geometry.dist(oL, iL)) / 2
            if eye > 0, eye.isFinite { return eye * reachInEyes }
        }
        if let r = frame[.cheekR], let l = frame[.cheekL] {
            let width = Geometry.dist(r, l)
            if width > 0, width.isFinite { return width * reachInFaceWidth }
        }
        return nil
    }

    /// 位移超過可移範圍就照同一個方向縮回邊上。只留左右上下，z 一律是 0（拖的點都不拿來算深度）
    static func clamp(_ d: Pt, reach: Double) -> Pt {
        guard d.x.isFinite, d.y.isFinite else { return Pt(x: 0, y: 0) }
        let length = hypot(d.x, d.y)
        let limit = max(0, reach)
        guard length > limit, length > 0 else { return Pt(x: d.x, y: d.y) }
        let k = limit / length
        return Pt(x: d.x * k, y: d.y * k)
    }

    /// 照片上從 from 拖到 to，換成臉平面上的位移
    static func delta(_ mapper: PlaneMapper, from: UV, to: UV) -> Pt? {
        guard let a = mapper.map(from), let b = mapper.map(to) else { return nil }
        return Pt(x: b.x - a.x, y: b.y - a.y)
    }

    /// 拖到的位置，和它在臉上的位移。limited 是被可移範圍擋住了
    struct Placed: Equatable {
        var uv: UV
        var delta: Pt
        var limited: Bool
    }

    /// 手指拖到 to：沒超過可移範圍就放在那裡；超過了，沿著拖的方向退回到範圍邊上（照片上的位置也跟著退，
    /// 畫面上的點跟算進去的位移才是同一個）
    static func place(_ mapper: PlaneMapper, from: UV, to: UV, reach: Double) -> Placed? {
        guard let d = delta(mapper, from: from, to: to) else { return nil }
        if hypot(d.x, d.y) <= reach { return Placed(uv: to, delta: d, limited: false) }
        // 往回找範圍的邊。lo 一直是在範圍內的那一頭
        var lo = 0.0, hi = 1.0
        var best = Placed(uv: from, delta: Pt(x: 0, y: 0), limited: true)
        for _ in 0..<24 {
            let t = (lo + hi) / 2
            let uv = UV(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
            if let d = delta(mapper, from: from, to: uv), hypot(d.x, d.y) <= reach {
                lo = t
                best = Placed(uv: uv, delta: d, limited: true)
            } else {
                hi = t
            }
        }
        return best
    }

    /// 這一點原本在照片上的哪裡。
    /// 網格的點照片上記著位置，直接用；眉毛、眼睛、嘴唇的點是 Vision 輪廓上的某一點，
    /// 在那條輪廓上找換到臉平面後跟它重合的那一點，畫面上的點才會剛好壓在輪廓上。找不到（差太多）就不給拖
    static func origin(
        _ lm: LM, frame: FaceFrame, marked: UV?, outline: [UV], mapper: PlaneMapper, reach: Double
    ) -> UV? {
        guard frame[lm] != nil else { return nil }
        if source(lm) == .mesh { return marked }
        guard let target = frame[lm] else { return nil }
        var best: (uv: UV, d: Double)?
        for uv in outline {
            guard let p = mapper.map(uv) else { continue }
            let d = Geometry.dist(p, target)
            if best == nil || d < best!.d { best = (uv, d) }
        }
        guard let best, best.d <= reach * 0.1 else { return nil }
        return best.uv
    }

    /// 把位移加到一張畫面。這張沒量到的點不補
    static func apply(_ nudges: [LM: Pt], to frame: FaceFrame) -> FaceFrame {
        var out = frame
        for (lm, d) in nudges where d.x != 0 || d.y != 0 {
            guard let p = out[lm] else { continue }
            out[lm] = Pt(x: p.x + d.x, y: p.y + d.y, z: p.z)
        }
        return out
    }

    /// 每一張都加同一個位移。沒有要移的點就原樣還回去
    static func apply(_ nudges: [LM: Pt], to frames: [FaceFrame]) -> [FaceFrame] {
        let moving = nudges.filter { $0.value.x != 0 || $0.value.y != 0 }
        guard !moving.isEmpty else { return frames }
        return frames.map { apply(moving, to: $0) }
    }

    /// 掃完按「看報告」時的計算：套上手動調的點，每張算特徵，取中位數。
    /// edits 是 nil 或沒調任何點時，跟加這一頁之前的算法一模一樣
    static func measure(
        _ frames: [FaceFrame], edits: MarkEdits?, hairRatio: Double?, eps: Double, rules: Rules
    ) -> Measured {
        let moved = edits?.frames(frames) ?? frames
        return Stats.summarize(moved.map { FeatureEngine.features($0, hairRatio: hairRatio, eps: eps) }, rules: rules)
    }
}

/// 這一次確認標註改了哪些點。只收可以拖的點，位移一律夾在可移範圍內
struct MarkEdits: Equatable {
    struct Move: Equatable {
        /// 照片上的原位和拖到的位置（0–1）
        var from: UV
        var to: UV
        /// 臉平面上的位移
        var delta: Pt
    }

    /// 每一點最多能移多遠（臉平面的單位）。0 就是一點都不能動
    let reach: Double
    private(set) var moves: [LM: Move] = [:]

    init(reach: Double = 0) {
        self.reach = reach.isFinite ? max(0, reach) : 0
    }

    mutating func set(_ lm: LM, from: UV, to: UV, delta: Pt) {
        guard ManualMarks.draggable.contains(lm) else { return }
        let d = ManualMarks.clamp(delta, reach: reach)
        guard hypot(d.x, d.y) > reach * ManualMarks.still, hypot(d.x, d.y) > 0 else {
            moves[lm] = nil
            return
        }
        moves[lm] = Move(from: from, to: to, delta: d)
    }

    mutating func reset(_ lm: LM) {
        moves[lm] = nil
    }

    /// 調過的點，照 draggable 的順序
    var adjusted: [LM] { ManualMarks.draggable.filter { moves[$0] != nil } }

    var nudges: [LM: Pt] { moves.mapValues { $0.delta } }

    /// 30 張畫面都套上。沒調過就原樣還回去
    func frames(_ frames: [FaceFrame]) -> [FaceFrame] {
        ManualMarks.apply(nudges, to: frames)
    }

    /// 這一點調過以後在臉平面上的位置
    func point(_ lm: LM, in frame: FaceFrame) -> Pt? {
        guard let p = frame[lm] else { return nil }
        guard let d = moves[lm]?.delta else { return p }
        return Pt(x: p.x + d.x, y: p.y + d.y, z: p.z)
    }

    /// 這一點調過以後在照片上的位置
    func photo(_ lm: LM, original: UV?) -> UV? {
        moves[lm]?.to ?? original
    }
}
