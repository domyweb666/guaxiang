import Foundation

/// 刻度尺：一條看得到的條件，在尺上畫出「古書寫的那一段」和你的位置。
/// 分界用 rules.json 的門檻，兩端和兩端的字用 features 的 scale，這裡不另外寫數字。
struct Ruler: Equatable {
    /// 你的位置，0 是最左、1 是最右。超出兩端就停在邊上
    let position: Double
    /// 分界線的位置
    let edge: Double
    /// 古書寫的那一段在分界線的右邊還是左邊
    let bandOnRight: Bool
    let left: String
    let right: String

    /// 條件沒有門檻、沒有尺、規則庫寫了不畫，或這次量不到，都不畫
    init?(_ c: Condition, measured: Measured, rules: Rules) {
        guard c.noRuler != true, let key = c.feature, let op = c.op, let scale = rules.features[key]?.scale,
            let value = measured[key]?.v, value.isFinite
        else { return nil }
        let threshold: Double?
        if let th = c.th {
            threshold = rules.threshold(th)
        } else {
            threshold = c.value
        }
        let span = scale.to - scale.from
        guard let line = threshold, span != 0 else { return nil }
        let at: (Double) -> Double = { max(0, min(1, ($0 - scale.from) / span)) }
        position = at(value)
        edge = at(line)
        bandOnRight = op.hasPrefix(">") == (span > 0)
        left = scale.left
        right = scale.right
    }

    var band: ClosedRange<Double> { bandOnRight ? edge...1 : 0...edge }
}

extension Report {
    func ruler(_ c: Condition) -> Ruler? {
        Ruler(c, measured: measurement.F, rules: rules)
    }

    /// 十二件事的尺。看三段的那一件，用「三段差不多長」那條規則的門檻
    func ruler(_ x: PalaceResult) -> Ruler? {
        guard x.status != .unjudged, let m = x.palace.measure else { return nil }
        guard m.type == "santing" else { return ruler(m) }
        guard let equal = rules.rules.first(where: { $0.id == "santing-equal" })?.when.conditions.first else {
            return nil
        }
        return ruler(equal)
    }
}
