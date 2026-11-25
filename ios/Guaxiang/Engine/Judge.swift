import Foundation

/// 一個特徵量出來的結果：30 張畫面的中位數、四分位距、穩不穩
struct FeatureStat: Codable, Equatable {
    var v: Double
    var iqr: Double
    var unstable: Bool
}

typealias Measured = [String: FeatureStat]

/// 掃描前勾的那幾題
struct Answers: Codable, Equatable {
    var browTattoo = false
    var noseSurgery = false
    var noGlasses = true

    /// 掃描前勾了「動過」，用到那個部位的項目都不看。沒勾就是 nil
    func blockedWhy(_ key: String?) -> String? {
        switch key {
        case "brow_tattoo": return browTattoo ? "你勾了紋眉或修眉，眉形是選出來的，不是天生的" : nil
        case "nose_surgery": return noseSurgery ? "你勾了鼻子動過，古書講的是天生的樣子" : nil
        default: return nil
        }
    }
}

/// 跟古書寫的相符、不同、剛好在交界上、這次沒看。四種要分開數，在交界上和沒看的不算相符也不算不同（鐵則 7）。
/// 原始值跟網頁版一樣，標準答案測試要比，不給人看
enum Status: String, Codable {
    case pass = "成"
    case fail = "不成"
    case edge = "交界"
    case unjudged = "不判"

    var word: String {
        switch self {
        case .pass: return "相符"
        case .fail: return "不同"
        case .edge: return "在交界上"
        case .unjudged: return "沒看"
        }
    }
}

/// 四種各有幾項。在交界上、沒看的單獨數，加起來一定等於總數
struct Tally: Equatable {
    let same: Int
    let different: Int
    let onEdge: Int
    let unseen: Int

    init(_ statuses: [Status]) {
        same = statuses.filter { $0 == .pass }.count
        different = statuses.filter { $0 == .fail }.count
        onEdge = statuses.filter { $0 == .edge }.count
        unseen = statuses.filter { $0 == .unjudged }.count
    }

    var total: Int { same + different + onEdge + unseen }

    /// 完整一句：四種都寫出來，是 0 也寫
    func sentence(_ unit: String) -> String {
        "\(same) \(unit)跟古書寫的相符・\(different) \(unit)不同・\(onEdge) \(unit)在交界上・\(unseen) \(unit)沒看"
    }
}

struct TestResult {
    let pass: Bool?
    let x: Double?
    let t: Double?
    let edge: Bool
    let unstable: Bool

    static let missing = TestResult(pass: nil, x: nil, t: nil, edge: false, unstable: false)

    var status: Status {
        guard let pass else { return .unjudged }
        if edge { return .edge }
        return pass ? .pass : .fail
    }
}

struct ConditionRow {
    let condition: Condition
    let result: TestResult
    /// 掃描前勾了「動過」，所以這一條沒看
    var blocked: String?

    var status: Status { result.status }

    /// 這一條的結果，白話
    var line: String {
        let plain = condition.plain ?? ""
        if let blocked { return "\(plain)：這一條沒看，\(blocked)" }
        switch status {
        case .pass: return condition.yes ?? ""
        case .fail: return condition.no ?? ""
        case .edge: return Judge.edgeLine(plain)
        case .unjudged: return "\(plain)：這次量不到"
        }
    }
}

struct OfficialResult: Identifiable {
    let official: Official
    let status: Status
    let why: String?
    let rows: [ConditionRow]
    var id: String { official.id }
}

struct WuxingResult {
    /// 木、金、火、水、土的分數，照這個順序
    let scores: [(name: String, score: Double)]
    let host: String
    let guest: String?
    let weak: Bool
    /// plain 是給人看的白話，lines 是有古書名和術語的版本（給依據清單）
    let relation: (kind: String, lines: [String], plain: [String])?
}

struct PalaceResult: Identifiable {
    let palace: Palace
    let status: Status
    let line: String
    let edge: Bool
    let unstable: Bool
    var id: String { palace.id }
}

struct SantingSegment: Identifiable {
    let k: String
    let part: String
    let life: String
    let v: Double
    var id: String { k }
}

