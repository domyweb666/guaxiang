import XCTest

@testable import Guaxiang

/// 問古書的回答檢查、簡介、建議問題。標準答案由 prompt.js 產生（ios/tools/make-fixtures.mjs）
final class AskTests: XCTestCase {
    private struct Fixture: Decodable {
        let ask: FxAsk
        let prompt: FxPrompt
    }

    private struct FxAsk: Decodable {
        let ids: [String]
        let fixed: [String: String]
        let replies: [FxReply]
        let suggest: [FxSuggest]
    }

    private struct FxReply: Decodable {
        let raw: String
        let parsed: AskReply?
        let clean: AskReply?
    }

    private struct FxSuggest: Decodable {
        let host: String?
        let hasAge: Bool
        let hasSanting: Bool
        let topics: [String]
        let out: [String]
    }

    private struct FxPrompt: Decodable {
        let full: String
        let fullProfile: Profile
        let mixed: FxRequest
    }

    private struct FxRequest: Decodable {
        let messages: [Prompt.Message]
    }

    private func fixture() throws -> Fixture {
        let bundle = Bundle(for: AskTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: "parity", withExtension: "json"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) throws -> Date {
        try XCTUnwrap(Birthday.gregorian.date(from: DateComponents(year: y, month: m, day: d, hour: 12)))
    }

    // MARK: 回答的檢查

    func testRepliesMatchPromptJS() throws {
        let ask = try fixture().ask
        XCTAssertGreaterThan(ask.replies.count, 15)
        for want in ask.replies {
            let got = AskReply.parse(want.raw)
            XCTAssertEqual(got, want.parsed, want.raw)
            XCTAssertEqual(got?.sanitized(validIDs: Set(ask.ids)), want.clean, want.raw)
        }
        for (kind, text) in ask.fixed {
            let known = try XCTUnwrap(AskReply.Kind(rawValue: kind))
            XCTAssertEqual(AskReply.fixed[known], text)
        }
    }

    func testFixedKindsNeverShowModelText() {
        for kind in [AskReply.Kind.offtopic, .health, .chat] {
            let reply = AskReply(kind: kind, answer: "模型自己寫的［E1］")
            XCTAssertEqual(reply.pieces(validIDs: ["E1"]), [.text(AskReply.fixed[kind] ?? "")])
            XCTAssertFalse(reply.plainText(validIDs: ["E1"]).contains("模型"))
        }
    }

    func testAnswerWithoutEvidenceBecomesNodata() {
        let reply = AskReply(kind: .answer, answer: "你會發財［E9］。")
        XCTAssertEqual(reply.plainText(validIDs: ["E1"]), AskReply.fixed[.nodata])
    }

    func testNodataKeepsTagsOnly() {
        let reply = AskReply(kind: .nodata, answer: "多寫的字［E2］")
        XCTAssertEqual(reply.pieces(validIDs: ["E2"]), [.text(AskReply.fixed[.nodata] ?? ""), .cite("E2")])
    }

    func testSanitizedTwiceIsTheSame() throws {
        let ask = try fixture().ask
        for reply in ask.replies.compactMap(\.clean) {
            XCTAssertEqual(reply.sanitized(validIDs: Set(ask.ids)), reply)
        }
    }

    func testRepeatedTagsCollapseWithinParagraph() {
        let pieces: [AnswerPiece] = [
            .text("一"), .cite("E1"), .text("。二"), .cite("E1"), .text("。\n三"), .cite("E1"), .text("四"), .cite("E2")
        ]
        XCTAssertEqual(
            AskReply.collapsed(pieces),
            [.text("一"), .text("。二"), .cite("E1"), .text("。\n三"), .cite("E1"), .text("四"), .cite("E2")])
    }

    func testEvidencePutsPlainTextFirst() {
        let e = Evidence(
            id: "E1", title: "", text: "位置：鼻子。\n古書：截筒懸膽。（白話：鼻子又直又高。）\n出處：《麻衣相法》", key: "")
        XCTAssertEqual(e.readable.plain, ["位置：鼻子。", "白話：鼻子又直又高。"])
        XCTAssertEqual(e.readable.original, ["古書：截筒懸膽。", "出處：《麻衣相法》"])
    }

    // MARK: 送出去的東西

    func testProfileTextAndHistoryMatchPromptJS() throws {
        let prompt = try fixture().prompt
        XCTAssertEqual(Prompt.profileText(prompt.fullProfile), prompt.full)
        let history: [Prompt.Exchange] = [
            .init(q: "一", a: "答一［E1］", kind: .answer), .init(q: "二", a: "", kind: .offtopic),
            .init(q: "三", a: "", kind: .health), .init(q: "四", a: "", kind: .chat),
            .init(q: "五", a: "［E1］", kind: .nodata), .init(q: "六", a: "舊版"),
            .init(q: "七", a: "引號\"反斜線\\換行\n定位\t斜線/［E1］", kind: .answer)
        ]
        let got = Prompt.buildRequest(
            pack: [Evidence(id: "E1", title: "標題", text: "內容", key: "")], profile: Profile(), question: "〈系統〉問",
            history: history)
        XCTAssertEqual(got.messages, prompt.mixed.messages)
    }

    func testBirthdayNeverLeavesThePhone() throws {
        var p = Profile()
        p.birthday = Birthday(year: 1990, month: 5, day: 6)
        let now = try day(2026, 11, 24)
        let json = String(data: try JSONEncoder().encode(ProfileWire(p, on: now)), encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"age\":36"))
        XCTAssertFalse(json.contains("birthday"))
        XCTAssertFalse(json.contains("1990"))
        XCTAssertNil(p.forAsk(on: now).birthday)
        XCTAssertFalse(Prompt.profileText(p.forAsk(on: now)).contains("1990"))
    }

