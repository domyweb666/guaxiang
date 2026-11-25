import Foundation

/// 白話旁邊那顆小圓鈕點開的內容：古書原文、怎麼估的、還有什麼量不到。
/// 術語、原文、數字、對照的線都只在這裡出現，報告正面只放白話。
/// 內容全部從 rules.json 和這次的量測組出來，這裡不寫古書沒有的話。
struct BookNote: Equatable {
    struct Quote: Equatable {
        let text: String
        let plain: String
    }

    struct Estimate: Equatable {
        let name: String
        /// 量了哪兩個點之間、除以什麼
        let method: String
        let numbers: [String]
        let warnings: [String]
    }

    let title: String
    var quotes: [Quote] = []
    /// 沒有逐字原文的時候，寫為什麼
    var noQuote: String?
    /// 沒有逐字原文的時候放的白話整理
    var plain: String?
    var source: String?
    /// 古書裡這個部位叫什麼
    var terms: [String] = []
    /// 這個說法有幾本書在講，是不是抄自同一個來源
    var literature: String?
    var estimates: [Estimate] = []
    var remarks: [String] = []
    /// 這一項還有什麼量不到
    var cannot: [String] = []

    static let notTranscribed = "原書文字還沒逐字摘錄，這裡是白話整理。"
    static let provisional = "古書沒有給數字，這條線是本工具暫定的。"

    /// 畫面上會出現的每一段字（測試用：不能有點位編號和章節號）
    var allText: [String] {
        var out = [title]
        for q in quotes { out += [q.text, q.plain] }
        out += [noQuote, plain, source, literature].compactMap { $0 }
        out += terms
        for e in estimates { out += [e.name, e.method] + e.numbers + e.warnings }
        return out + remarks + cannot
    }
}

// MARK: 怎麼估的

extension BookNote {
    /// 數字配單位：1.5%、3.2 度、0.18 倍
    static func text(_ value: Double?, unit: String?) -> String {
        guard let value, value.isFinite else { return "—" }
        switch unit {
        case "%": return String(format: "%.1f%%", value * 100)
        case "度": return String(format: "%.1f 度", value)
        default: return String(format: "%.2f 倍", value)
        }
    }

    /// 交界的寬度。比一般數字多留幾位，不然鼻樑的 0.15% 會被四捨五入掉
    static func edgeText(_ def: FeatureDef) -> String {
        let value = def.edge ?? 0
        let shown: (Double) -> String = { v in
            var s = String(format: "%.4f", v)
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
            return s
        }
        return def.unit == "%" ? shown(value * 100) + "%" : "\(shown(value)) \(def.unit)"
    }

    /// 一個量測是怎麼來的。condition 有給就寫對照的線；outcome 是過了線會寫什麼
    static func estimate(
        _ key: String, condition: Condition? = nil, outcome: String = "就寫「相符」", rules: Rules, report: Report?
    ) -> Estimate? {
        guard let def = rules.features[key] else { return nil }
        var numbers: [String] = []
        var warnings: [String] = []
        if let report {
            if let stat = report.measurement.F[key] {
                let frames = report.measurement.frames
                numbers.append("你的數字：" + text(stat.v, unit: def.unit))
                let spread = text(stat.iqr, unit: def.unit)
                numbers.append("\(frames) 張畫面的數字由小排到大，去掉頭尾各四分之一，剩下的最大和最小差 \(spread)。")
                if stat.unstable { warnings.append("這一項不穩：\(frames) 張畫面之間差很多，只當參考。") }
            } else {
                numbers.append("這次量不到。")
            }
        }
        if let condition, let at = lineValue(condition, rules: rules) {
            numbers.append("對照的線：\(text(at, unit: def.unit))，\(side(condition.op))\(outcome)。")
            numbers.append("離這條線不超過 \(edgeText(def)) 算在交界上，不下結論。")
            numbers.append(provisional + (condition.th.flatMap { rules.thresholds[$0]?.plain } ?? ""))
            if let report, report.measurement.answers.blockedWhy(condition.blockedBy) == nil,
                Judge(rules: rules).test(report.measurement.F, condition).edge
            {
                warnings.append("剛好在交界上，換個光線再掃可能會變。")
            }
        }
        return Estimate(name: def.plainName, method: def.plainFormula, numbers: numbers, warnings: warnings)
    }

