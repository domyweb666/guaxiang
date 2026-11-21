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
}

/// 成＝合格、不成＝不合格、不判＝沒判。三種要分開數，沒判的不能算進合格或不合格（鐵則 7）
enum Status: String, Codable {
    case pass = "成"
    case fail = "不成"
    case unjudged = "不判"

    var word: String {
        switch self {
        case .pass: return "合格"
        case .fail: return "不合格"
        case .unjudged: return "沒判"
        }
    }
}

struct TestResult {
    let pass: Bool?
    let x: Double?
    let t: Double?
    let edge: Bool
    let unstable: Bool

    static let missing = TestResult(pass: nil, x: nil, t: nil, edge: false, unstable: false)
}

struct ConditionRow {
    let condition: Condition
    let result: TestResult
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
    let relation: (kind: String, lines: [String])?
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

    /// 每個特徵取所有畫面的中位數；四分位距 ÷ 中位數超過門檻（角度類是超過 3 度）就標不穩。
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
        // 剛好落在門檻附近：角度類 ±1 度，其他 ±3%
        let edge = FeatureEngine.degreeFeatures.contains(feature) ? abs(x - t) <= 1 : abs(x - t) <= abs(t) * 0.03
        return TestResult(pass: pass, x: x, t: t, edge: edge, unstable: stat.unstable)
    }

    func officials(_ F: Measured, answers: Answers) -> [OfficialResult] {
        rules.officials.map { o -> OfficialResult in
            if o.conditions.isEmpty {
                return OfficialResult(official: o, status: .unjudged, why: o.unjudged, rows: [])
            }
            if o.blockedBy == "brow_tattoo", answers.browTattoo {
                return OfficialResult(
                    official: o, status: .unjudged,
                    why: "你勾了紋眉或修眉，眉形是選出來的，不是天生的（2-4、2-14）", rows: [])
            }
            if o.blockedBy == "nose_surgery", answers.noseSurgery {
                return OfficialResult(
                    official: o, status: .unjudged, why: "你勾了鼻子動過，原典假設臉是天生的（第五部）", rows: [])
            }
            let rows = o.conditions.map { ConditionRow(condition: $0, result: test(F, $0)) }
            if rows.contains(where: { $0.result.pass == nil }) {
                return OfficialResult(official: o, status: .unjudged, why: "量測資料不足", rows: rows)
            }
            let status: Status = rows.allSatisfy { $0.result.pass == true } ? .pass : .fail
            return OfficialResult(official: o, status: status, why: nil, rows: rows)
        }
    }

    func matchRules(_ F: Measured, hasHair: Bool) -> [Rule] {
        rules.rules.filter { r in
            if r.needHairline == true, !hasHair { return false }
            return r.when.conditions.allSatisfy { test(F, $0).pass == true }
        }
    }

    /// 臉形推估。計分是本工具暫定的，古書沒有給數字。少了臉長寬比、額顎比或下顎角就不判。
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
        var relation: (kind: String, lines: [String])?
        if let guest {
            let line: (String) -> String = { W.keRule[$0] ?? "" }
            if W.sheng[guest] == host {
                relation = ("客生主", [line("sheng")])
            } else if W.ke[guest] == host {
                relation = ("客剋主", [line("quanbian_guestKillsHost"), line("bingjian_guestKillsHost")])
            } else if W.ke[host] == guest {
                relation = ("主剋客", [line("quanbian_hostKillsGuest"), line("bingjian_hostKillsGuest")])
            } else if W.sheng[host] == guest {
                relation = ("主生客", ["兩本書都沒有這一組的例子，古書在這裡沒有說法。"])
            }
        }
        return WuxingResult(scores: scores, host: host, guest: guest, weak: hostScore < 0.2, relation: relation)
    }

    /// 十二宮。量得到的才判，其他寫明為什麼這次沒判。
    func palaces(_ F: Measured, answers: Answers, santingRule: Rule?) -> [PalaceResult] {
        rules.palaces.map { g -> PalaceResult in
            let unjudged: (String) -> PalaceResult = {
                PalaceResult(palace: g, status: .unjudged, line: $0, edge: false, unstable: false)
            }
            guard let m = g.measure else { return unjudged(g.why ?? "") }
            if g.blockedBy == "nose_surgery", answers.noseSurgery {
                return unjudged("你勾了鼻子動過，原典假設臉是天生的。")
            }
            if g.blockedBy == "brow_tattoo", answers.browTattoo {
                return unjudged("你勾了紋眉或修眉，眉形是選出來的，不是天生的。")
            }
            if m.type == "santing" {
                guard let santingRule else { return unjudged("沒有拉髮際線，量不到臉的上段。") }
                let ok = santingRule.id == "santing-equal"
                return PalaceResult(
                    palace: g, status: ok ? .pass : .fail, line: (ok ? m.yes : m.no) ?? "", edge: false,
                    unstable: false)
            }
            let t = test(F, m)
            guard let pass = t.pass else { return unjudged("量測資料不足。") }
            return PalaceResult(
                palace: g, status: pass ? .pass : .fail, line: (pass ? m.yes : m.no) ?? "", edge: t.edge,
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
