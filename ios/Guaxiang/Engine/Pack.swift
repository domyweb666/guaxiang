import Foundation

/// 使用者填的簡介。只存在手機裡；提問時跟著問題一起以文字送出（要先勾同意）。
struct Profile: Codable, Equatable {
    var age: Int?
    var gender = ""
    var relation = ""
    var work = ""
    var intro = ""
}

/// 依據清單的一條。AI 的每一句話都要標它用了哪一條（E1、E2…）
struct Evidence: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let text: String
    let key: String
}

/// 把報告整理成編號的依據清單。逐字照網頁版 index.html 的 buildPack()，
/// 標準答案測試（EngineParityTests）會拿網頁版的輸出逐條比對。
enum Pack {
    /// 實驗項目的附註。網頁版寫的是「網頁版量不準」，iOS 版的深度還沒校準，講法不一樣
    static let webExperimentalNote = "這是實驗項目，網頁版量不準。"
    static let iosExperimentalNote = "這是實驗項目，深度量測還沒校準，只當參考。"

    static func build(_ report: Report, profile: Profile?, experimentalNote: String = iosExperimentalNote)
        -> [Evidence]
    {
        let rules = report.rules
        let W = rules.wuxing
        let F = report.measurement.F
        var pack: [Evidence] = []
        let add: (String, String, String) -> Void = { title, text, key in
            pack.append(Evidence(id: "E\(pack.count + 1)", title: title, text: text, key: key))
        }
        let fixed: (Double?, Int) -> String = { value, digits in
            guard let value, value.isFinite else { return "—" }
            return String(format: "%.\(digits)f", value)
        }

        add(
            "這次沒看到的東西",
            "這份報告只看臉的形狀（比例、長短、角度）。古書還要看的這些，這次都沒看："
                + rules.cannotSee.map { "\($0.plain)（\($0.name)）：\($0.why)" }.joined(separator: "；")
                + "。另外，古書的說法沒有經過科學驗證。",
            "cannot")

        if let wx = report.wuxing, let type = W.types[wx.host] {
            var text = "量測：臉長是寬的 \(fixed(F["face_aspect"]?.v, 2)) 倍，"
            text += "額寬是下顎的 \(fixed(F["fore_jaw"]?.v, 2)) 倍，下顎角 \(fixed(F["jaw_angle"]?.v, 0)) 度。"
            text += "五形裡最接近\(wx.host)形（\(type.plainShape)）"
            if let guest = wx.guest { text += "，也帶一點\(guest)形" }
            if wx.weak { text += "，但特徵不明顯" }
            text += "。用比例算哪一形是本工具暫定的算法；五行形本來要看全身和膚色，這裡只是臉形推估。"
            text += "\n古書：\(type.yuanwen)（白話：\(type.plainLine)）"
            text += "\n\(W.notFaultPlain)"
            if let rel = wx.relation { text += "\n兼形：" + rel.lines.joined(separator: " ") }
            text += "\n出處：\(W.source)"
            add("臉形：\(wx.host)形人", text, "wuxing")
        } else {
            add("臉形：沒判", "量測資料不足，這次沒有判臉形。", "wuxing")
        }

        add("五官怎麼算", W.guan + "「十年」只是概數。沒判的不能當成合格。", "guan")

        for x in report.officials {
            let o = x.official
            let rows = x.rows.map { row -> String in
                let pass = row.result.pass == true
                return (pass ? "符合" : "不符合") + "：" + ((pass ? row.condition.yes : row.condition.no) ?? "")
            }.joined(separator: "；")
            let verdict = x.status == .pass ? "量得到的條件都合格" : x.status.word
            var text = "\(o.governs)。\n這次結果：" + (x.status == .unjudged ? "沒判，" + (x.why ?? "") : rows)
            if let notMeasured = o.notMeasured { text += "\n量不到的：" + notMeasured.joined(separator: "、") }
            text += "\n古書的合格標準：\(o.baihua)\n出處：\(o.source)"
            add("五官・\(o.plain)（\(o.name)）：\(verdict)", text, o.id)
        }

        if let segments = report.segments, let st = report.santingRule {
            let parts = segments.map { "\($0.k)（\($0.part)，管\($0.life)）是平均的 \(fixed($0.v, 2)) 倍" }
            add(
                "臉的三段（三停）：" + (st.id == "santing-equal" ? "差不多長" : "長短不一"),
                parts.joined(separator: "；") + "。\n古書：\(st.yuanwen ?? "")\n白話：\(st.baihua)\n出處：\(st.source)",
                "santing")
        } else {
            add("臉的三段（三停）：沒判", "沒有拉髮際線，量不到臉的上段。", "santing")
        }

        for r in report.others {
            var text = r.baihua
            if let yuanwen = r.yuanwen, !yuanwen.isEmpty { text += "\n古書：" + yuanwen }
            if r.experimental == true { text += "\n" + experimentalNote }
            if let note = r.note, !note.isEmpty { text += "\n" + note }
            text += "\n出處：\(r.source)"
            add(r.headline ?? r.part, text, r.id)
        }

        for x in report.palaces {
            let g = x.palace
            let verdict: String
            switch x.status {
            case .pass: verdict = "量得到的部分合格"
            case .fail: verdict = "量得到的部分不合格"
            case .unjudged: verdict = "沒判"
            }
            var text = "位置：\(g.place)。\n這次結果：\(x.line)"
            if let notMeasured = g.notMeasured, x.status != .unjudged { text += "\n" + notMeasured }
            if let yuanwen = g.yuanwen, !yuanwen.isEmpty { text += "\n古書：\(yuanwen)（白話：\(g.baihua ?? "")）" }
            if let note = g.note, !note.isEmpty { text += "\n" + note }
            if let source = g.source, !source.isEmpty { text += "\n出處：" + source }
            add("十二宮・\(g.topic)（\(g.name)）：\(verdict)", text, "gong-" + g.id)
        }

        if let ln = Judge(rules: rules).liunian(age: profile?.age) {
            let snapshot = pack
            let describe: (LiunianRow?) -> String = { row in
                guard let row else { return "超出〈流年運氣部位歌〉正面路線（76 歲以後在臉的外圈），這次不判" }
                var s = "\(row.name)（\(row.place)）"
                if !row.layer.isEmpty { s += "，屬於" + row.layer }
                if let link = row.link, let hit = snapshot.first(where: { $0.key == link }) {
                    s += "，這個部位的量測結果見［\(hit.id)］"
                } else {
                    s += "，這個部位這次沒有對應的量測"
                }
                return s
            }
            var text = "\(rules.liunian.note)\n今年（虛歲 \(ln.xu)）走到：\(describe(ln.hit))。"
            text += "\n明年（虛歲 \(ln.xu + 1)）走到：\(describe(ln.next))。"
            if let gender = profile?.gender, !gender.isEmpty {
                text += "\n性別：\(gender)，傳統從\(gender == "男" ? "左" : "右")邊起算。"
            }
            text += "\n出處：\(rules.liunian.source)"
            add("今年的流年：虛歲 \(ln.xu) 歲", text, "liunian")
        }
        return pack
    }
}