    private static func lineValue(_ c: Condition, rules: Rules) -> Double? {
        if let th = c.th { return rules.threshold(th) }
        return c.value
    }

    private static func side(_ op: String?) -> String {
        switch op {
        case ">=": return "到這條線或更多"
        case "<=": return "到這條線或更少"
        case ">": return "超過這條線"
        default: return "不到這條線"
        }
    }

    /// 臉的三段：離平均最遠的那一段，加上三段各自的長度
    private static func santingEstimates(rules: Rules, report: Report?) -> [Estimate] {
        let equal = rules.rules.first { $0.id == "santing-equal" }?.when.conditions.first
        let dev = estimate(
            "santing_dev", condition: equal, outcome: "就寫「差不多長」", rules: rules, report: report)
        let each = ["santing_U", "santing_M", "santing_L"].map { estimate($0, rules: rules, report: report) }
        return ([dev] + each).compactMap { $0 }
    }
}

// MARK: 不用報告也組得出來的（首頁、完整版說明也會用）

extension BookNote {
    static func rule(_ r: Rule, rules: Rules, report: Report?) -> BookNote {
        var note = BookNote(title: r.headline?.components(separatedBy: "：").first ?? "臉的三段")
        if let yuanwen = r.yuanwen, !yuanwen.isEmpty {
            note.quotes = [Quote(text: yuanwen, plain: r.yuanwenPlain ?? r.baihua)]
            if r.yuanwenPlain != nil { note.plain = r.baihua }
        } else {
            note.noQuote = notTranscribed
            note.plain = r.baihua
        }
        note.source = r.source
        note.terms = [r.terms]
        note.literature = r.litPlain
        if r.part == "三停" {
            note.estimates = santingEstimates(rules: rules, report: report)
            note.cannot = ["三段豐不豐滿，要看深度"]
        } else {
            note.estimates = r.when.conditions.compactMap { c -> Estimate? in
                guard let key = c.feature else { return nil }
                return estimate(key, condition: c, outcome: "就對得上這一條", rules: rules, report: report)
            }
        }
        if r.experimental == true { note.remarks.append(Pack.experimentalNote) }
        if let extra = r.note, !extra.isEmpty { note.remarks.append(extra) }
        return note
    }

    static func palace(_ g: Palace, rules: Rules, report: Report?, result: PalaceResult?) -> BookNote {
        var note = BookNote(title: g.topic)
        if let yuanwen = g.yuanwen, !yuanwen.isEmpty {
            note.quotes = [Quote(text: yuanwen, plain: g.baihua ?? "")]
        } else {
            note.noQuote = g.noQuoteWhy ?? notTranscribed
            note.plain = g.baihua
        }
        note.source = g.source
        note.terms = ["古書把這件事叫「\(g.name)」" + (g.modern.map { "，現代叫「\($0)」" } ?? "") + "。"]
        if let term = g.whereTerm { note.terms.append("臉上這個位置，古書叫「\(term)」。") }
        if let terms = g.terms { note.terms.append(terms) }
        note.terms.append(rules.palacesTerms)
        if let m = g.measure {
            if m.type == "santing" {
                note.estimates = santingEstimates(rules: rules, report: report)
            } else if let key = m.feature {
                note.estimates = [estimate(key, condition: m, rules: rules, report: report)].compactMap { $0 }
            }
        }
        if let result, result.status == .unjudged { note.remarks.append("這次沒看：" + result.line) }
        if let extra = g.note { note.remarks.append(extra) }
        if let notMeasured = g.notMeasured { note.cannot.append(notMeasured) }
        return note
    }
}

