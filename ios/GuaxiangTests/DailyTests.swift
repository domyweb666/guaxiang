import XCTest

@testable import Guaxiang

/// 今日一句：同一天一樣、輪完一圈才重複、沒買的區不出現、只放對上的好處
final class DailyTests: XCTestCase {
    private func report() throws -> Report {
        let bundle = Bundle(for: DailyTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: "rules", withExtension: "json"))
        let rules = try Rules.decode(Data(contentsOf: url))
        return Report(measurement: Sample.measurement(rulesVersion: rules.version), rules: rules)
    }

    private let open: (ReportSection) -> Bool = { _ in false }
    private let freeOnly: (ReportSection) -> Bool = { !$0.isFree }

    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return c.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    private var taipei: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return c
    }

    func testSameDaySameLine() throws {
        let r = try report()
        let morning = Daily.today(r, age: 35, now: day(2026, 11, 27, hour: 0), calendar: taipei, isLocked: open)
        let night = Daily.today(r, age: 35, now: day(2026, 11, 27, hour: 23), calendar: taipei, isLocked: open)
        XCTAssertNotNil(morning)
        XCTAssertEqual(morning, night)
    }

    func testCyclesThroughAllBeforeRepeating() throws {
        let r = try report()
        let pool = Daily.pool(r, age: 35, isLocked: open)
        XCTAssertGreaterThanOrEqual(pool.count, 2)
        var seen: [String] = []
        for i in 0..<pool.count {
            let date = taipei.date(byAdding: .day, value: i, to: day(2026, 11, 27))!
            seen.append(try XCTUnwrap(Daily.today(r, age: 35, now: date, calendar: taipei, isLocked: open)).key)
        }
        XCTAssertEqual(Set(seen).count, pool.count)
    }

    func testOnlyGoodNewsAndHasLiunian() throws {
        let r = try report()
        let pool = Daily.pool(r, age: 35, isLocked: open)
        XCTAssertTrue(pool.contains { $0.key.hasPrefix("liunian-") })
        for line in pool where line.key.hasPrefix("palace-") {
            let id = String(line.key.dropFirst("palace-".count))
            XCTAssertEqual(r.fortunes.first { $0.palace.id == id }?.status, .pass)
        }
        XCTAssertFalse(Daily.pool(r, age: nil, isLocked: open).contains { $0.key.hasPrefix("liunian-") })
    }

    func testLockedSectionsStayOut() throws {
        let r = try report()
        let pool = Daily.pool(r, age: 35, isLocked: freeOnly)
        XCTAssertTrue(pool.allSatisfy { $0.section?.isFree == true })
        XCTAssertFalse(pool.contains { $0.key.hasPrefix("liunian-") })
    }

    func testShuffleIsAPermutation() {
        for n in [0, 1, 2, 7, 13] {
            XCTAssertEqual(Daily.shuffled(n, seed: 42).sorted(), Array(0..<n))
            XCTAssertEqual(Daily.shuffled(n, seed: 42), Daily.shuffled(n, seed: 42))
        }
    }
}
