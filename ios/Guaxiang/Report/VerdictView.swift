import SwiftUI

/// 「跟古書寫的相符、不同、在交界上、這次沒看」在畫面上長什麼樣，全部集中在這個檔。
/// 要換樣式（形狀、顏色、排法）只改這裡，其他畫面只呼叫，不自己畫。
/// 多米 2026-11-25 選 B 刻度尺：看得到的畫尺，一段是古書寫的樣子，圓點是你的位置。
/// 不用對錯的符號和顏色，旁邊一定有字，旁白唸字。沒有尺的（沒看、量不到）才用小標籤。

/// 小圓點：相符＝實心、不同＝空心圈、在交界上＝左半邊實心、沒看＝虛線圈
struct VerdictDot: View {
    let status: Status
    @ScaledMetric(relativeTo: .footnote) var side: CGFloat = Theme.markDot

    var body: some View {
        shape
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var shape: some View {
        switch status {
        case .pass:
            Circle().fill(Theme.accent)
        case .fail:
            Circle().strokeBorder(Theme.accent, lineWidth: Theme.markWidth)
        case .edge:
            Circle().strokeBorder(Theme.accent, lineWidth: Theme.markWidth)
                .background(Circle().trim(from: 0.25, to: 0.75).fill(Theme.accent))
        case .unjudged:
            Circle().strokeBorder(Theme.secondary, style: StrokeStyle(lineWidth: Theme.hairline, dash: Theme.verdictDash))
        }
    }
}

/// 條件列前面的標記：圓點加字
struct VerdictMark: View {
    let status: Status

    var body: some View {
        HStack(spacing: Theme.tight) {
            VerdictDot(status: status)
            Text(status.word)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondary)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.word)
    }
}

/// 卡片右上角的標籤
struct VerdictTag: View {
    let status: Status

    var body: some View {
        HStack(spacing: Theme.tight) {
            VerdictDot(status: status)
            Text(status.word)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(status == .unjudged ? Theme.secondary : Color.primary)
        }
        .padding(.horizontal, Theme.item)
        .padding(.vertical, Theme.tight / 2)
        .background(Theme.fill)
        .clipShape(RoundedRectangle(cornerRadius: Theme.tagRadius, style: .continuous))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.word)
    }
}

/// 摘要：四種各幾項
struct VerdictSummary: View {
    let tally: Tally
    /// 項、件
    let unit: String

    var body: some View {
        Text(tally.sentence(unit))
            .font(.headline)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 頁首那兩句：尺怎麼看、分界是誰定的
struct RulerGuide: View {
    var body: some View {
        Note("紅色那一段是古書寫的樣子，圓點是你的位置。圓點落在分界線旁邊那一小段淡色裡，就是在交界上，不算相符也不算不同。古書沒有給數字，分界、交界的寬度和尺的兩端都是本工具暫定的。")
    }
}

/// 刻度尺
struct RulerView: View {
    let ruler: Ruler
    let status: Status

    var body: some View {
        VStack(spacing: Theme.tight) {
            bar
            HStack(alignment: .firstTextBaseline) {
                Note(ruler.left)
                Spacer(minLength: Theme.item)
                Note(ruler.right).multilineTextAlignment(.trailing)
            }
        }
        .padding(.top, Theme.tight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("刻度尺，從\(ruler.left)到\(ruler.right)")
        .accessibilityValue(
            spoken)
    }

    private var spoken: String {
        switch status {
        case .pass: return "你的位置在古書寫的那一段裡面，相符"
        case .fail: return "你的位置在古書寫的那一段外面，不同"
        case .edge: return "你的位置剛好在交界上，不算相符也不算不同"
        case .unjudged: return "這次沒看"
        }
    }

    private var bar: some View {
        GeometryReader { geo in bar(width: geo.size.width) }
            .frame(height: Theme.rulerDot)
    }

    /// 圓點。在交界上的改空心，裡面看得到分界線和淡色那一段
    @ViewBuilder private var marker: some View {
        if status == .edge {
            Circle().strokeBorder(Theme.accent, lineWidth: Theme.rulerRing)
        } else {
            Circle()
                .fill(Theme.accent)
                .padding(Theme.rulerRing)
                .background(Circle().fill(Theme.card))
        }
    }

    /// 圓點的中心能走的範圍兩邊各縮半顆。分界線跟圓點用同一個換算，圓點在哪一邊不會看錯
    private func bar(width: CGFloat) -> some View {
        let half = Theme.rulerDot / 2
        let room = max(0, width - Theme.rulerDot)
        let edge = half + CGFloat(ruler.edge) * room
        let dot = half + CGFloat(ruler.position) * room
        let start = ruler.bandOnRight ? edge : 0
        let end = ruler.bandOnRight ? width : edge
        // 交界那一小段：先用底色蓋掉，再鋪一層淡的
        let low = half + CGFloat(ruler.buffer.lowerBound) * room
        let high = half + CGFloat(ruler.buffer.upperBound) * room
        return ZStack(alignment: .leading) {
            ZStack(alignment: .leading) {
                Theme.fill
                Theme.rulerBand.frame(width: max(0, end - start)).offset(x: start)
                Theme.rulerBuffer.frame(width: max(0, high - low)).offset(x: low)
            }
            .frame(height: Theme.rulerTrack)
            .clipShape(Capsule())
            Capsule()
                .fill(Theme.accent)
                .frame(width: Theme.markWidth, height: Theme.rulerTick)
                .offset(x: edge - Theme.markWidth / 2)
            marker
                .frame(width: Theme.rulerDot, height: Theme.rulerDot)
                .offset(x: dot - half)
        }
        .frame(width: width, height: Theme.rulerDot, alignment: .leading)
    }
}

/// 總覽和首頁的小格子放不下整句，拆成大字一行、小字兩段
enum VerdictShort {
    static func lead(_ tally: Tally, _ unit: String) -> String {
        "\(tally.same) \(unit)相符"
    }

    static func rest(_ tally: Tally, _ unit: String) -> [String] {
        // 格子小，在交界上是 0 就不放；完整一句一定四種都寫
        ["\(tally.different) \(unit)不同"]
            + (tally.onEdge > 0 ? ["\(tally.onEdge) \(unit)在交界上"] : [])
            + ["\(tally.unseen) \(unit)沒看"]
    }
}