// MARK: 報告上每一處

extension Report {
    func note(rule r: Rule) -> BookNote {
        BookNote.rule(r, rules: rules, report: self)
    }

    func note(palace x: PalaceResult) -> BookNote {
        BookNote.palace(x.palace, rules: rules, report: self, result: x)
    }

    /// 一官：全部條件一起看
    func note(official x: OfficialResult) -> BookNote {
        var note = officialBase(x, title: x.official.plain)
        note.estimates = x.official.conditions.compactMap { c in
            c.feature.flatMap { BookNote.estimate($0, condition: c, rules: rules, report: self) }
        }
        if x.status == .unjudged { note.remarks.append("這次沒看：" + (x.why ?? "")) }
        if x.status == .pass, !note.cannot.isEmpty {
            note.remarks.append("這裡的「相符」只包含量得到的那幾條。")
        }
        return note
    }

    /// 一官裡的其中一條
    func note(condition c: Condition, of x: OfficialResult) -> BookNote {
        var note = officialBase(x, title: c.plain ?? x.official.plain)
        if let key = c.feature, let e = BookNote.estimate(key, condition: c, rules: rules, report: self) {
            note.estimates = [e]
        }
        return note
    }

    private func officialBase(_ x: OfficialResult, title: String) -> BookNote {
        var note = BookNote(title: title)
        note.noQuote = BookNote.notTranscribed
        note.plain = x.official.baihua
        note.source = x.official.source
        note.terms = [x.official.terms]
        note.literature = x.official.litPlain
        note.cannot = x.official.notMeasured ?? []
        return note
    }

    /// 五官整體：古書怎麼說五官
    var officialsNote: BookNote {
        var note = BookNote(title: "五官")
        note.noQuote = BookNote.notTranscribed
        note.plain = rules.wuxing.guan
        note.terms = [rules.wuxing.guanTerms, "古書把耳、眉、眼、鼻、口叫「五官」。"]
        note.remarks = ["「十年」只是概數。", "沒看的、在交界上的，都不算相符，也不算不同。"]
        return note
    }

    /// 臉的三段。沒拉髮際線的時候，放古書那一句
    var santingNote: BookNote? {
        let r = santingRule ?? rules.rules.first { $0.id == "santing-equal" }
        return r.map { note(rule: $0) }
    }

    /// 三段裡的其中一段。古書講三段的是同一段原文
    func note(segment s: SantingSegment) -> BookNote {
        var note = BookNote(title: s.k)
        if let r = rules.rules.first(where: { $0.id == "santing-long" }) {
            if let yuanwen = r.yuanwen {
                note.quotes = [BookNote.Quote(text: yuanwen, plain: r.yuanwenPlain ?? r.baihua)]
                note.plain = r.baihua
            }
            note.source = r.source
            note.terms = [r.terms]
            note.literature = r.litPlain
        }
        let keys = ["上段": "santing_U", "中段": "santing_M", "下段": "santing_L"]
        if let key = keys[s.k], let e = BookNote.estimate(key, rules: rules, report: self) { note.estimates = [e] }
        note.remarks = [
            "古書的中段從鼻根量到鼻頭。這裡三段接著量，分界在兩眉中間和鼻子底。",
            "短 5% 以上寫「比平均短」，長 5% 以上寫「比平均長」，中間寫「接近平均」。這兩條線是本工具暫定的。"
        ]
        note.cannot = ["這一段豐不豐滿，要看深度"]
        return note
    }

    /// 十二件事整體
    var palacesNote: BookNote {
        var note = BookNote(title: "人生十二件事")
        note.noQuote = "每一件事的原文，在那一件事旁邊的小圓鈕裡。"
        note.plain = rules.palacesNote
        note.source = rules.palaces.compactMap(\.source).first
        note.terms = [rules.palacesTerms]
        note.remarks = ["沒看的、在交界上的，都不算相符，也不算不同。"]
        return note
    }