enum Stats {
    static func median(_ values: [Double]) -> Double {
        let s = values.sorted()
        let n = s.count
        guard n > 0 else { return .nan }
        return n % 2 == 1 ? s[(n - 1) / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }

    static func quantile(_ values: [Double], _ q: Double) -> Double {
        let s = values.sorted()
        guard !s.isEmpty else { return .nan }
        let i = Double(s.count - 1) * q
        let lo = Int(i.rounded(.down)), hi = Int(i.rounded(.up))
        return s[lo] + (s[hi] - s[lo]) * (i - Double(lo))
    }

    /// 每個特徵取所有畫面的中位數；四分位距太大就標不穩：有尺的跟尺寬比（接近 0 的鼻樑、嘴角才標得到），
    /// 角度類是超過 3 度，其他跟中位數比。
    /// 一個特徵要在至少一半的畫面上量得到才算數，不然不放進結果（報告會寫沒判）。
    static func summarize(_ frames: [[String: Double]], rules: Rules) -> Measured {
        var out: Measured = [:]
        let keys = Set(frames.flatMap { $0.keys })
        let spread = rules.threshold("unstable_spread") ?? 0.06
        for key in keys {
            let values = frames.compactMap { $0[key] }.filter { $0.isFinite }
            guard !values.isEmpty, values.count * 2 >= frames.count else { continue }
            let med = median(values)
            let iqr = quantile(values, 0.75) - quantile(values, 0.25)
            let unstable: Bool
            if FeatureEngine.degreeFeatures.contains(key) {
                unstable = iqr > 3
            } else if let scale = rules.features[key]?.scale {
                unstable = iqr > spread * abs(scale.to - scale.from)
            } else {
                let base = abs(med) == 0 ? 1e-6 : abs(med)
                unstable = abs(iqr / base) > spread && abs(med) > 0.02
            }
            out[key] = FeatureStat(v: med, iqr: iqr, unstable: unstable)
        }
        return out
    }
}

/// 規則比對。照網頁版 index.html 的 test()、judgeOfficials()、matchRules()、wuxing() 和十二宮那一段。
struct Judge {
    let rules: Rules

    func test(_ F: Measured, _ c: Condition) -> TestResult {
        guard let feature = c.feature, let stat = F[feature], stat.v.isFinite else { return .missing }
        let threshold: Double?
        if let th = c.th {
            threshold = rules.threshold(th)
        } else {
            threshold = c.value
        }
        guard let t = threshold, let op = c.op else { return .missing }
        let x = stat.v
        let pass: Bool
        switch op {
        case ">=": pass = x >= t
        case "<=": pass = x <= t
        case ">": pass = x > t
        default: pass = x < t
        }
        // 交界：離門檻不超過 rules.json 的 edge。落在裡面不算相符，也不算不同
        let edge = abs(x - t) <= (rules.features[feature]?.edge ?? 0)
        return TestResult(pass: pass, x: x, t: t, edge: edge, unstable: stat.unstable)
    }

    static func edgeLine(_ plain: String) -> String {
        "\(plain)：剛好在交界上，換個光線再掃可能會變，不算相符也不算不同"
    }

    func officials(_ F: Measured, answers: Answers) -> [OfficialResult] {
        rules.officials.map { o -> OfficialResult in
            if o.conditions.isEmpty {
                return OfficialResult(official: o, status: .unjudged, why: o.unjudged, rows: [])
            }
            if let why = answers.blockedWhy(o.blockedBy) {
                return OfficialResult(official: o, status: .unjudged, why: why, rows: [])
            }
            let rows = o.conditions.map { c -> ConditionRow in
                let blocked = answers.blockedWhy(c.blockedBy)
                return ConditionRow(condition: c, result: blocked == nil ? test(F, c) : .missing, blocked: blocked)
            }
            if let hit = rows.first(where: { $0.blocked != nil }) {
                return OfficialResult(
                    official: o, status: .unjudged,
                    why: "「\(hit.condition.plain ?? "")」這一條沒看：\(hit.blocked ?? "")", rows: rows)
            }
            if rows.contains(where: { $0.result.pass == nil }) {
                return OfficialResult(official: o, status: .unjudged, why: "這次量到的資料不夠", rows: rows)
            }
            // 有一條明確不同就是不同；沒有不同、但有一條在交界上，整官算在交界上
            let all = rows.map(\.status)
            let status: Status = all.contains(.fail) ? .fail : all.contains(.edge) ? .edge : .pass
            return OfficialResult(official: o, status: status, why: nil, rows: rows)
        }
    }

    /// 落在交界的不算對上；三段剛好在交界時，固定放 onEdge 那一條的原文（它兩種都講到）
    func matchRules(_ F: Measured, hasHair: Bool, answers: Answers) -> [Rule] {
        rules.rules.filter { r in
            if r.needHairline == true, !hasHair { return false }
            if answers.blockedWhy(r.blockedBy) != nil { return false }
            return r.when.conditions.allSatisfy { c in
                switch test(F, c).status {
                case .pass: return true
                case .edge: return r.onEdge == true
                case .fail, .unjudged: return false
                }
            }
        }
    }

    /// 三段「差不多長」那一條比出來的結果
    func santing(_ F: Measured) -> TestResult {
        guard let c = rules.rules.first(where: { $0.id == "santing-equal" })?.when.conditions.first else {
            return .missing
        }
        return test(F, c)
    }

