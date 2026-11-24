import Foundation

/// 問古書的回答檢查。跟 prompt.js 的 parseReply、sanitizeReply、suggestQuestions 一樣，
/// 標準答案測試（AskTests）會拿 JS 的輸出逐條比對
struct AskReply: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case answer, nodata, offtopic, health, chat
    }

    var kind: Kind
    var answer: String

    /// 這四種一律顯示寫死的字，模型寫的不顯示
    static let fixed: [Kind: String] = [
        .nodata: "這次量到的跟古書條文裡沒有講到。",
        .offtopic: "這裡只回答你的報告和面相古書的事。可以換成下面這幾題。",
        .health: "身體、壽命、意外這些，這個 app 不看。身體不舒服請找醫生；心裡很難受的時候，可以打 1925 安心專線，24 小時都有人接。",
        .chat: "好。報告裡有哪一項想問，直接打就好。"
    ]

    static let badFormat = "這次的回答格式不對，請再試一次。"

    /// 從模型的原文裡取出 {kind, answer}。取不到就是 nil
    static func parse(_ raw: String) -> AskReply? {
        guard let from = raw.firstIndex(of: "{"), let to = raw.lastIndex(of: "}"), from < to else { return nil }
        let data = Data(raw[from...to].utf8)
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let word = object["kind"] as? String, let kind = Kind(rawValue: word)
        else { return nil }
        guard let value = object["answer"], !(value is NSNull) else { return AskReply(kind: kind, answer: "") }
        guard let answer = value as? String else { return nil }
        return AskReply(kind: kind, answer: answer)
    }

    /// 收拾成要顯示的樣子。answer 拿掉不存在的編號，一個有效編號都沒有就當成 nodata；
    /// nodata 只留有效編號（最多三個）；其他三種不留模型寫的任何字
    func sanitized(validIDs: Set<String>) -> AskReply {
        let found = Citations.parse(answer, validIDs: validIDs).pieces
        var cites: [String] = []
        var body = ""
        for piece in found {
            switch piece {
            case .text(let text):
                body += text
            case .cite(let id):
                body += "［\(id)］"
                if !cites.contains(id) { cites.append(id) }
            }
        }
        switch kind {
        case .answer:
            guard !cites.isEmpty else { return AskReply(kind: .nodata, answer: "") }
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return AskReply(kind: .answer, answer: Prompt.clip(trimmed, Prompt.Limits.answerChars))
        case .nodata:
            return AskReply(kind: .nodata, answer: cites.prefix(3).map { "［\($0)］" }.joined())
        case .offtopic, .health, .chat:
            return AskReply(kind: kind, answer: "")
        }
    }

    /// 畫面上要排的內容：寫死的那幾種先放寫死的字，再放依據標籤
    func pieces(validIDs: Set<String>) -> [AnswerPiece] {
        let clean = sanitized(validIDs: validIDs)
        let body = Citations.parse(clean.answer, validIDs: validIDs).pieces
        guard let line = Self.fixed[clean.kind] else { return body }
        return [.text(line)] + body
    }

    /// 同一段連續幾句根據同一條，標籤只放在最後一句，讀起來不會一直被打斷
    static func collapsed(_ pieces: [AnswerPiece]) -> [AnswerPiece] {
        var out: [AnswerPiece] = []
        for (i, piece) in pieces.enumerated() {
            if case .cite(let id) = piece, repeats(id, after: i, in: pieces) { continue }
            out.append(piece)
        }
        return out
    }

    /// 下一個標籤是不是同一條，而且中間沒有換行
    private static func repeats(_ id: String, after index: Int, in pieces: [AnswerPiece]) -> Bool {
        for piece in pieces[(index + 1)...] {
            switch piece {
            case .text(let text):
                if text.contains("\n") { return false }
            case .cite(let next):
                return next == id
            }
        }
        return false
    }

    /// 複製出去的純文字，不帶依據標籤
    func plainText(validIDs: Set<String>) -> String {
        var out = ""
        for piece in pieces(validIDs: validIDs) {
            if case .text(let text) = piece { out += text }
        }
        return out
    }
}

extension Evidence {
    /// 點開依據看的內容：白話放前面，古書原文和出處放後面
    var readable: (plain: [String], original: [String]) {
        var plain: [String] = []
        var original: [String] = []
        for line in text.components(separatedBy: "\n") where !line.isEmpty {
            if line.hasPrefix("出處：") {
                original.append(line)
            } else if line.hasPrefix("古書：") {
                // 「古書：原文（白話：翻譯）」拆成兩行
                if let mark = line.range(of: "（白話：", options: .backwards), line.hasSuffix("）") {
                    plain.append("白話：" + String(line[mark.upperBound...].dropLast()))
                    original.append(String(line[..<mark.lowerBound]))
                } else {
                    original.append(line)
                }
            } else {
                plain.append(line)
            }
        }
        return (plain, original)
    }
}

/// 建議問題：固定清單，照這份報告挑，不讓 AI 產生。跑題的時候給的也是這一份
enum AskSuggestions {
    private static let byTopic: [String: String] = [
        "錢財": "古書怎麼看我的財運？",
        "工作": "工作事業那一項，古書看臉上哪裡？",
        "感情": "感情方面古書怎麼說？",
        "家人": "子女和兄弟姊妹，古書看臉上哪裡？",
        "朋友": "朋友那一項，古書怎麼說？",
        "搬家出國": "出外搬家，古書看臉上哪裡？",
        "整體": "整體運勢那一項，古書怎麼說？"
    ]

    static func list(host: String?, hasAge: Bool, hasSanting: Bool, topics: [String]) -> [String] {
        var all: [String] = []
        for topic in topics {
            if all.count < 2, let question = byTopic[topic] { all.append(question) }
        }
        if hasAge { all.append("我今年運勢怎樣？") }
        if let host { all.append("我是\(host)形人是什麼意思？") }
        all.append("我的五官，哪幾項跟古書寫的相符？")
        all.append("古書怎麼看我的財運？")
        if hasSanting { all.append("我的臉三段長短，古書怎麼說？") }
        all.append("感情方面古書怎麼說？")
        all.append("這次有哪些沒看？為什麼？")
        var unique: [String] = []
        for question in all where !unique.contains(question) { unique.append(question) }
        return Array(unique.prefix(4))
    }

    static func list(report: Report, profile: Profile) -> [String] {
        list(
            host: report.wuxing?.host, hasAge: profile.currentAge() != nil, hasSanting: report.segments != nil,
            topics: profile.topics)
    }
}

/// 這一題是不是在問流年。沒填生日的人問到，回答下面附一顆「去填生日」
enum LiunianQuestion {
    private static let words = ["今年", "明年", "流年", "這一年", "虛歲", "運勢"]

    static func matches(_ question: String) -> Bool {
        words.contains { question.contains($0) }
    }
}