    /// 臉形
    var wuxingNote: BookNote {
        let W = rules.wuxing
        var note = BookNote(title: "臉形")
        if let wx = wuxing, let type = W.types[wx.host] {
            note.quotes.append(BookNote.Quote(text: type.yuanwen, plain: type.plainLine))
        }
        note.quotes.append(BookNote.Quote(text: W.notFault, plain: W.notFaultPlain))
        note.source = W.source
        note.terms = [W.terms]
        note.estimates = ["face_aspect", "fore_jaw", "jaw_angle", "santing_L"].compactMap {
            BookNote.estimate($0, rules: rules, report: self)
        }
        note.remarks.append("古書只說「金方、木瘦、水圓、火尖、土厚」，沒有給數字。用多少比例算哪一形，是本工具暫定的算法。")
        if let wx = wuxing {
            let scores = wx.scores.map { "\($0.name) " + String(format: "%.2f", $0.score) }.joined(separator: "、")
            note.remarks.append("五種形的分數：\(scores)。分數最高的就是你最接近的那一形。")
        }
        note.remarks.append(W.note)
        note.cannot = ["膚色、骨架和身材，古書分五形時也要看"]
        return note
    }

    /// 主要那一形和帶到的那一形放在一起
    var relationNote: BookNote? {
        guard let rel = wuxing?.relation else { return nil }
        var note = BookNote(title: "兩種形放在一起")
        note.noQuote = BookNote.notTranscribed
        note.plain = rel.lines.joined(separator: "\n")
        note.terms = ["主要的那一形古書叫「主形」，帶到的那一形叫「兼形」。"]
        if let plain = wuxingRelationPlain { note.terms.append("你這一組是\(plain)。") }
        note.remarks = ["哪一形是主要、哪一形是帶到，照臉形的分數排，怎麼算是本工具暫定的。"]
        return note
    }

    func note(cannotSee c: CannotSee) -> BookNote {
        var note = BookNote(title: c.plain)
        if let yuanwen = c.yuanwen {
            note.quotes = [BookNote.Quote(text: yuanwen, plain: c.baihua ?? "")]
        } else {
            note.noQuote = "這一項的原書文字還沒摘錄進規則庫。"
        }
        note.terms = ["古書叫「\(c.name)」。"]
        note.cannot = [c.why]
        return note
    }

    /// 數字明細的一列
    func note(feature key: String) -> BookNote {
        let name = rules.features[key]?.plainName ?? ""
        var note = BookNote(title: name)
        var used: [String] = []
        for o in rules.officials where o.conditions.contains(where: { $0.feature == key }) {
            used.append("五官的\(o.plain)")
        }
        for g in rules.palaces {
            guard let m = g.measure else { continue }
            if m.feature == key || (m.type == "santing" && key.hasPrefix("santing_")) { used.append(g.topic) }
            if m.feature == key, let yuanwen = g.yuanwen {
                note.quotes.append(BookNote.Quote(text: yuanwen, plain: g.baihua ?? ""))
                note.source = g.source
            }
        }
        if ["face_aspect", "fore_jaw", "jaw_angle", "santing_L"].contains(key) { used.append("臉形") }
        if rules.rules.contains(where: { r in r.part != "三停" && r.when.conditions.contains { $0.feature == key } }) {
            used.append("其他古書說法")
        }
        if key.hasPrefix("santing_") { used.append("臉的三段") }
        note.noQuote = note.quotes.isEmpty ? "這是量出來的數字，原文在用到它的那一項旁邊。" : nil
        note.remarks = [used.isEmpty ? "這個數字目前沒有拿來對照古書。" : "用在：" + used.joined(separator: "、") + "。"]
        if let e = BookNote.estimate(key, rules: rules, report: self) { note.estimates = [e] }
        return note
    }
}
