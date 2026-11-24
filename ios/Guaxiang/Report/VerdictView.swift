import SwiftUI

/// 「跟古書寫的相符、不同、這次沒看」在畫面上長什麼樣，全部集中在這個檔。
/// 要換樣式（形狀、顏色、排法）只改這裡，其他畫面只呼叫，不自己畫。
/// 三種用同一個墨色系，不用對錯的符號和顏色，旁邊一定有字，旁白唸字。

/// 小圓點：相符＝實心、不同＝空心圈、沒看＝虛線圈
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
        case .unjudged:
            Circle().strokeBorder(Theme.secondary, style: StrokeStyle(lineWidth: Theme.hairline, dash: Theme.verdictDash))
        }
    }
}

/// 條件列前面的標記：圓點加字
struct VerdictMark: View {
    let status: Status

    init(_ pass: Bool?) {
        status = Status(pass)
    }

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

/// 摘要：一項一個點，加上三種各幾項
struct VerdictSummary: View {
    let tally: Tally
    /// 項、件
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.item) {
            FlowLayout(spacing: Theme.item) {
                ForEach(Array(dots.enumerated()), id: \.offset) { _, status in
                    VerdictDot(status: status)
                }
            }
            .accessibilityHidden(true)
            Text(tally.sentence(unit))
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var dots: [Status] {
        Array(repeating: Status.pass, count: tally.same)
            + Array(repeating: Status.fail, count: tally.different)
            + Array(repeating: Status.unjudged, count: tally.unseen)
    }
}

/// 總覽和首頁的小格子放不下整句，拆成大字一行、小字兩段
enum VerdictShort {
    static func lead(_ tally: Tally, _ unit: String) -> String {
        "\(tally.same) \(unit)相符"
    }

    static func rest(_ tally: Tally, _ unit: String) -> [String] {
        ["\(tally.different) \(unit)不同", "\(tally.unseen) \(unit)沒看"]
    }
}
