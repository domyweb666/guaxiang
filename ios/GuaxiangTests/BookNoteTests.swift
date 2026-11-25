import XCTest

@testable import Guaxiang

/// 小圓鈕點開的原文和估算方式：每一處都組得出來，而且不露出點位編號和章節號。
/// 正面的字：不用考試的詞，三種數量加起來等於總數。
final class BookNoteTests: XCTestCase {
    private func loadRules() throws -> Rules {
        let bundle = Bundle(for: BookNoteTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: "rules", withExtension: "json"))
        return try Rules.decode(Data(contentsOf: url))
    }

    /// 範例數字、缺眉毛的、沒拉髮際線的、勾了不看的、帶到第二種形的
    private func reports(_ rules: Rules) -> [Report] {
        let base = Sample.measurement(rulesVersion: rules.version)
        var noBrow = base
        noBrow.F["brow_eye"] = nil
        noBrow.F["brow_tail"] = nil
        noBrow.F["nose_dev"]?.unstable = true
        var noHair = base
        noHair.hasHair = false
        for key in ["santing_U", "santing_M", "santing_L", "santing_dev"] { noHair.F[key] = nil }
        var blocked = base
        blocked.answers.browTattoo = true
        blocked.answers.noseSurgery = true
        var long = base
        long.F["santing_dev"]?.v = 0.2
        long.F["face_aspect"]?.v = 1.1
        long.F["santing_L"]?.v = 1.2
        long.F["jaw_angle"]?.v = 140
        long.F["mouth_ipd"]?.v = 1.1
        long.F["mouth_corner"]?.v = 0.05
        long.F["nose_prom"]?.v = 0.4
        long.F["cheek_prom"]?.v = 0.05
        var empty = base
        empty.F = [:]
        // 每一條都剛好壓在線上
        var edge = base
        edge.F["santing_dev"]?.v = 0.1
        edge.F["brow_eye"]?.v = 0.1
        edge.F["eye_lw"]?.v = 3.2
        edge.F["nose_dev"]?.v = 0.015
        edge.F["yintang"]?.v = 1.1
        edge.F["mouth_ipd"]?.v = 0.95
        return [base, noBrow, noHair, blocked, long, empty, edge].map { Report(measurement: $0, rules: rules) }
    }

    private func check(_ note: BookNote?, _ what: String, estimates: Bool, file: StaticString = #filePath, line: UInt = #line) {
        guard let note else {
            XCTFail("\(what)：組不出來", file: file, line: line)
            return
        }
        XCTAssertFalse(note.title.isEmpty, "\(what)：標題", file: file, line: line)
        XCTAssertTrue(!note.quotes.isEmpty || note.noQuote != nil, "\(what)：沒有原文也沒寫為什麼", file: file, line: line)
        for q in note.quotes {
            XCTAssertFalse(q.text.isEmpty || q.plain.isEmpty, "\(what)：原文或白話是空的", file: file, line: line)
        }
        if estimates { XCTAssertFalse(note.estimates.isEmpty, "\(what)：沒寫怎麼估的", file: file, line: line) }
        for text in note.allText {
            XCTAssertFalse(text.trimmingCharacters(in: .whitespaces).isEmpty, "\(what)：有空白的字", file: file, line: line)
            clean(text, what, file: file, line: line)
        }
    }

    /// 點位編號「(33/263)」「(眉心9)」、章節號「2-5」、網頁版、考試的詞都不能出現
    private func clean(_ text: String, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        for pattern in ["[0-9]+-[0-9]+", "[(（][^()（）]*[0-9]+[/↔][0-9]+[^()（）]*[)）]", "[(（][0-9, ]+[)）]", "第[一二三四五]部"] {
            XCTAssertNil(text.range(of: pattern, options: .regularExpression), "\(what)：「\(text)」", file: file, line: line)
        }
        for word in ["網頁版", "合格", "沒判", "符合", "標準線", "門檻", "破格", "🟢", "⚪"] {
            XCTAssertFalse(text.contains(word), "\(what)：「\(text)」有「\(word)」", file: file, line: line)
        }
    }

    func testEveryPlaceHasNote() throws {
        let rules = try loadRules()
        for (i, report) in reports(rules).enumerated() {
            let at = "第 \(i) 份"
            for x in report.officials {
                let name = "\(at)・\(x.official.plain)"
                check(report.note(official: x), name, estimates: !x.official.conditions.isEmpty)
                for c in x.official.conditions {
                    XCTAssertNotNil(c.plain, "\(name)：條件沒有白話")
                    check(report.note(condition: c, of: x), "\(name)・\(c.plain ?? "")", estimates: true)
                }
            }
            for x in report.palaces {
                check(report.note(palace: x), "\(at)・\(x.palace.topic)", estimates: x.palace.measure != nil)
            }
            for s in report.segments ?? [] { check(report.note(segment: s), "\(at)・\(s.k)", estimates: true) }
            for r in rules.rules { check(report.note(rule: r), "\(at)・\(r.id)", estimates: true) }
            for c in rules.cannotSee { check(report.note(cannotSee: c), "\(at)・\(c.plain)", estimates: false) }
            for key in FeatureEngine.order { check(report.note(feature: key), "\(at)・\(key)", estimates: true) }
            check(report.officialsNote, "\(at)・五官", estimates: false)
            check(report.palacesNote, "\(at)・十二件事", estimates: false)
            check(report.santingNote, "\(at)・三段", estimates: true)
            check(report.wuxingNote, "\(at)・臉形", estimates: true)
            if report.wuxing?.relation != nil { check(report.relationNote, "\(at)・兩種形", estimates: false) }
            for p in report.summaryPoints { check(p.note, "\(at)・摘要 \(p.title)", estimates: false) }
        }
    }

    /// 首頁和完整版說明用的，沒有報告也要組得出來
    func testNotesWithoutReport() throws {
        let rules = try loadRules()
        for r in rules.rules { check(BookNote.rule(r, rules: rules, report: nil), r.id, estimates: true) }
        for g in rules.palaces {
            check(BookNote.palace(g, rules: rules, report: nil, result: nil), g.topic, estimates: g.measure != nil)
        }
    }

    /// 古書原文一字不動地拿出來；沒有原文的不准自己補
    func testQuotesComeFromRules() throws {
        let rules = try loadRules()
        let report = try XCTUnwrap(reports(rules).first)
        for x in report.palaces {
            XCTAssertEqual(report.note(palace: x).quotes.map(\.text), [x.palace.yuanwen].compactMap { $0 })
        }
        for x in report.officials {
            let note = report.note(official: x)
            XCTAssertTrue(note.quotes.isEmpty)
            XCTAssertEqual(note.noQuote, BookNote.notTranscribed)
        }
    }

    /// 四種數量都寫出來，加起來等於總數；在交界上、沒看的不混進另外兩種
    func testTalliesAddUp() throws {
        let rules = try loadRules()
        for report in reports(rules) {
            for (tally, total) in [(report.officialTally, 5), (report.palaceTally, 12)] {
                XCTAssertEqual(tally.same + tally.different + tally.onEdge + tally.unseen, total)
                XCTAssertEqual(tally.total, total)
                for n in [tally.same, tally.different, tally.onEdge, tally.unseen] {
                    XCTAssertTrue(tally.sentence("項").contains("\(n) 項"))
                }
            }
            XCTAssertEqual(report.officialTally.unseen, report.count(.unjudged))
        }
        let t = Tally([.pass, .unjudged, .fail, .edge, .unjudged])
        XCTAssertEqual(t.sentence("項"), "1 項跟古書寫的相符・1 項不同・1 項在交界上・2 項沒看")
        XCTAssertEqual(VerdictShort.rest(t, "項"), ["1 項不同", "1 項在交界上", "2 項沒看"])
        XCTAssertEqual(VerdictShort.rest(Tally([.pass, .fail]), "項"), ["1 項不同", "0 項沒看"])
    }

    /// 正面的字：沒有考試的詞、章節號、術語
    func testFrontTextIsPlain() throws {
        let rules = try loadRules()
        var texts: [String] = [rules.palacesNote, rules.wuxing.guan, rules.wuxing.notFaultPlain]
        for report in reports(rules) {
            texts += report.summaryPoints.flatMap { [$0.title, $0.body] }
            texts += report.palaces.map(\.line)
            texts += report.officials.compactMap(\.why)
            texts += [report.santingHeadline, report.wuxingWhy, report.santingShort, report.santingLife].compactMap { $0 }
            texts += report.wuxing?.relation?.plain ?? []
            texts += report.unstableNames
        }
        for o in rules.officials {
            texts += [o.plain, o.governs, o.baihua] + (o.notMeasured ?? [])
            texts += o.conditions.flatMap { [$0.plain, $0.yes, $0.no].compactMap { $0 } }
        }
        for g in rules.palaces { texts += [g.topic, g.place, g.baihua, g.why, g.notMeasured].compactMap { $0 } }
        for r in rules.rules { texts += [r.baihua, r.headline, r.note].compactMap { $0 } }
        for c in rules.cannotSee { texts += [c.plain, c.why] }
        for def in rules.features.values { texts += [def.plainName, def.plainFormula] }

        let terms = [
            "採聽官", "保壽官", "監察官", "審辨官", "出納官", "三停", "上停", "中停", "下停", "印堂", "五嶽", "中嶽", "地閣",
            "山根", "天倉", "十二宮", "財帛宮", "命宮", "孤峰", "兼形", "相生", "相剋", "形質"
        ]
        for text in texts {
            clean(text, "正面")
            for term in terms { XCTAssertFalse(text.contains(term), "正面「\(text)」有術語「\(term)」") }
        }
        XCTAssertEqual([Status.pass, .fail, .edge, .unjudged].map(\.word), ["相符", "不同", "在交界上", "沒看"])
    }

    func testLiunianLayerInPlainWords() throws {
        let rules = try loadRules()
        let row = try XCTUnwrap(rules.liunian.table.first { $0.name == "凌雲" })
        XCTAssertEqual(row.plainLayer, "兄弟朋友、眉毛")
    }
}
