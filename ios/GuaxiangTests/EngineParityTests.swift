import XCTest

@testable import Guaxiang

/// 標準答案測試：同一批假臉，Swift 版判讀引擎算出來的每一項，都要跟網頁版 index.html 的 JS 一樣。
/// 標準答案由 ios/tools/make-fixtures.mjs 產生（GuaxiangTests/Fixtures/parity.json）。
final class EngineParityTests: XCTestCase {
    struct Fixture: Decodable {
        let rulesVersion: String
        let profile: FxProfile
        let cases: [FxCase]
        let liunian: [FxLiunian]
        let prompt: FxPrompt
    }

    struct FxProfile: Decodable {
        let age: Int
        let gender: String
        let relation: String
        let work: String
        let intro: String
        var profile: Profile { Profile(age: age, gender: gender, relation: relation, work: work, intro: intro) }
    }

    struct FxCase: Decodable {
        let name: String
        let input: FxInput
        let perFrame: [[String: Double]]
        let expected: FxExpected
    }

    struct FxInput: Decodable {
        let frames: [[String: [Double]]]
        let best: [String: [Double]]
        let hairPoint: [Double]?
        let answers: Answers
    }

    struct FxExpected: Decodable {
        let hairRatio: Double?
        let F: [String: FeatureStat]
        let officials: [FxOfficial]
        let rules: [String]
        let wx: FxWuxing
        let palaces: [FxPalace]
        let seg: [FxSegment]?
        let stRule: String?
        let others: [String]
        let pack: [Evidence]
        let packNoProfile: [Evidence]?
        let request: FxRequest?
    }

    struct FxOfficial: Decodable {
        let id: String
        let status: String
        let why: String?
        let rows: [FxRow]
    }

    struct FxRow: Decodable {
        let feature: String
        let pass: Bool?
        let x: Double?
        let t: Double?
        let edge: Bool
        let unstable: Bool
    }

    struct FxWuxing: Decodable {
        struct Score: Decodable {
            let k: String
            let v: Double
        }

        let scores: [Score]
        let host: String
        let guest: String?
        let weak: Bool
        let relKind: String?
        let relLines: [String]
    }

    struct FxPalace: Decodable {
        let id: String
        let status: String
        let line: String
        let edge: Bool
        let unstable: Bool
    }

    struct FxSegment: Decodable {
        let k: String
        let part: String
        let life: String
        let v: Double
    }

    struct FxRequest: Decodable {
        let system: String
        let messages: [Prompt.Message]
    }

    struct FxLiunian: Decodable {
        let age: Int
        let xu: Int
        let hit: String?
        let next: String?
    }

    struct FxPrompt: Decodable {
        let noHistory: FxRequest
        let longPack: FxRequest
    }

