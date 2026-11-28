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

    private func check(_ note: BookNote?, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let note else {
            XCTFail("\(what)：組不出來", file: file, line: line)
            return
        }
        XCTAssertTrue(!note.quotes.isEmpty || note.plain != nil, "\(what)：沒有原文也沒有白話", file: file, line: line)
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
            for x in report.shownOfficials { check(report.note(official: x), "\(at)・\(x.official.plain)") }
            for x in report.fortunes { check(report.note(palace: x), "\(at)・\(x.palace.topic)") }
            for r in rules.rules { check(report.note(rule: r), "\(at)・\(r.id)") }
            check(report.officialsNote, "\(at)・五官")
            check(report.santingNote, "\(at)・三段")
            check(report.fortunesNote, "\(at)・運勢")
            if report.wuxing != nil { check(report.wuxingNote, "\(at)・臉形") }
            if report.wuxing?.relation != nil { check(report.relationNote, "\(at)・兩種形") }
        }
    }

    /// 看不到的不放正面：耳朵、沒有說法的那幾件事；但都要找得到寫在「這次沒看的」
    func testUnseenMovedOffTheFront() throws {
        let rules = try loadRules()
        let report = try XCTUnwrap(reports(rules).first)
        XCTAssertEqual(report.shownOfficials.map(\.official.plain), ["眉毛", "眼睛", "鼻子", "嘴巴"])
        XCTAssertEqual(Set(report.fortunes.map(\.palace.topic)), ["錢財", "整體運勢", "兄弟朋友"])
        XCTAssertTrue(rules.cannotSee.contains { $0.plain == "耳朵" })
        XCTAssertEqual(report.unseenTopics.count, 8)
        for g in report.unseenTopics { XCTAssertFalse((g.why ?? "").isEmpty, g.topic) }
    }

    /// 好處只給對上的：不同、在交界上、沒看，都不准出現在總覽
    func testGoodOnlyWhenMatched() throws {
        let rules = try loadRules()
        for report in reports(rules) {
            let goods = report.highlights.map(\.good)
            for x in report.fortunes {
                XCTAssertEqual(goods.contains(x.palace.say?.good ?? ""), x.status == .pass, x.palace.topic)
            }
            XCTAssertEqual(goods.contains(rules.wuxing.guanGood), report.shownOfficials.contains { $0.status == .pass })
            if report.santingOnEdge || report.segments == nil { XCTAssertNil(report.santingGood) }
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
            XCTAssertEqual(note.plain, x.official.baihua)
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
        }
        let t = Tally([.pass, .unjudged, .fail, .edge, .unjudged])
        XCTAssertEqual(t.sentence("項"), "1 項跟古書寫的相符・1 項不同・1 項在交界上・2 項沒看")
    }

    /// 正面的字：沒有考試的詞、章節號、術語
    func testFrontTextIsPlain() throws {
        let rules = try loadRules()
        var texts: [String] = [rules.wuxing.guan, rules.wuxing.guanGood]
        for report in reports(rules) {
            texts += report.highlights.flatMap { [$0.topic, $0.good] }
            texts += report.fortunes.map(\.front)
            texts += report.officials.flatMap { $0.rows.map(\.front) }
            texts += report.officials.compactMap(\.why)
            texts += [report.santingGood, report.santingFront, report.shapeName, report.shapeGood].compactMap { $0 }
            texts += [report.fortunesIntro, report.officialsIntro, report.santingIntro]
            texts += report.officials.compactMap { $0.verdictLine(rules.wuxing.guanGood) }
            texts += report.wuxing?.relation?.plain ?? []
        }
        for o in rules.officials {
            texts += [o.plain, o.governs, o.baihua, o.means].compactMap { $0 } + (o.notMeasured ?? [])
            texts += o.conditions.flatMap { [$0.plain, $0.yes, $0.no, $0.mid, $0.book].compactMap { $0 } }
        }
        for g in rules.palaces {
            texts += [g.topic, g.place, g.baihua, g.why, g.notMeasured].compactMap { $0 }
            if let say = g.say { texts += [say.good, say.pass, say.fail, say.edge] }
        }
        for r in rules.rules { texts += [r.baihua, r.headline, r.note].compactMap { $0 } }
        for c in rules.cannotSee { texts += [c.plain, c.why] }

        let terms = [
            "採聽官", "保壽官", "監察官", "審辨官", "出納官", "三停", "上停", "中停", "下停", "印堂", "五嶽", "中嶽", "地閣",
            "山根", "天倉", "十二宮", "財帛宮", "命宮", "孤峰", "兼形", "相生", "相剋", "形質"
        ]
        texts += rules.wuxing.types.values.flatMap { [$0.plainLine, $0.plainShape, $0.good].compactMap { $0 } }
        for text in texts {
            clean(text, "正面")
            XCTAssertFalse(text.isEmpty)
            for term in terms { XCTAssertFalse(text.contains(term), "正面「\(text)」有術語「\(term)」") }
        }
        XCTAssertEqual([Status.pass, .fail, .edge, .unjudged].map(\.word), ["相符", "不同", "在交界上", "沒看"])
    }

    /// 每一條都講滿三件事：古書說什麼、你怎樣、這句算不算。「這次先不說」不准再出現（多米 11/28）
    func testEveryLineSaysWhatItMeans() throws {
        let rules = try loadRules()
        for g in rules.palaces where g.measure != nil && g.measure?.type == nil {
            let say = try XCTUnwrap(g.say, g.topic)
            for text in [say.pass, say.fail, say.edge] {
                XCTAssertTrue(text.hasPrefix("古書說"), "\(g.topic)：「\(text)」")
                XCTAssertFalse(text.contains("這次先不說"), "\(g.topic)：「\(text)」")
                XCTAssertTrue(text.contains(say.good.components(separatedBy: "，").first ?? say.good), "\(g.topic)：「\(text)」")
            }
            XCTAssertTrue(say.pass.contains("算在你身上"), g.topic)
            XCTAssertTrue(say.fail.contains("不算在你身上"), g.topic)
            XCTAssertTrue(say.edge.contains("只算一半"), g.topic)
        }
        for o in rules.officials {
            XCTAssertFalse((o.means ?? "").isEmpty, "\(o.plain) 沒有 means")
            for c in o.conditions {
                XCTAssertFalse((c.mid ?? "").isEmpty, "\(o.plain)・\(c.plain ?? "")：沒有 mid")
                XCTAssertTrue((c.book ?? "").hasPrefix("古書說"), "\(o.plain)・\(c.plain ?? "")：沒有 book")
            }
        }
        for report in reports(rules) {
            var texts = report.fortunes.map(\.front) + [report.santingFront]
            for x in report.shownOfficials {
                for row in x.rows where row.status != .unjudged {
                    XCTAssertTrue(row.front.hasPrefix(row.condition.book ?? "-"), row.front)
                    texts.append(row.front)
                }
                let verdict = x.verdictLine(rules.wuxing.guanGood)
                XCTAssertEqual(verdict == nil, x.status == .unjudged, x.official.plain)
                if let verdict {
                    XCTAssertTrue(verdict.contains(rules.wuxing.guanGood), verdict)
                    texts.append(verdict)
                }
            }
            for text in texts { XCTAssertFalse(text.contains("這次先不說"), text) }
        }
    }

    /// 「不同」只說這句好處不算，不說成壞事，也不跟別人比
    func testDifferentIsNotBad() throws {
        let rules = try loadRules()
        var texts = rules.palaces.compactMap(\.say?.fail)
        for report in reports(rules) {
            texts += report.shownOfficials.filter { $0.status == .fail }.compactMap { $0.verdictLine(rules.wuxing.guanGood) }
            texts += report.shownOfficials.flatMap { $0.rows.filter { $0.status == .fail }.map(\.front) }
        }
        XCTAssertFalse(texts.isEmpty)
        for text in texts {
            for word in ["不好", "壞", "很差", "辛苦", "大部分人", "一般人", "普通"] {
                XCTAssertFalse(text.contains(word), "「\(text)」有「\(word)」")
            }
        }
    }

    /// 每一區最上面：這一區看什麼、這次量了幾樣，數字跟著資料走
    func testSectionIntrosCountFromData() throws {
        let rules = try loadRules()
        let all = reports(rules)
        XCTAssertTrue(all[0].officialsIntro.hasPrefix("這一區看眉毛、眼睛、鼻子、嘴巴 4 樣，這次量了 4 樣。"))
        XCTAssertTrue(all[0].officialsIntro.hasSuffix(rules.wuxing.guan))
        XCTAssertTrue(all[0].fortunesIntro.contains("錢財、整體運勢、兄弟朋友 3 件，這次量了 3 件"))
        XCTAssertTrue(all[0].santingIntro.hasSuffix("這次量了 3 段。"))
        // 沒拉髮際線
        XCTAssertTrue(all[2].santingIntro.hasSuffix("這次沒量到。"))
        // 勾了紋眉和鼻子動過：眉毛、鼻子沒看；運勢三件都沒看
        XCTAssertTrue(all[3].officialsIntro.contains("這次量了 2 樣"), all[3].officialsIntro)
        XCTAssertTrue(all[3].fortunesIntro.contains("這次量了 0 件"), all[3].fortunesIntro)
        for report in all {
            let seen = report.shownOfficials.filter { $0.status != .unjudged }.count
            XCTAssertTrue(report.officialsIntro.contains("這次量了 \(seen) 樣"), report.officialsIntro)
            let fortunes = report.fortunes.filter { $0.status != .unjudged }.count
            XCTAssertTrue(report.fortunesIntro.contains("這次量了 \(fortunes) 件"), report.fortunesIntro)
            for text in [report.officialsIntro, report.fortunesIntro, report.santingIntro] { clean(text, "區的開頭") }
        }
    }

    func testLiunianLayerInPlainWords() throws {
        let rules = try loadRules()
        let row = try XCTUnwrap(rules.liunian.table.first { $0.name == "凌雲" })
        XCTAssertEqual(row.plainLayer, "兄弟朋友、眉毛")
    }
}