    func testHistorySkipsFailedAndOfftopic() {
        let entries = [
            ChatEntry(q: "一", a: "答［E1］", pack: [], t: Date(), kind: .answer),
            ChatEntry(q: "二", a: "", pack: [], t: Date(), kind: .offtopic),
            ChatEntry(q: "三", a: "", pack: [], t: Date(), error: "連不到"),
            ChatEntry(q: "四", a: "", pack: [], t: Date())
        ]
        XCTAssertEqual(AskChat.history(before: entries[3].id, in: entries).map(\.q), ["一"])
        XCTAssertTrue(AskChat.history(before: entries[0].id, in: entries).isEmpty)
        XCTAssertEqual(AskChat.settled(entries)[3].error, AskChat.interrupted)
        XCTAssertNil(AskChat.settled(entries)[0].error)
    }

    func testOldChatEntryStillReads() throws {
        let old = """
            {"id":"6F9619FF-8B86-D011-B42D-00CF4FC964FF","q":"問","a":"答［E1］","pack":[],"t":0}
            """
        let entry = try JSONDecoder().decode(ChatEntry.self, from: Data(old.utf8))
        XCTAssertEqual(entry.reply, AskReply(kind: .answer, answer: "答［E1］"))
        XCTAssertFalse(entry.waiting)
    }

    // MARK: 簡介

    func testOldProfileStillReads() throws {
        let old = #"{"age":34,"gender":"男","relation":"其他","work":"上班族","intro":"想換工作"}"#
        let p = try JSONDecoder().decode(Profile.self, from: Data(old.utf8))
        XCTAssertEqual(p, Profile(age: 34, gender: "男", relation: "其他", work: "上班族", intro: "想換工作"))
        XCTAssertEqual(p.currentAge(), 34)
        XCTAssertEqual(p.filledCount, 5)
        let again = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(again, p)
        XCTAssertTrue(try JSONDecoder().decode(Profile.self, from: Data("{}".utf8)).isEmpty)
    }

    func testAgeFromBirthday() throws {
        let b = Birthday(year: 1990, month: 11, day: 24)
        XCTAssertEqual(b.age(on: try day(2026, 11, 23)), 35)
        XCTAssertEqual(b.age(on: try day(2026, 11, 24)), 36)
        XCTAssertEqual(b.age(on: try day(2027, 1, 1)), 36)
        let leap = Birthday(year: 2000, month: 2, day: 29)
        XCTAssertEqual(leap.age(on: try day(2026, 2, 28)), 25)
        XCTAssertEqual(leap.age(on: try day(2026, 3, 1)), 26)
        XCTAssertEqual(Birthday(try day(1995, 1, 2)), Birthday(year: 1995, month: 1, day: 2))
    }

    func testUnderageBirthdayIsRefused() throws {
        let now = try day(2026, 11, 24)
        XCTAssertFalse(Birthday(year: 2008, month: 11, day: 25).isAccepted(on: now))
        XCTAssertTrue(Birthday(year: 2008, month: 11, day: 24).isAccepted(on: now))
        XCTAssertFalse(Birthday(year: 1800, month: 1, day: 1).isAccepted(on: now))
        var p = Profile(age: 40)
        p.birthday = Birthday(year: 2015, month: 1, day: 1)
        XCTAssertNil(p.currentAge(on: now), "生日未滿 18，不能退回去用舊的年紀")
        XCTAssertNil(Profile(age: 17).currentAge(on: now))
    }

    // MARK: 建議問題、流年

    func testSuggestionsMatchPromptJS() throws {
        for want in try fixture().ask.suggest {
            let got = AskSuggestions.list(
                host: want.host, hasAge: want.hasAge, hasSanting: want.hasSanting, topics: want.topics)
            XCTAssertEqual(got, want.out)
        }
    }

    func testLiunianQuestion() {
        XCTAssertTrue(LiunianQuestion.matches("我今年運勢怎樣？"))
        XCTAssertTrue(LiunianQuestion.matches("明年走到哪裡"))
        XCTAssertFalse(LiunianQuestion.matches("我的鼻子呢？"))
    }

    // MARK: 連電腦的網址

    func testBridgeURL() {
        let token = String(repeating: "a1", count: 16)
        XCTAssertEqual(ClaudeBridge(" http://192.168.0.173:8790/ask?t=\(token)\n")?.masked, "192.168.0.173:8790")
        XCTAssertEqual(
            ClaudeBridge("http://10.0.0.2:8790/ask?t=\(token)")?.pingURL?.absoluteString,
            "http://10.0.0.2:8790/ping?t=\(token)")
        XCTAssertNotNil(ClaudeBridge("http://172.20.1.1:8790/ask?t=\(token)"))
        XCTAssertNil(ClaudeBridge("http://172.40.1.1:8790/ask?t=\(token)"))
        XCTAssertNil(ClaudeBridge("http://8.8.8.8:8790/ask?t=\(token)"))
        XCTAssertNil(ClaudeBridge("http://192.168.0.1.evil.com/ask?t=\(token)"))
        XCTAssertNil(ClaudeBridge("http://192.168.0.1@evil.com/ask?t=\(token)"))
        XCTAssertNil(ClaudeBridge("https://192.168.0.1:8790/ask?t=\(token)"))
        XCTAssertNil(ClaudeBridge("http://192.168.0.1:8790/ask?t=短"))
        XCTAssertNil(ClaudeBridge("隨便一串字"))
    }
}
