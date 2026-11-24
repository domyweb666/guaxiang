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

    init(measurement m: Measurement, rules: Rules) {
        let judge = Judge(rules: rules)
        measurement = m
        self.rules = rules
        officials = judge.officials(m.F, answers: m.answers)
        matched = judge.matchRules(m.F, hasHair: m.hasHair)
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
    }

    /// 三停那一段的白話結論
    var santingHeadline: String? {
        guard let segments, let santingRule else { return nil }
        if santingRule.id == "santing-equal" {
            return "臉的上、中、下三段差不多長。古書說這樣一生各段比較平穩。"
        }
        let sorted = segments.enumerated().sorted { a, b in
            a.element.v != b.element.v ? a.element.v > b.element.v : a.offset < b.offset
        }.map(\.element)
        let longest = sorted[0], shortest = sorted[2]
        return "臉的三段裡，\(longest.k)（\(longest.part)）最長，\(shortest.k)最短。"
            + "古書說長的那段人生（\(longest.life)）比較順，短的那段（\(shortest.life)）比較辛苦。"
    }

    /// 30 張畫面之間差很多的項目名稱
    var unstableNames: [String] {
        FeatureEngine.order.compactMap { key in
            guard measurement.F[key]?.unstable == true, let def = rules.features[key] else { return nil }
            return def.plainName
        }
    }

    func count(_ status: Status) -> Int {
        officials.filter { $0.status == status }.count
    }

    var officialTally: Tally { Tally(officials.map(\.status)) }
    var palaceTally: Tally { Tally(palaces.map(\.status)) }
}

/// 「古書怎麼說你」最上面那幾點
struct SummaryPoint: Identifiable {
    let title: String
    let body: String
    /// 旁邊小圓鈕點開的內容
    let note: BookNote?
    var id: String { title + body }
}

extension Report {
    var summaryPoints: [SummaryPoint] {
        var points: [SummaryPoint] = []
        let W = rules.wuxing
        if let wx = wuxing, let type = W.types[wx.host] {
            points.append(
                SummaryPoint(
                    title: "\(wx.host)形・\(type.plainShape)", body: "古書說\(type.plainLine)", note: wuxingNote))
        } else {
            points.append(SummaryPoint(title: "臉形", body: "這次量到的資料不夠，沒看。", note: wuxingNote))
        }

        let organs = officials.map { (name: $0.official.plain, status: $0.status) }
        points.append(
            SummaryPoint(
                title: "五官", body: officialTally.sentence("項") + "。" + Self.grouped(organs) + W.guan,
                note: officialsNote))

        points.append(SummaryPoint(title: "臉的三段", body: santingHeadline ?? "這次沒看。", note: santingNote))

        let topics = palaces.map { (name: $0.palace.topic, status: $0.status) }
        points.append(
            SummaryPoint(
                title: "人生十二件事",
                body: palaceTally.sentence("件") + "。" + Self.grouped(topics, unseen: false) + "沒看的都寫了原因。",
                note: palacesNote))

        for r in others {
            points.append(
                SummaryPoint(
                    title: r.headline ?? r.part, body: r.experimental == true ? "實驗項目，只當參考。" : "",
                    note: note(rule: r)))
        }
        return points
    }

    /// 「相符的是鼻子；不同的是眉毛、嘴巴；沒看的是耳朵。」三種都沒有就是空字串
    private static func grouped(_ items: [(name: String, status: Status)], unseen: Bool = true) -> String {
        var parts: [String] = []
        for status in [Status.pass, .fail, .unjudged] {
            if status == .unjudged, !unseen { continue }
            let names = items.filter { $0.status == status }.map { $0.name }
            if !names.isEmpty { parts.append("\(status.word)的是\(names.joined(separator: "、"))") }
        }
        return parts.isEmpty ? "" : parts.joined(separator: "；") + "。"
    }

    /// 臉形是怎麼看出來的（照本工具暫定的計分方式描述）。數字在小圓鈕裡
    var wuxingWhy: String? {
        switch wuxing?.host {
        case "木": return "你的臉長跟臉寬比起來偏長。"
        case "金": return "你的額頭和下顎差不多寬，下顎偏方。"
        case "火": return "你的額頭比下顎窄，上窄下寬。"
        case "水": return "你的臉長跟臉寬比起來偏短，下顎偏圓。"
        case "土": return "你的臉長跟臉寬比起來偏短，下巴那一段偏長。"
        default: return nil
        }
    }

    var wuxingRelationPlain: String? {
        guard let wx = wuxing, let guest = wx.guest, let rel = wx.relation else { return nil }
        switch rel.kind {
        case "客生主": return "\(guest)生\(wx.host)（五行相生）"
        case "客剋主": return "\(guest)剋\(wx.host)（五行相剋）"
        case "主剋客": return "\(wx.host)剋\(guest)（五行相剋）"
        case "主生客": return "\(wx.host)生\(guest)（五行相生）"
        default: return nil
        }
    }
}
