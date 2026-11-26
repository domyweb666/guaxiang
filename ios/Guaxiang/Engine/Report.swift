import Foundation

/// 存在手機裡的那一份：只有量出來的數字和掃描前的勾選。照片另外存（Store/FacePhoto.swift），匯出時不帶。
/// 相符或不同每次打開都照 rules.json 重新比一次，所以規則庫更新後舊報告會跟著新規則走。
struct Measurement: Codable, Equatable {
    var when: Date
    var frames: Int
    var light: Double
    var hasHair: Bool
    var answers: Answers
    var F: Measured
    var rulesVersion: String
    /// 這次哪些量測來源沒接上（例如眉毛和嘴唇的 2D 定位點），報告最下面會列出來
    var gaps: [String] = []
}

/// 一份報告：量測數字照規則比對完的全部結論。畫面和「問古書」的依據清單都從這裡拿。
struct Report {
    let measurement: Measurement
    let rules: Rules
    let officials: [OfficialResult]
    let matched: [Rule]
    let wuxing: WuxingResult?
    let palaces: [PalaceResult]
    let segments: [SantingSegment]?
    let santingRule: Rule?
    let others: [Rule]
    /// 三段剛好在「差不多長」和「長短不一樣」的交界上
    let santingOnEdge: Bool
    /// 十二件事裡看得到、古書有說法的那幾件（QC-0009）
    let fortunes: [PalaceResult]
    /// 總覽和首頁那幾列。這三個建報告時算一次就好，畫面切分頁、按分段鈕都會讀
    private(set) var highlights: [Highlight] = []

    init(measurement m: Measurement, rules: Rules) {
        let judge = Judge(rules: rules)
        measurement = m
        self.rules = rules
        officials = judge.officials(m.F, answers: m.answers)
        matched = judge.matchRules(m.F, hasHair: m.hasHair, answers: m.answers)
        wuxing = judge.wuxing(m.F, hasHair: m.hasHair)
        santingRule = matched.first { $0.part == "三停" }
        others = matched.filter { $0.part != "三停" }
        palaces = judge.palaces(m.F, answers: m.answers, santingRule: santingRule)
        if m.hasHair, let u = m.F["santing_U"]?.v, let mid = m.F["santing_M"]?.v, let l = m.F["santing_L"]?.v {
            segments = [
                SantingSegment(k: "上段", part: "額頭：髮際到眉心", life: "初年", v: u),
                SantingSegment(k: "中段", part: "眉心到鼻子底", life: "中年", v: mid),
                SantingSegment(k: "下段", part: "鼻子底到下巴", life: "晚年", v: l)
            ]
        } else {
            segments = nil
        }
        santingOnEdge = segments != nil && santingRule != nil && judge.santing(m.F).edge
        fortunes = palaces.filter { $0.palace.say != nil }
        highlights = makeHighlights()
    }

    var officialTally: Tally { Tally(officials.map(\.status)) }
    var palaceTally: Tally { Tally(palaces.map(\.status)) }
}

/// 總覽和首頁那幾列：哪件事、古書說的好處、在哪一區
struct Highlight: Identifiable {
    let topic: String
    let good: String
    let section: ReportSection
    var id: String { topic + good }
}

// MARK: 正面的字：先講好處，再講你的長相

extension PalaceResult {
    /// 這一件事正面寫的那一句
    var front: String {
        guard let say = palace.say else { return line }
        switch status {
        case .pass: return say.pass
        case .fail: return say.fail
        case .edge: return say.edge
        case .unjudged: return line
        }
    }
}

extension ConditionRow {
    /// 這一條正面寫的那一句，只講長相
    var front: String {
        switch status {
        case .pass: return condition.yes ?? ""
        case .fail: return condition.no ?? ""
        case .edge: return condition.mid ?? ""
        case .unjudged: return "\(condition.plain ?? "")：這次沒看"
        }
    }
}

extension SantingSegment {
    /// 初年、晚年換成白話
    var lifeWord: String {
        switch life {
        case "初年": return "年輕時"
        case "晚年": return "老年"
        default: return life
        }
    }
}

extension Report {
    /// 看得到的官。耳朵掃不到，不放（QC-0009）
    var shownOfficials: [OfficialResult] { officials.filter { !$0.official.conditions.isEmpty } }

    /// 十二件事裡掃描看不到的，只放在「這次沒看的」
    var unseenTopics: [Palace] { palaces.map(\.palace).filter { $0.measure == nil } }

    /// 「眉毛、眼睛」。一官都沒相符就是 nil
    var goodOfficials: String? {
        let names = shownOfficials.filter { $0.status == .pass }.map(\.official.plain)
        return names.isEmpty ? nil : names.joined(separator: "、")
    }

    /// 最長的那一段。差不多長、在交界上、沒看，都沒有
    var longestSegment: SantingSegment? {
        guard let segments, let santingRule, !santingOnEdge, santingRule.id != "santing-equal" else { return nil }
        return segments.max { $0.v < $1.v }
    }

    var santingGood: String? {
        guard segments != nil, let santingRule, !santingOnEdge else { return nil }
        if santingRule.id == "santing-equal" { return "一生都平穩" }
        return longestSegment.map { "\($0.lifeWord)最順" }
    }

    var santingFront: String {
        guard segments != nil, let santingRule else { return "沒有拉髮際線，三段這次沒看。" }
        if santingOnEdge { return "你臉的三段，長短介於中間，這次先不說。" }
        if santingRule.id == "santing-equal" { return "你臉的上、中、下三段差不多長。" }
        return "你臉的\(longestSegment?.k ?? "")最長。"
    }

    var shapeName: String { wuxing.map { "\($0.host)形人" } ?? "臉形" }

    /// 臉形的好處；古書沒寫好處的那幾形，寫長相
    var shapeGood: String {
        guard let wx = wuxing, let type = rules.wuxing.types[wx.host] else { return "這次沒看" }
        return type.good ?? type.plainShape
    }

    /// 對上的好處，一件一列。沒對上的不列，細的在「面相」
    private func makeHighlights() -> [Highlight] {
        var out = fortunes.compactMap { x -> Highlight? in
            guard x.status == .pass, let say = x.palace.say else { return nil }
            return Highlight(topic: x.palace.topic, good: say.good, section: .palaces)
        }
        if goodOfficials != nil {
            out.append(Highlight(topic: "五官", good: rules.wuxing.guanGood, section: .officials))
        }
        if let good = santingGood { out.append(Highlight(topic: "三段", good: good, section: .santing)) }
        for r in others {
            if let good = r.good { out.append(Highlight(topic: "其他古書說法", good: good, section: .others)) }
        }
        return out.filter { !$0.section.locked }
    }
}