    /// 臉形推估。計分是本工具暫定的，古書沒有給數字。少了臉長寬比、額顎比或下顎角就不看。
    func wuxing(_ F: Measured, hasHair: Bool) -> WuxingResult? {
        guard let A = F["face_aspect"]?.v, let R = F["fore_jaw"]?.v, let J = F["jaw_angle"]?.v else { return nil }
        let Lh: Double
        if hasHair {
            guard let l = F["santing_L"]?.v else { return nil }
            Lh = l
        } else {
            Lh = F["santing_L_ml"]?.v ?? 1
        }
        let cl: (Double) -> Double = { max(0, min(1, $0)) }
        let scores: [(name: String, score: Double)] = [
            ("木", cl((A - 1.30) / 0.20)),
            ("金", (1 - cl(abs(R - 1.0) / 0.12)) * cl((130 - J) / 12)),
            ("火", cl((0.95 - R) / 0.15)),
            ("水", cl((1.30 - A) / 0.15) * cl((J - 124) / 12)),
            ("土", cl((1.32 - A) / 0.15) * cl((Lh - 1.0) / 0.12))
        ]
        // 分數高的在前；同分照上面的順序
        let ranked = scores.enumerated().sorted { a, b in
            a.element.score != b.element.score ? a.element.score > b.element.score : a.offset < b.offset
        }.map(\.element)
        let host = ranked[0].name, hostScore = ranked[0].score
        let guest: String? = (ranked[1].score >= 0.25 && ranked[1].score >= hostScore * 0.6) ? ranked[1].name : nil
        let W = rules.wuxing
        var relation: (kind: String, lines: [String], plain: [String])?
        if let guest {
            let lines: ([String]) -> [String] = { $0.map { W.keRule[$0] ?? "" } }
            let plain: ([String]) -> [String] = { $0.map { W.keRulePlain[$0] ?? "" } }
            if W.sheng[guest] == host {
                let keys = ["sheng"]
                relation = ("客生主", lines(keys), plain(keys))
            } else if W.ke[guest] == host {
                let keys = ["quanbian_guestKillsHost", "bingjian_guestKillsHost"]
                relation = ("客剋主", lines(keys), plain(keys))
            } else if W.ke[host] == guest {
                let keys = ["quanbian_hostKillsGuest", "bingjian_hostKillsGuest"]
                relation = ("主剋客", lines(keys), plain(keys))
            } else if W.sheng[host] == guest {
                relation = ("主生客", ["兩本書都沒有這一組的例子，古書在這裡沒有說法。"], plain(["none"]))
            }
        }
        return WuxingResult(scores: scores, host: host, guest: guest, weak: hostScore < 0.2, relation: relation)
    }

    /// 十二宮。量得到的才比，其他寫明為什麼這次沒看。
    func palaces(_ F: Measured, answers: Answers, santingRule: Rule?) -> [PalaceResult] {
        rules.palaces.map { g -> PalaceResult in
            let unjudged: (String) -> PalaceResult = {
                PalaceResult(palace: g, status: .unjudged, line: $0, edge: false, unstable: false)
            }
            guard let m = g.measure else { return unjudged(g.why ?? "") }
            if let why = answers.blockedWhy(g.blockedBy) { return unjudged(why + "。") }
            let onEdge: (TestResult) -> PalaceResult = {
                PalaceResult(
                    palace: g, status: .edge, line: Judge.edgeLine(m.plain ?? "") + "。", edge: true,
                    unstable: $0.unstable)
            }
            if m.type == "santing" {
                guard let santingRule else { return unjudged("沒有拉髮際線，量不到臉的上段。") }
                let st = santing(F)
                if st.edge { return onEdge(st) }
                let ok = santingRule.id == "santing-equal"
                return PalaceResult(
                    palace: g, status: ok ? .pass : .fail, line: (ok ? m.yes : m.no) ?? "", edge: false,
                    unstable: false)
            }
            let t = test(F, m)
            guard let pass = t.pass else { return unjudged("這次量到的資料不夠。") }
            if t.edge { return onEdge(t) }
            return PalaceResult(
                palace: g, status: t.status, line: (pass ? m.yes : m.no) ?? "", edge: false,
                unstable: t.unstable)
        }
    }

    /// 流年：實歲加一換成虛歲，查今年和明年走到哪個部位
    func liunian(age: Int?) -> (xu: Int, hit: LiunianRow?, next: LiunianRow?)? {
        guard let age, age > 0 else { return nil }
        let xu = age + 1
        let table = rules.liunian.table
        return (
            xu, table.first { xu >= $0.from && xu <= $0.to },
            table.first { xu + 1 >= $0.from && xu + 1 <= $0.to }
        )
    }
}
