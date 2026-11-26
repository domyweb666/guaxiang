import SwiftUI

/// 「面相」：標題下一排分段鈕，運勢、五官、三段一次看一區，點了照片跟著亮那一區
/// （QC-0009；多米 2026-11-26 選設計 A，參考他截圖的「腿｜推｜拉」）。
/// 先講好處，再講你的長相；怎麼看的、怎麼算的不寫。原文在標題旁的小圓鈕，一張卡只有一顆。
struct FacePage: View {
    @EnvironmentObject private var model: AppModel
    let report: Report
    /// 現在看哪一區，照片跟著亮
    @Binding var section: ReportSection

    var body: some View {
        VStack(spacing: 0) {
            Picker("面相分區", selection: $section) {
                ForEach(ReportSection.onFacePage, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Theme.screenMargin)
            .padding(.vertical, Theme.item)
            Page {
                if model.isSample {
                    Note("範例報告：數字是假的，不是你的臉。", warn: true)
                        .padding(.horizontal, Theme.tight)
                        // 不要緊貼分段鈕
                        .padding(.top, Theme.item)
                }
                if section.locked {
                    LockedSection(section: section)
                } else {
                    switch section {
                    case .officials: officials
                    case .santing: santing
                    default: fortunes
                    }
                }
            }
            // 換區從最上面看起
            .id(section)
        }
        .background(Theme.canvas.ignoresSafeArea())
    }

    /// 區塊標題，旁邊一顆小圓鈕
    private func title(_ text: String, _ note: @escaping () -> BookNote?) -> some View {
        HStack(spacing: Theme.tight) {
            Text(text).font(.title2.bold()).accessibilityAddTraits(.isHeader)
            InfoButton(subject: text, note: note)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.tight)
    }

    private func good(_ text: String) -> some View {
        Text(text)
            .font(.title3.weight(.bold))
            .foregroundStyle(Theme.accent)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func shaky(_ unstable: Bool) -> some View {
        if unstable { Note("這一項不太穩，只當參考", warn: true) }
    }

    // MARK: 運勢

    private var fortunes: some View {
        Group {
            title(ReportSection.palaces.title) { report.fortunesNote }
            Card {
                ForEach(Array(report.fortunes.enumerated()), id: \.element.id) { i, x in
                    CardBlock(divider: i > 0) {
                        HStack(spacing: Theme.tight) {
                            Text(x.palace.topic).font(.headline)
                            InfoButton(subject: x.palace.topic) { report.note(palace: x) }
                            Spacer(minLength: 0)
                        }
                        if x.status == .pass, let say = x.palace.say { good(say.good) }
                        Text(x.front).fixedSize(horizontal: false, vertical: true)
                        shaky(x.unstable)
                    }
                }
            }
        }
    }

    // MARK: 五官

    private var officials: some View {
        Group {
            title(ReportSection.officials.title) { report.officialsNote }
            if let names = report.goodOfficials {
                VStack(alignment: .leading, spacing: Theme.tight) {
                    good(report.rules.wuxing.guanGood)
                    Text("你的\(names)，長成古書寫的樣子。").fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Theme.tight)
            }
            ForEach(report.shownOfficials) { x in officialCard(x) }
        }
    }

    private func officialCard(_ x: OfficialResult) -> some View {
        Card(dashed: x.status == .unjudged) {
            CardBlock(divider: false) {
                HStack(spacing: Theme.item) {
                    if let color = markColor(x.official.id) {
                        // 跟照片上那一圈同一個顏色
                        Circle().fill(color).frame(width: Theme.markDot, height: Theme.markDot).accessibilityHidden(true)
                    }
                    Text(x.official.plain).font(.title3.weight(.semibold))
                    InfoButton(subject: x.official.plain) { report.note(official: x) }
                    Spacer(minLength: 0)
                    VerdictTag(status: x.status)
                }
                if x.status == .unjudged, let why = x.why { Note(why) }
                ForEach(Array(x.rows.enumerated()), id: \.offset) { _, row in rowLine(row) }
            }
        }
    }

    private func rowLine(_ row: ConditionRow) -> some View {
        // 勾了「動過」而沒看的那一條，量得到也不畫
        let ruler = row.status == .unjudged ? nil : report.ruler(row.condition)
        return VStack(alignment: .leading, spacing: Theme.tight / 2) {
            Text(row.front).fixedSize(horizontal: false, vertical: true)
            if let ruler { RulerView(ruler: ruler, status: row.status) }
            shaky(row.result.unstable)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // 兩條尺要分得開，上一條的「窄、寬」才不會看成下一條的
        .padding(.top, Theme.tight)
    }

    /// 這一官在照片上是什麼顏色。沒有照片就不放色點
    private func markColor(_ id: String) -> Color? {
        guard !model.isSample, model.photo != nil else { return nil }
        switch id {
        case "guan-brow": return Theme.markBrow
        case "guan-eye": return Theme.markEye
        case "guan-nose": return Theme.markNose
        case "guan-mouth": return Theme.markMouth
        default: return nil
        }
    }

    // MARK: 三段

    private var santing: some View {
        Group {
            title(ReportSection.santing.title) { report.santingNote }
            Card {
                CardBlock(divider: false) {
                    if let head = report.santingGood { good(head) }
                    Text(report.santingFront).fixedSize(horizontal: false, vertical: true)
                }
                if let segments = report.segments, report.santingRule != nil {
                    CardBlock { ForEach(segments) { s in segmentLine(s, longest: s.k == report.longestSegment?.k) } }
                }
            }
        }
    }

    private func segmentLine(_ s: SantingSegment, longest: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.tight) {
            Text("\(s.k)・\(s.lifeWord)").font(.subheadline.weight(longest ? .semibold : .regular))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.fill)
                    Capsule().fill(longest ? Theme.accent : Theme.rulerBand)
                        .frame(width: geo.size.width * CGFloat(min(1, s.v / 1.4)))
                }
            }
            .frame(height: Theme.barHeight)
            .accessibilityHidden(true)
        }
        .padding(.vertical, Theme.tight / 2)
    }
}
