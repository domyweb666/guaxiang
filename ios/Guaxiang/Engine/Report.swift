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
    /// 確認標註頁手動調過哪些點（LM 的名字，例如 browTailR）。沒調就是 nil；
    /// 2026-11-28 以前存的檔案沒有這一欄，讀進來也是 nil（選填欄位，讀舊檔不會失敗）
    var adjusted: [String]? = nil

    /// 手動調了幾個點
    var adjustedCount: Int { adjusted?.count ?? 0 }
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
    /// 這一條正面寫的那一句：古書要什麼樣子、你的長相、這一條算不算
    var front: String {
        if status == .unjudged { return "\(condition.plain ?? "")：這次沒看" }
        let look: String
        switch status {
        case .pass: look = condition.yes ?? ""
        case .fail: look = condition.no ?? ""
        default: look = condition.mid ?? ""
        }
        guard let book = condition.book else { return look }
        switch status {
        case .pass: return "\(book)。你的\(look)，這一條對上了。"
        case .fail: return "\(book)。你的\(look)，這一條沒對上。"
        default: return "\(book)。你的\(look)，剛好在古書那條線上，這一條只算一半。"
        }
    }
}

extension OfficialResult {
    /// 官卡最下面那一句：五官那句好處，這一官算不算。沒看的不寫
    func verdictLine(_ guanGood: String) -> String? {
        let name = official.plain
        switch status {
        case .pass: return "所以\(guanGood)這句好處，\(name)算一份。"
        case .fail: return "所以\(guanGood)這句好處，\(name)不算在內。"
        case .edge: return "所以\(guanGood)這句好處，\(name)只算半份。"
        case .unjudged: return nil
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

    /// 三段正面那一句：古書說什麼樣的人有什麼好處、你的三段怎樣、這句算不算。
    /// 古書的話照 rules.json 三段兩條的 baihua 和 yuanwenPlain，不另外加
    var santingFront: String {
        guard segments != nil else { return "沒有拉髮際線，三段這次沒看。" }
        guard let santingRule else { return "三段這次量到的資料不夠，沒看。" }
        let equalGood = "古書說，臉的上、中、下三段差不多長的人，一生都比較平穩。"
        if santingOnEdge {
            return equalGood + "你的三段剛好在「差不多長」那條線上，這句好處對你只算一半。"
        }
        if santingRule.id == "santing-equal" { return equalGood + "你的三段差不多長，這句好處算在你身上。" }
        guard let s = longestSegment else { return "古書說，臉上哪一段長、又飽滿，那一段的人生比較順。" }
        return "古書說，臉上哪一段長、又飽滿，那一段的人生比較順。你的\(s.k)最長，\(s.k)管\(s.lifeWord)，"
            + "所以這句說的是你\(s.lifeWord)最順。"
    }

    // MARK: 每一區最上面那一句：這一區看什麼、這次量了幾樣。數字從資料算

    /// 「運勢」最上面那一句
    var fortunesIntro: String {
        let names = fortunes.map(\.palace.topic).joined(separator: "、")
        let seen = fortunes.filter { $0.status != .unjudged }.count
        return "古書把人生分成十二件事，各看臉上一個地方。這一區看其中\(names) \(fortunes.count) 件，"
            + "這次量了 \(seen) 件；其他幾件放在「\(ReportSection.cannotSee.title)」。"
    }

    /// 「五官」最上面那一句，後面接古書說五官的好處（rules.wuxing.guan）
    var officialsIntro: String {
        let names = shownOfficials.map(\.official.plain).joined(separator: "、")
        let seen = shownOfficials.filter { $0.status != .unjudged }.count
        return "這一區看\(names) \(shownOfficials.count) 樣，這次量了 \(seen) 樣。\(rules.wuxing.guan)"
    }

    /// 「三段」最上面那一句
    var santingIntro: String {
        let head = "這一區看臉的上、中、下三段長短，三段分別管年輕時、中年、老年。"
        guard let segments else { return head + "這次沒量到。" }
        return head + "這次量了 \(segments.count) 段。"
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
