import Foundation

/// 今日一句：每天從這份報告「對上的好處」挑一句，加上今年的流年。
/// 臉不會每天變，所以不說是今天看出來的；只是每天換一句古書說你的話，輪完一圈才重複。
/// 同一份報告、同一天，挑到的一定一樣（不用亂數，換手機、重開 app 都一樣）。
struct DailyLine: Equatable {
    /// 哪件事，例如「錢財」「今年的流年」
    let topic: String
    /// 大字那一句：古書說的好處
    let good: String
    /// 你的長相，或流年走到哪裡
    let line: String
    /// 古書原文，沒有就不放
    let quote: String?
    /// 點了跳到報告哪一區；流年沒有對應的區
    let section: ReportSection?
    /// 換日也不會變的代號，測試和「今天看過了」用
    let key: String
}

enum Daily {
    /// 這份報告可以輪的句子。沒對上的、還沒買的區都不放（跟首頁那幾列同一個規矩）
    static func pool(_ r: Report, age: Int?, isLocked: (ReportSection) -> Bool = { $0.locked }) -> [DailyLine] {
        var out: [DailyLine] = []

        if let wx = r.wuxing, let type = r.rules.wuxing.types[wx.host], let good = type.good {
            out.append(
                DailyLine(
                    topic: "\(wx.host)形人", good: good, line: type.plainLine, quote: type.yuanwen,
                    section: .wuxing, key: "wuxing-\(wx.host)"))
        }

        if let names = r.goodOfficials {
            out.append(
                DailyLine(
                    topic: "五官", good: r.rules.wuxing.guanGood, line: "你的\(names)長成古書寫的樣子。", quote: nil,
                    section: .officials, key: "officials"))
        }

        for x in r.fortunes where x.status == .pass {
            guard let say = x.palace.say else { continue }
            out.append(
                DailyLine(
                    topic: x.palace.topic, good: say.good, line: say.pass, quote: x.palace.yuanwen,
                    section: .palaces, key: "palace-\(x.palace.id)"))
        }

        if let good = r.santingGood {
            out.append(
                DailyLine(
                    topic: "臉的三段", good: good, line: r.santingFront, quote: r.santingRule?.yuanwen,
                    section: .santing, key: "santing"))
        }

        for rule in r.others {
            guard let good = rule.good else { continue }
            out.append(
                DailyLine(
                    topic: rule.part, good: good, line: rule.goodLine ?? rule.baihua, quote: rule.yuanwen,
                    section: .others, key: "rule-\(rule.id)"))
        }

        out = out.filter { $0.section.map { !isLocked($0) } ?? true }

        // 流年跟「運勢」那一區一起開放
        if !isLocked(.palaces), let ln = Judge(rules: r.rules).liunian(age: age), let row = ln.hit {
            let layer = row.plainLayer
            let line =
                layer.isEmpty
                ? "古書把一歲對應臉上一個部位，虛歲 \(ln.xu) 歲看這裡。"
                : "古書把一歲對應臉上一個部位，虛歲 \(ln.xu) 歲看這裡，管的是\(layer)。"
            out.append(
                DailyLine(
                    topic: "今年的流年", good: "今年走到\(row.name)（\(row.place)）", line: line, quote: nil, section: nil,
                    key: "liunian-\(ln.xu)"))
        }
        return out
    }

    /// 今天那一句。一句都沒有就是 nil，首頁不放這張卡
    static func today(
        _ r: Report, age: Int?, now: Date = Date(), calendar: Calendar = .current,
        isLocked: (ReportSection) -> Bool = { $0.locked }
    ) -> DailyLine? {
        let lines = pool(r, age: age, isLocked: isLocked)
        guard !lines.isEmpty else { return nil }
        let order = shuffled(lines.count, seed: seed(r.measurement.when))
        let index = dayNumber(now, calendar: calendar) % lines.count
        return lines[order[index]]
    }

    /// 從 2000-01-01 算起第幾天，照手機的時區換日
    static func dayNumber(_ date: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1)) ?? Date(timeIntervalSince1970: 0)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: date))
        return max(0, days.day ?? 0)
    }

    /// 每份報告輪的順序不一樣，但同一份報告永遠一樣。Swift 的 Hasher 每次開 app 都不同，所以自己算
    private static func seed(_ when: Date) -> UInt64 {
        UInt64(bitPattern: Int64(when.timeIntervalSince1970.rounded()))
    }

    static func shuffled(_ n: Int, seed: UInt64) -> [Int] {
        var order = Array(0..<n)
        var state = seed &+ 0x9E37_79B9_7F4A_7C15
        func next() -> UInt64 {
            // splitmix64
            state = state &+ 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        if n > 1 {
            for i in stride(from: n - 1, to: 0, by: -1) {
                let j = Int(next() % UInt64(i + 1))
                order.swapAt(i, j)
            }
        }
        return order
    }
}
