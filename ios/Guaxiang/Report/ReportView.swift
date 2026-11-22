import SwiftUI

/// 報告的每一區。總覽一列一區，點進去推入那一區的頁面
enum ReportSection: String, Hashable, CaseIterable {
    case wuxing, officials, santing, palaces, others, cannotSee, diagram, numbers

    var title: String {
        switch self {
        case .wuxing: return "臉形"
        case .officials: return "五官"
        case .santing: return "三停"
        case .palaces: return "十二宮"
        case .others: return "其他古書條文"
        case .cannotSee: return "這次沒看的"
        case .diagram: return "標註圖"
        case .numbers: return "數字明細"
        }
    }

    /// 沒買完整版也看得到的區。暫定「臉形和五官免費」（HANDOFF 8-1 的最低限），多米還沒定案（.vibe/代決清單.md）
    var isFree: Bool {
        switch self {
        case .santing, .palaces, .others: return false
        default: return true
        }
    }

    var locked: Bool { !isFree && !Paywall.canSeeFullReport }
}

extension Report {
    /// 三停的短說法，給總覽和首頁那一格
    var santingShort: String {
        guard let segments, let santingRule else { return "沒判" }
        if santingRule.id == "santing-equal" { return "三段差不多長" }
        let longest = segments.max { $0.v < $1.v }
        return "\(longest?.k ?? "")最長"
    }

    var santingLife: String {
        guard let segments, let santingRule else { return "沒拉髮際線" }
        if santingRule.id == "santing-equal" { return "古書說各段平穩" }
        return "管" + (segments.max { $0.v < $1.v }?.life ?? "")
    }

    var judgedPalaces: Int {
        palaces.filter { $0.status != .unjudged }.count
    }

    var measuredCount: Int {
        FeatureEngine.order.filter { measurement.F[$0] != nil }.count
    }
}

/// 報告總覽：古書怎麼說你、問古書、每一區、這次沒看的。設定、匯出、清除都在設定頁，不放這裡（準則 3-3、3-4）
struct ReportView: View {
    @EnvironmentObject private var model: AppModel
    let report: Report
    @State private var showAsk = false
    @State private var showPaywall = false

    private var rules: Rules { report.rules }
    private var m: Measurement { report.measurement }

    var body: some View {
        Page {
            PageTitle(
                title: model.isSample ? "範例報告" : "你的報告",
                lead: model.isSample
                    ? "數字是假的，不是你的臉。用來看報告長什麼樣。"
                    : "\(m.when.formatted(date: .long, time: .omitted))・收了 \(m.frames) 張畫面",
                pushed: true)
            if !m.gaps.isEmpty { gaps }

            SectionTitle("古書怎麼說你")
            summary
            askCard

            SectionTitle("每一區")
            Card {
                ForEach(Array([ReportSection.wuxing, .officials, .santing, .palaces, .others].enumerated()), id: \.offset) {
                    i, s in
                    if i > 0 { RowDivider() }
                    row(s)
                }
            }

            SectionTitle("這次沒看的")
            Card {
                row(.cannotSee)
                RowDivider()
                FlowChips(items: rules.cannotSee.map { "\($0.plain)" })
                    .padding(.horizontal, Theme.cardPad)
                    .padding(.vertical, Theme.rowPadV)
            }

            Card {
                row(.diagram)
                RowDivider()
                row(.numbers)
            }
            .padding(.top, Theme.section - Theme.group)

            Note("古書的說法沒有經過科學驗證。報告不判健康、壽命、災禍，也不評價人品，不能用來替你或別人做重大決定。")
                .padding(.top, Theme.section - Theme.group)
                .padding(.horizontal, Theme.tight)
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAsk) { AskView(report: report) }
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    private func value(_ s: ReportSection) -> String? {
        switch s {
        case .wuxing: return report.wuxing.map { "\($0.host)形" } ?? "沒判"
        case .officials:
            return "\(report.count(.pass)) 合格・\(report.count(.fail)) 不合格・\(report.count(.unjudged)) 沒判"
        case .santing: return report.santingShort
        case .palaces: return "判了 \(report.judgedPalaces) 宮"
        case .others: return report.others.isEmpty ? "沒有對到" : "\(report.others.count) 條"
        case .cannotSee: return "\(rules.cannotSee.count) 項"
        case .diagram: return nil
        case .numbers: return "\(report.measuredCount) 項"
        }
    }

    private func row(_ s: ReportSection) -> some View {
        Button {
            if s.locked { showPaywall = true } else { model.open(s) }
        } label: {
            ReportRow(title: s.title, value: value(s), locked: s.locked)
        }
        .buttonStyle(.plain)
    }

    private var summary: some View {
        Card {
            ForEach(Array(report.summaryPoints.enumerated()), id: \.offset) { i, p in
                CardBlock(divider: i > 0) {
                    (Text(p.title).bold() + Text(p.body.isEmpty ? "" : "：" + p.body))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !report.unstableNames.isEmpty {
                CardBlock {
                    Note(
                        "有幾項在 \(m.frames) 張畫面之間差很多，結果只當參考：\(report.unstableNames.joined(separator: "、"))。",
                        warn: true)
                }
            }
        }
    }

    @ViewBuilder private var askCard: some View {
        if model.isSample {
            Note("範例報告不能問古書。掃過自己的臉之後就能問。").padding(.horizontal, Theme.tight)
        } else {
            Button { showAsk = true } label: {
                HStack(spacing: Theme.group) {
                    Image(systemName: "bubble.left").font(.title3)
                    VStack(alignment: .leading, spacing: Theme.tight / 2) {
                        Text("問古書").font(.headline)
                        Text("只根據這份報告回答，每句標依據").font(.footnote)
                    }
                    Spacer()
                    if let left = Paywall.questionsLeft { Text("還能問 \(left) 題").font(.subheadline) }
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                }
                .foregroundStyle(Theme.onAccent)
                .padding(Theme.cardPad)
                .background(Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            }
            .buttonStyle(PressStyle())
        }
    }

    private var gaps: some View {
        Card {
            CardBlock(divider: false) {
                Text("這一版還量不到的").font(.headline)
                ForEach(m.gaps, id: \.self) { Note($0, warn: true) }
                Note("量不到的項目一律寫「沒判」，沒有拿別的數字湊。")
            }
        }
    }
}

/// 一排會自動換行的小膠囊
struct FlowChips: View {
    let items: [String]

    var body: some View {
        FlowLayout(spacing: Theme.item) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.footnote)
                    .padding(.horizontal, Theme.item)
                    .padding(.vertical, Theme.tight)
                    .background(Theme.fill)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += s.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, s.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}
