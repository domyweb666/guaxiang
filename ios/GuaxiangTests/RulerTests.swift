import XCTest

@testable import Guaxiang

/// 刻度尺：圓點在不在「古書寫的那一段」裡，要跟判讀的相符／不同完全一致。
final class RulerTests: XCTestCase {
    private func loadRules() throws -> Rules {
        let bundle = Bundle(for: RulerTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: "rules", withExtension: "json"))
        return try Rules.decode(Data(contentsOf: url))
    }

    private func conditions(_ rules: Rules) -> [Condition] {
        let officials: [Condition] = rules.officials.flatMap { $0.conditions }
        let palaces: [Condition] = rules.palaces.compactMap { $0.measure }
            .filter { $0.type != "santing" && $0.noRuler != true }
        let santing: [Condition] = rules.rules.first { $0.id == "santing-equal" }?.when.conditions ?? []
        return officials + palaces + santing
    }

    func testDotAgreesWithVerdict() throws {
        let rules = try loadRules()
        let judge = Judge(rules: rules)
        let all = conditions(rules)
        XCTAssertFalse(all.isEmpty)
        for c in all {
            let key = try XCTUnwrap(c.feature)
            let scale = try XCTUnwrap(rules.features[key]?.scale, key)
            XCTAssertFalse(scale.left.isEmpty || scale.right.isEmpty, key)
            let span = scale.to - scale.from
            // 從尺的左邊外面走到右邊外面
            for step in -20...120 {
                let value = scale.from + span * Double(step) / 100
                let F: Measured = [key: FeatureStat(v: value, iqr: 0, unstable: false)]
                let ruler = try XCTUnwrap(Ruler(c, measured: F, rules: rules), key)
                XCTAssertTrue(ruler.edge > 0.1 && ruler.edge < 0.9, "\(key)：分界線太靠邊")
                XCTAssertTrue((0...1).contains(ruler.position), key)
                // 剛好壓在線上的，浮點誤差會左右晃，略過
                if abs(ruler.position - ruler.edge) < 1e-9 { continue }
                XCTAssertEqual(ruler.band.contains(ruler.position), judge.test(F, c).pass, "\(key) \(value)")
            }
        }
    }

    func testNoRulerWhenNotMeasuredOrNotInBook() throws {
        let rules = try loadRules()
        for c in conditions(rules) { XCTAssertNil(Ruler(c, measured: [:], rules: rules)) }
        let report = Report(measurement: Sample.measurement(rulesVersion: rules.version), rules: rules)
        for x in report.palaces {
            let drawn = report.ruler(x) != nil
            XCTAssertEqual(drawn, x.status != .unjudged && x.palace.id != "ming", x.palace.topic)
        }
    }
}
