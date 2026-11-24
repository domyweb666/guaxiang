import Foundation

/// 存在手機裡的那一份：只有量出來的數字和掃描前的勾選。照片另外存（Store/FacePhoto.swift），匯出時不帶。
/// 合格不合格每次打開都照 rules.json 重新比一次，所以規則庫更新後舊報告會跟著新規則走。
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
            return def.name
        }
    }

    func count(_ status: Status) -> Int {
        officials.filter { $0.status == status }.count
    }

    /// 五官那一列底下的一句話：沒判寫原因，合格寫符合哪幾條，不合格寫哪幾條不符合
    static func officialLine(_ x: OfficialResult) -> String {
        switch x.status {
        case .unjudged:
            return x.why ?? ""
        case .pass:
            return x.rows.compactMap { $0.condition.yes }.joined(separator: "，")
        case .fail:
            return x.rows.filter { $0.result.pass != true }.compactMap { $0.condition.no }.joined(separator: "，")
        }
    }

    /// 數字怎麼顯示：百分比一位小數、角度一位小數、其他兩位小數
    func format(_ key: String, _ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        switch rules.features[key]?.unit {
        case "%": return String(format: "%.1f%%", value * 100)
        case "度": return String(format: "%.1f°", value)
        default: return String(format: "%.2f", value)
        }
    }
}

/// 「古書怎麼說你」最上面那幾點
struct SummaryPoint: Identifiable {
    let title: String
    let body: String
    var id: String { title + body }
}

extension Report {
    var summaryPoints: [SummaryPoint] {
        var points: [SummaryPoint] = []
        let W = rules.wuxing
        if let wx = wuxing, let type = W.types[wx.host] {
            points.append(
                SummaryPoint(title: "臉形：\(wx.host)形人", body: "\(type.plainShape)。古書說：\(type.plainLine)"))
        } else {
            points.append(SummaryPoint(title: "臉形", body: "量測資料不足，這次沒判。"))
        }

        let names: ([OfficialResult]) -> String = { $0.map(\.official.plain).joined(separator: "、") }
        let ok = officials.filter { $0.status == .pass }
        let bad = officials.filter { $0.status == .fail }
        let na = officials.filter { $0.status == .unjudged }
        var guan = ok.isEmpty ? "沒有一個合古書的標準" : names(ok) + "合古書的標準"
        if !bad.isEmpty { guan += "；" + names(bad) + "不合" }
        if !na.isEmpty { guan += "；" + names(na) + "這次沒判" }
        points.append(SummaryPoint(title: "五官：\(ok.count) 個合格", body: guan + "。" + W.guan))

        points.append(SummaryPoint(title: "臉的三段", body: santingHeadline ?? "這次沒判。"))

        let pOk = palaces.filter { $0.status == .pass }
        let pBad = palaces.filter { $0.status == .fail }
        let pNa = palaces.filter { $0.status == .unjudged }
        var gong = ""
        if !pOk.isEmpty { gong += pOk.map(\.palace.topic).joined(separator: "、") + "合古書的標準" }
        if !pOk.isEmpty, !pBad.isEmpty { gong += "；" }
        if !pBad.isEmpty { gong += pBad.map(\.palace.topic).joined(separator: "、") + "不合" }
        if !pOk.isEmpty || !pBad.isEmpty { gong += "。" }
        gong += "其他 \(pNa.count) 宮這次沒判，每一宮都寫了原因。"
        points.append(SummaryPoint(title: "十二宮：量得到 \(pOk.count + pBad.count) 宮", body: gong))

        for r in others {
            points.append(
                SummaryPoint(title: r.headline ?? r.part, body: r.experimental == true ? "實驗項目，只當參考。" : ""))
        }
        return points
    }

    /// 臉形是怎麼看出來的（照本工具暫定的計分方式描述）
    var wuxingWhy: String? {
        guard let wx = wuxing else { return nil }
        let n2: (Double?) -> String = { v in
            guard let v, v.isFinite else { return "—" }
            return String(format: "%.2f", v)
        }
        let n0: (Double?) -> String = { v in
            guard let v, v.isFinite else { return "—" }
            return String(format: "%.0f", v)
        }
        let A = measurement.F["face_aspect"]?.v, R = measurement.F["fore_jaw"]?.v
        let J = measurement.F["jaw_angle"]?.v
        switch wx.host {
        case "木": return "你的臉長是寬的 \(n2(A)) 倍，比例偏長。"
        case "金": return "額頭和下顎差不多寬（額寬是下顎的 \(n2(R)) 倍），下顎角 \(n0(J))°，偏方。"
        case "火": return "額頭比下顎窄（額寬只有下顎的 \(n2(R)) 倍），上窄下寬。"
        case "水": return "臉長只有寬的 \(n2(A)) 倍，下顎角 \(n0(J))°，偏圓。"
        case "土": return "臉長只有寬的 \(n2(A)) 倍，下巴那一段偏長，看起來厚實。"
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