    private func resource(_ name: String) throws -> Data {
        let bundle = Bundle(for: EngineParityTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json"), "測試資源裡找不到 \(name).json")
        return try Data(contentsOf: url)
    }

    private func loadRules() throws -> Rules {
        try Rules.decode(resource("rules"))
    }

    private func loadFixture() throws -> Fixture {
        try JSONDecoder().decode(Fixture.self, from: resource("parity"))
    }

    private func frame(_ raw: [String: [Double]]) throws -> FaceFrame {
        var out: FaceFrame = [:]
        for (name, v) in raw {
            let key = try XCTUnwrap(LM(rawValue: name), "不認得的點位名稱 \(name)")
            out[key] = Pt(x: v[0], y: v[1], z: v[2])
        }
        return out
    }

    private func close(_ a: Double?, _ b: Double?, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let a, let b else {
            XCTAssertEqual(a == nil, b == nil, what, file: file, line: line)
            return
        }
        XCTAssertEqual(a, b, accuracy: max(1e-9, abs(b) * 1e-9), what, file: file, line: line)
    }

    func testRulesVersionMatchesFixture() throws {
        let rules = try loadRules()
        let fixture = try loadFixture()
        XCTAssertEqual(
            rules.version, fixture.rulesVersion, "rules.json 改過了，請重跑 node ios/tools/make-fixtures.mjs")
        XCTAssertEqual(rules.officials.count, 5)
        XCTAssertEqual(rules.palaces.count, 12)
    }

    func testEveryCaseMatchesWebVersion() throws {
        let rules = try loadRules()
        let fixture = try loadFixture()
        XCTAssertGreaterThan(fixture.cases.count, 10)

        for c in fixture.cases {
            let frames = try c.input.frames.map(frame)
            let best = try frame(c.input.best)

            // 髮際線
            var hairRatio: Double?
            if let hp = c.input.hairPoint {
                hairRatio = FeatureEngine.hairRatio(best: best, hairPoint: Pt(x: hp[0], y: hp[1]))
            }
            close(hairRatio, c.expected.hairRatio, "\(c.name)：髮際線比例")

            // 每一張畫面的特徵
            let perFrame = frames.map { FeatureEngine.features($0, hairRatio: hairRatio, eps: 1) }
            for (i, got) in perFrame.enumerated() {
                let want = c.perFrame[i]
                XCTAssertEqual(Set(got.keys), Set(want.keys), "\(c.name)：第 \(i) 張的特徵項目")
                for (k, v) in want { close(got[k], v, "\(c.name)：第 \(i) 張 \(k)") }
            }

            // 中位數、波動、穩不穩
            let F = Stats.summarize(perFrame, rules: rules)
            XCTAssertEqual(Set(F.keys), Set(c.expected.F.keys), "\(c.name)：量測項目")
            for (k, want) in c.expected.F {
                close(F[k]?.v, want.v, "\(c.name)：\(k) 中位數")
                close(F[k]?.iqr, want.iqr, "\(c.name)：\(k) 四分位距")
                XCTAssertEqual(F[k]?.unstable, want.unstable, "\(c.name)：\(k) 穩不穩")
            }

            let measurement = Measurement(
                when: Date(timeIntervalSince1970: 0), frames: frames.count, light: 140, hasHair: hairRatio != nil,
                answers: c.input.answers, F: F, rulesVersion: rules.version)
            let report = Report(measurement: measurement, rules: rules)

            // 五官
            XCTAssertEqual(report.officials.count, c.expected.officials.count)
            for (got, want) in zip(report.officials, c.expected.officials) {
                XCTAssertEqual(got.official.id, want.id)
                XCTAssertEqual(got.status.rawValue, want.status, "\(c.name)：\(want.id) 結論")
                XCTAssertEqual(got.why, want.why, "\(c.name)：\(want.id) 沒判的原因")
                XCTAssertEqual(got.rows.count, want.rows.count, "\(c.name)：\(want.id) 條件數")
                for (row, wantRow) in zip(got.rows, want.rows) {
                    XCTAssertEqual(row.condition.feature, wantRow.feature)
                    XCTAssertEqual(row.result.pass, wantRow.pass, "\(c.name)：\(want.id) \(wantRow.feature)")
                    XCTAssertEqual(row.result.edge, wantRow.edge, "\(c.name)：\(wantRow.feature) 邊緣")
                    XCTAssertEqual(row.result.unstable, wantRow.unstable, "\(c.name)：\(wantRow.feature) 不穩")
                    close(row.result.x, wantRow.x, "\(c.name)：\(wantRow.feature) 數值")
                    close(row.result.t, wantRow.t, "\(c.name)：\(wantRow.feature) 門檻")
                }
            }

            // 符合的古書條文、三停
            XCTAssertEqual(report.matched.map(\.id), c.expected.rules, "\(c.name)：符合的條文")
            XCTAssertEqual(report.santingRule?.id, c.expected.stRule, "\(c.name)：三停")
            XCTAssertEqual(report.others.map(\.id), c.expected.others, "\(c.name)：其他條文")
            XCTAssertEqual(report.segments?.count, c.expected.seg?.count, "\(c.name)：三段")
            if let got = report.segments, let want = c.expected.seg {
                for (a, b) in zip(got, want) {
                    XCTAssertEqual(a.k, b.k)
                    XCTAssertEqual(a.part, b.part)
                    XCTAssertEqual(a.life, b.life)
                    close(a.v, b.v, "\(c.name)：\(b.k)")
                }
            }

            // 五行形
            let wx = try XCTUnwrap(report.wuxing, "\(c.name)：五行形應該判得出來")
            XCTAssertEqual(wx.scores.map(\.name), c.expected.wx.scores.map(\.k))
            for (a, b) in zip(wx.scores, c.expected.wx.scores) { close(a.score, b.v, "\(c.name)：\(b.k)形分數") }
            XCTAssertEqual(wx.host, c.expected.wx.host, "\(c.name)：主形")
            XCTAssertEqual(wx.guest, c.expected.wx.guest, "\(c.name)：兼形")
            XCTAssertEqual(wx.weak, c.expected.wx.weak, "\(c.name)：特徵不明顯")
            XCTAssertEqual(wx.relation?.kind, c.expected.wx.relKind, "\(c.name)：主兼關係")
            XCTAssertEqual(wx.relation?.lines ?? [], c.expected.wx.relLines, "\(c.name)：主兼說法")

            // 十二宮
            XCTAssertEqual(report.palaces.count, c.expected.palaces.count)
            for (got, want) in zip(report.palaces, c.expected.palaces) {
                XCTAssertEqual(got.palace.id, want.id)
                XCTAssertEqual(got.status.rawValue, want.status, "\(c.name)：\(want.id) 宮")
                XCTAssertEqual(got.line, want.line, "\(c.name)：\(want.id) 宮的說明")
                XCTAssertEqual(got.edge, want.edge, "\(c.name)：\(want.id) 宮邊緣")
                XCTAssertEqual(got.unstable, want.unstable, "\(c.name)：\(want.id) 宮不穩")
            }

            // 問古書的依據清單，逐字比
            let pack = Pack.build(report, profile: fixture.profile.profile, experimentalNote: Pack.webExperimentalNote)
            XCTAssertEqual(pack.count, c.expected.pack.count, "\(c.name)：依據條數")
            for (got, want) in zip(pack, c.expected.pack) {
                XCTAssertEqual(got.id, want.id)
                XCTAssertEqual(got.key, want.key, "\(c.name)：\(want.id)")
                XCTAssertEqual(got.title, want.title, "\(c.name)：\(want.id) 標題")
                XCTAssertEqual(got.text, want.text, "\(c.name)：\(want.id) 內容")
            }
            if let want = c.expected.packNoProfile {
                let got = Pack.build(report, profile: nil, experimentalNote: Pack.webExperimentalNote)
                XCTAssertEqual(got, want, "\(c.name)：沒填簡介的依據清單")
            }
            if let want = c.expected.request {
                let history = [Prompt.Exchange(q: "我的五官哪裡最好？", a: "古書說五官管地位和名聲［E3］。")]
                let got = Prompt.buildRequest(
                    pack: pack, profile: fixture.profile.profile, question: "我今年運勢怎樣？", history: history)
                XCTAssertEqual(got.system, want.system, "\(c.name)：提示詞")
                XCTAssertEqual(got.messages, want.messages, "\(c.name)：送出的訊息")
            }
        }
    }

    func testLiunianMatchesWebVersion() throws {
        let rules = try loadRules()
        let fixture = try loadFixture()
        let judge = Judge(rules: rules)
        for want in fixture.liunian {
            let got = try XCTUnwrap(judge.liunian(age: want.age))
            XCTAssertEqual(got.xu, want.xu)
            XCTAssertEqual(got.hit?.name, want.hit, "\(want.age) 歲今年")
            XCTAssertEqual(got.next?.name, want.next, "\(want.age) 歲明年")
        }
        XCTAssertNil(judge.liunian(age: nil))
    }

    func testPromptLimitsMatchWebVersion() throws {
        let fixture = try loadFixture()

        let short = Prompt.buildRequest(
            pack: [Evidence(id: "E1", title: "標題", text: "內容", key: "")], profile: Profile(),
            question: String(repeating: "問", count: 400), history: [])
        XCTAssertEqual(short.system, fixture.prompt.noHistory.system)
        XCTAssertEqual(short.messages, fixture.prompt.noHistory.messages)

        let pack = (0..<40).map {
            Evidence(
                id: "E\($0 + 1)", title: "標題" + String(repeating: "長", count: 80),
                text: String(repeating: "字", count: 1500), key: "")
        }
        let history = (0..<8).map { Prompt.Exchange(q: "問\($0)", a: String(repeating: "答", count: 1600)) }
        let long = Prompt.buildRequest(
            pack: pack, profile: Profile(age: 40, intro: String(repeating: "介", count: 500)), question: "問題",
            history: history)
        XCTAssertEqual(long.messages, fixture.prompt.longPack.messages)
    }
}
