import Foundation

/// 標題旁那顆小圓鈕點開的內容：古書原文、白話、出處。
/// 怎麼量、怎麼算、對照哪一條線都不寫（QC-0009，多米 2026-11-26）。
/// 內容全部從 rules.json 組出來，這裡不寫古書沒有的話。
struct BookNote: Equatable {
    struct Quote: Equatable {
        let text: String
        let plain: String
    }

    let title: String
    var quotes: [Quote] = []
    /// 沒有逐字原文的時候放的白話整理
    var plain: String?
    var source: String?

    /// 畫面上會出現的每一段字（測試用：不能有點位編號、章節號和算法）
    var allText: [String] {
        var out = [title]
        for q in quotes { out += [q.text, q.plain] }
        return out + [plain, source].compactMap { $0 }
    }

    /// 有逐字原文就放原文，沒有才放白話整理
    private static func make(_ title: String, yuanwen: String?, plain: String?, source: String?) -> BookNote {
        var note = BookNote(title: title, source: source)
        if let yuanwen, !yuanwen.isEmpty {
            note.quotes = [Quote(text: yuanwen, plain: plain ?? "")]
        } else {
            note.plain = plain
        }
        return note
    }

    static func rule(_ r: Rule) -> BookNote {
        let title = r.headline?.components(separatedBy: "：").first ?? "臉的三段"
        return make(title, yuanwen: r.yuanwen, plain: r.yuanwenPlain ?? r.baihua, source: r.source)
    }

    static func palace(_ g: Palace) -> BookNote {
        make(g.topic, yuanwen: g.yuanwen, plain: g.baihua, source: g.source)
    }
}

extension Report {
    func note(rule r: Rule) -> BookNote { BookNote.rule(r) }

    func note(palace x: PalaceResult) -> BookNote { BookNote.palace(x.palace) }

    func note(official x: OfficialResult) -> BookNote {
        BookNote(title: x.official.plain, plain: x.official.baihua, source: x.official.source)
    }

    /// 五官整體：古書怎麼說五官
    var officialsNote: BookNote { BookNote(title: "五官", plain: rules.wuxing.guan) }

    /// 運勢整體：古書怎麼把人生的事放到臉上。只取 palacesNote 第一句，後面講相機量不量得到的不放（QC-0009）
    var fortunesNote: BookNote {
        let first = rules.palacesNote.components(separatedBy: "。").first ?? rules.palacesNote
        return BookNote(title: "運勢", plain: first + "。", source: rules.palaces.first?.source)
    }

    /// 臉的三段。沒拉髮際線的時候，放古書那一句
    var santingNote: BookNote? {
        (santingRule ?? rules.rules.first { $0.id == "santing-equal" }).map { BookNote.rule($0) }
    }

    /// 臉形
    var wuxingNote: BookNote? {
        guard let wx = wuxing, let type = rules.wuxing.types[wx.host] else { return nil }
        return BookNote(
            title: "\(wx.host)形人", quotes: [BookNote.Quote(text: type.yuanwen, plain: type.plainLine)],
            source: rules.wuxing.source)
    }

    /// 主要那一形和帶到的那一形放在一起
    var relationNote: BookNote? {
        wuxing?.relation.map { BookNote(title: "兩種形放在一起", plain: $0.lines.joined(separator: "\n")) }
    }
}
