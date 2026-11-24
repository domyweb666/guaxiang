import SwiftUI

/// 一區推入頁的樣子：從視窗的總覽往右推進來，標題在視窗最上面那一列
struct ReportSectionView: View {
    let section: ReportSection
    let report: Report

    var body: some View {
        Page { ReportSectionContent(section: section, report: report) }
            .navigationTitle(section.title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// 一區的內容，不含外框。切換列那幾區直接放這個，推入頁也用這個。
/// 正面只放白話；古書原文、術語、數字都在旁邊的小圓鈕裡（BookNote）。
/// 判讀結果的樣子只呼叫 VerdictView.swift，這裡不畫
struct ReportSectionContent: View {
    @EnvironmentObject private var model: AppModel
    let section: ReportSection
    let report: Report

    private var rules: Rules { report.rules }
    private var m: Measurement { report.measurement }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.group) {
            if let lead {
                Text(lead)
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.tight)
            }
            if model.isSample { Note("範例報告：數字是假的，不是你的臉。", warn: true).padding(.horizontal, Theme.tight) }
            if section.locked {
                LockedSection(section: section)
            } else {
                content
            }
        }
        .padding(.top, Theme.item)
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .wuxing: wuxingSection
        case .officials: officialsSection
        case .santing: santingSection
        case .palaces: palacesSection
        case .others: othersSection
        case .cannotSee: cannotSeeSection
        case .diagram: diagramSection
        case .numbers: numbers
        }
    }

    private var lead: String? {
        switch section {
        case .wuxing: return "古書把人分成金、木、水、火、土五種形。"
        case .officials: return "古書寫了耳、眉、眼、鼻、嘴各長什麼樣，這裡拿你的臉去比。"
        case .santing: return "古書把臉從上到下分成三段，各管人生的一段時間。"
        case .palaces: return rules.palacesNote
        case .others: return "這次對得上的其他古書說法。"
        case .cannotSee: return "算命先生當面會看、相機拍不到的。"
        case .diagram: return "量測用到的位置。照片只存在這支手機。"
        case .numbers: return "每一項量出來的數字。怎麼算的、用在哪裡，按旁邊的小圓鈕看。"
        }
    }

    // MARK: 臉形

    @ViewBuilder private var wuxingSection: some View {
        if let wx = report.wuxing, let type = rules.wuxing.types[wx.host] {
            Card {
                wuxingHead(wx, type)
                CardBlock {
                    Note("怎麼看出來的")
                    Text((report.wuxingWhy ?? "") + "五形裡最接近\(wx.host)形。")
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let rel = wx.relation, let guest = wx.guest {
                    CardBlock {
                        PlainLine(subject: "兩種形放在一起", note: { report.relationNote }) {
                            Note("你也帶一點\(guest)形，古書對這樣的搭配怎麼說")
                            ForEach(rel.plain, id: \.self) { Text($0).fixedSize(horizontal: false, vertical: true) }
                            if rel.kind.contains("剋") { Note("兩本古書的看法相反，所以兩種都列出來。") }
                        }
                    }
                }
                CardBlock {
                    Note(rules.wuxing.notFaultPlain)
                    Note("古書分這五種形要看全身和膚色，這次只看臉，所以是推估。")
                }
            }
        } else {
            Card {
                CardBlock(divider: false) {
                    PlainLine(subject: "臉形", note: { report.wuxingNote }) { Note("這次量到的資料不夠，沒看臉形。") }
                }
            }
        }
    }

    private func wuxingHead(_ wx: WuxingResult, _ type: WuxingType) -> some View {
        CardBlock(divider: false) {
            VStack(spacing: Theme.item) {
                Text(wx.host)
                    .font(Theme.mark)
                    .foregroundStyle(Theme.accent)
                    .frame(width: Theme.markSize, height: Theme.markSize)
                    .background(Theme.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous))
                    .accessibilityHidden(true)
                Text("\(wx.host)形・\(type.plainShape)")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Note(wuxingSide(wx)).multilineTextAlignment(.center)
                Text("古書說：\(type.plainLine)")
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Theme.item)
            }
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topTrailing) {
                InfoButton(subject: "臉形") { report.wuxingNote }
                    .padding(.top, -Theme.group)
            }
        }
    }

    private func wuxingSide(_ wx: WuxingResult) -> String {
        var text = wx.guest.map { "也帶一點\($0)形" } ?? "沒有明顯帶別的形"
        if wx.weak { text += "・特徵不明顯，接近中間型" }
        return text
    }

    // MARK: 五官

    @ViewBuilder private var officialsSection: some View {
        VStack(alignment: .leading, spacing: Theme.item) {
            VerdictSummary(tally: report.officialTally, unit: "項")
            PlainLine(subject: "五官", note: { report.officialsNote }) {
                Text(rules.wuxing.guan).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
            Note("沒看的不算相符，也不算不同。「十年」只是概數。")
        }
        .padding(.horizontal, Theme.tight)
        ForEach(report.officials) { x in officialCard(x) }
    }

    private func officialCard(_ x: OfficialResult) -> some View {
        Card {
            CardBlock(divider: false) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.item) {
                    if let color = markColor(x.official.id) {
                        // 跟照片上那一圈同一個顏色
                        Circle().fill(color).frame(width: Theme.markDot, height: Theme.markDot).accessibilityHidden(true)
                    }
                    Text(x.official.plain).font(.title3.weight(.semibold))
                    Spacer()
                    VerdictTag(status: x.status)
                }
                Note("古書說：" + x.official.governs)
                if x.status == .unjudged {
                    Text(x.why ?? "").fixedSize(horizontal: false, vertical: true)
                    Note("沒看的不算相符，也不算不同。")
                }
                ForEach(Array(x.rows.enumerated()), id: \.offset) { _, row in rowLine(row, of: x) }
            }
            CardBlock {
                PlainLine(subject: x.official.plain, note: { report.note(official: x) }) {
                    Note("古書寫的樣子")
                    Text(x.official.baihua).fixedSize(horizontal: false, vertical: true)
                    if let rest = notMeasuredLine(x) { Note(rest) }
                }
            }
        }
    }

    private func notMeasuredLine(_ x: OfficialResult) -> String? {
        let count = x.official.notMeasured?.count ?? 0
        guard count > 0 else { return nil }
        return "古書還看 \(count) 處，這次沒看。" + (x.status == .pass ? "這裡的「相符」只包含看得到的幾條。" : "")
    }

    /// 這一官在照片上是什麼顏色。沒有照片、耳朵沒有標註，就不放色點
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

    private func rowLine(_ row: ConditionRow, of x: OfficialResult) -> some View {
        let c = row.condition
        return HStack(alignment: .center, spacing: Theme.group) {
            VerdictMark(row.result.pass)
            VStack(alignment: .leading, spacing: Theme.tight / 2) {
                Text(rowText(row)).fixedSize(horizontal: false, vertical: true)
                flags(edge: row.result.edge, unstable: row.result.unstable)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            InfoButton(subject: c.plain ?? x.official.plain) { report.note(condition: c, of: x) }
        }
    }

    private func rowText(_ row: ConditionRow) -> String {
        guard let pass = row.result.pass else { return "\(row.condition.plain ?? "")：這次量不到" }
        return (pass ? row.condition.yes : row.condition.no) ?? ""
    }

    /// 結論可能會變的提醒留在正面，數字在小圓鈕裡
    @ViewBuilder private func flags(edge: Bool, unstable: Bool) -> some View {
        if edge { Note("剛好在交界附近，換個光線再掃可能會變", warn: true) }
        if unstable { Note("\(m.frames) 張畫面之間差很多，只當參考", warn: true) }
    }

    // MARK: 三段

    @ViewBuilder private var santingSection: some View {
        if let segments = report.segments, report.santingRule != nil {
            Card {
                CardBlock(divider: false) {
                    PlainLine(subject: "臉的三段", note: { report.santingNote }) {
                        Text(report.santingHeadline ?? "").fixedSize(horizontal: false, vertical: true)
                        Note("古書還看每一段豐不豐滿，這次沒看。")
                    }
                }
                ForEach(segments) { s in CardBlock { segmentLine(s) } }
            }
        } else {
            Card {
                CardBlock(divider: false) {
                    PlainLine(subject: "臉的三段", note: { report.santingNote }) {
                        Note("沒有拉髮際線，上段量不到，這次沒看。有瀏海的話，撥開再掃一次就能看。")
                    }
                }
            }
        }
    }

    private func segmentLine(_ s: SantingSegment) -> some View {
        PlainLine(subject: s.k, note: { report.note(segment: s) }) {
            HStack {
                Text(s.k).bold() + Text("・管\(s.life)")
                Spacer()
                Note(s.v < 0.95 ? "比平均短" : s.v > 1.05 ? "比平均長" : "接近平均")
            }
            Note(s.part)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.fill)
                    Capsule().fill(Theme.accent)
                        .frame(width: geo.size.width * CGFloat(min(1, s.v / 1.4)))
                }
            }
            .frame(height: Theme.barHeight)
            .accessibilityHidden(true)
        }
    }

    // MARK: 十二件事

    @ViewBuilder private var palacesSection: some View {
        VStack(alignment: .leading, spacing: Theme.item) {
            PlainLine(subject: "人生十二件事", note: { report.palacesNote }) {
                VerdictSummary(tally: report.palaceTally, unit: "件")
            }
            Note("沒看的不算相符，也不算不同。")
        }
        .padding(.horizontal, Theme.tight)
        ForEach(report.palaces) { x in palaceCard(x) }
    }

    private func palaceCard(_ x: PalaceResult) -> some View {
        let g = x.palace
        return Card {
            CardBlock(divider: false) {
                HStack(spacing: Theme.item) {
                    Text(g.topic).font(.title3.weight(.semibold))
                    Spacer()
                    VerdictTag(status: x.status)
                    InfoButton(subject: g.topic) { report.note(palace: x) }
                }
                Note("看臉上的" + g.place)
                Text(x.line).fixedSize(horizontal: false, vertical: true)
                flags(edge: x.edge, unstable: x.unstable)
                if let baihua = g.baihua { Note("古書說：" + baihua) }
            }
        }
    }

    // MARK: 其他說法

    @ViewBuilder private var othersSection: some View {
        if report.others.isEmpty {
            Card { CardBlock(divider: false) { Note("這次沒有對上其他古書說法。") } }
        }
        ForEach(report.others) { r in
            Card {
                CardBlock(divider: false) {
                    PlainLine(subject: r.headline ?? "", note: { report.note(rule: r) }) {
                        if r.experimental == true { Tag(text: "實驗", color: Theme.bad, background: Theme.badSoft) }
                        Text(r.headline ?? "")
                            .font(.body.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(r.baihua).fixedSize(horizontal: false, vertical: true)
                        if let note = r.note { Note(note) }
                    }
                }
            }
        }
    }

    // MARK: 這次沒看的

    @ViewBuilder private var cannotSeeSection: some View {
        Card {
            ForEach(Array(rules.cannotSee.enumerated()), id: \.offset) { i, c in
                CardBlock(divider: i > 0) {
                    PlainLine(subject: c.plain, note: { report.note(cannotSee: c) }) {
                        Text(c.plain).font(.body.weight(.semibold))
                        Note(c.why)
                    }
                }
            }
        }
        if !skipped.isEmpty {
            SectionTitle("你選了不看的")
            Card {
                ForEach(Array(skipped.enumerated()), id: \.offset) { i, s in
                    CardBlock(divider: i > 0) {
                        Text(s.0).font(.body.weight(.semibold))
                        Note(s.1)
                    }
                }
            }
        }
    }

    private var skipped: [(String, String)] {
        var out: [(String, String)] = []
        if !m.hasHair { out.append(("臉的上段", "沒有拉髮際線")) }
        if m.answers.browTattoo { out.append(("眉毛", "你勾了紋眉或修眉")) }
        if m.answers.noseSurgery { out.append(("鼻子", "你勾了鼻子動過")) }
        return out
    }

    // MARK: 標註圖

    private var diagramSection: some View {
        VStack(alignment: .leading, spacing: Theme.group) {
            if !model.isSample, let photo = model.photo { AnnotatedPhoto(photo: photo) }
            Card {
                CardBlock(divider: false) {
                    FaceDiagram(frame: model.isSample ? nil : model.capture?.best.frame)
                    Note("紅色虛線是三段的分界線。這張只畫線條，把臉攤平、去掉鏡頭的變形，數字是照這張算的。")
                }
            }
        }
    }

    // MARK: 數字明細

    private var numbers: some View {
        Card {
            CardBlock(divider: false) {
                Note("每一項都是比例或角度，不受臉離鏡頭遠近影響。數字取 \(m.frames) 張畫面的中間那一個。")
            }
            ForEach(FeatureEngine.order, id: \.self) { key in
                if let stat = m.F[key], let def = rules.features[key] {
                    CardBlock { numberLine(key, stat, def) }
                }
            }
            if report.wuxing != nil {
                CardBlock {
                    PlainLine(subject: "臉形的分數", note: { report.wuxingNote }) {
                        Text("臉形的分數").font(.subheadline.weight(.semibold))
                    }
                }
            }
            CardBlock {
                Note(String(format: "掃的時候，畫面平均亮度 %.0f（最亮 255）・規則庫 %@", m.light, m.rulesVersion))
            }
        }
    }

    private func numberLine(_ key: String, _ stat: FeatureStat, _ def: FeatureDef) -> some View {
        PlainLine(subject: def.plainName, note: { report.note(feature: key) }) {
            HStack {
                Text(def.plainName).font(.subheadline.weight(.semibold))
                Spacer()
                Text(BookNote.text(stat.v, unit: def.unit)).font(.subheadline.monospacedDigit())
            }
            if stat.unstable { Note("\(m.frames) 張畫面之間差很多，只當參考", warn: true) }
        }
    }
}

/// 鎖住的那一區：就地說明完整版有什麼，不從視窗上再疊一層視窗（準則 4-5）。
/// 現在 Paywall 全開，這一塊不會出現；第 8 步接 StoreKit 時，購買鈕放在這裡
struct LockedSection: View {
    let section: ReportSection

    var body: some View {
        Card {
            CardBlock(divider: false) {
                Label("\(section.title)在完整版裡", systemImage: "lock")
                    .font(.headline)
                Text("完整版有臉的三段、人生十二件事、其他古書說法，問古書 \(Paywall.includedQuestions) 題，再掃幾次都會出完整報告。")
                Note("一次付清，這支 Apple ID 之後都能用。")
            }
        }
    }
}

/// 標註圖：把量測用到的點畫成線條。沒有這次掃描的點（例如打開的是上一次的報告）就說明原因。
struct FaceDiagram: View {
    let frame: FaceFrame?

    var body: some View {
        if let frame, let aligned = Geometry.align(frame)?.points, let box = bounds(aligned) {
            Canvas { context, size in
                let scale = min(size.width / box.width, size.height / box.height) * 0.86
                let ox = (size.width - box.width * scale) / 2 - box.minX * scale
                let oy = (size.height - box.height * scale) / 2 - box.minY * scale
                let at: (LM) -> CGPoint? = { lm in
                    guard let p = aligned[lm] else { return nil }
                    return CGPoint(x: CGFloat(p.x) * scale + ox, y: CGFloat(p.y) * scale + oy)
                }
                for shape in Self.strokes {
                    let pts = shape.names.compactMap(at)
                    guard pts.count == shape.names.count, let first = pts.first else { continue }
                    var path = Path()
                    path.move(to: first)
                    for p in pts.dropFirst() { path.addLine(to: p) }
                    if shape.closed { path.closeSubpath() }
                    context.stroke(path, with: .color(shape.color), lineWidth: 2)
                }
                for lm in [LM.glabella, .subnasale, .chin] {
                    guard let p = at(lm), let left = at(.cheekR), let right = at(.cheekL) else { continue }
                    var path = Path()
                    path.move(to: CGPoint(x: left.x, y: p.y))
                    path.addLine(to: CGPoint(x: right.x, y: p.y))
                    context.stroke(
                        path, with: .color(Theme.accent), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                }
            }
            .aspectRatio(box.width / box.height, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("量測點的線條圖")
        } else {
            Note("線條圖只有剛掃完看得到，關掉 app 之後不留。")
        }
    }

    private struct Stroke {
        let names: [LM]
        let color: Color
        let closed: Bool
    }

    private static let strokes: [Stroke] = [
        Stroke(names: [.templeR, .cheekR, .jawR, .chin, .jawL, .cheekL, .templeL], color: .gray, closed: false),
        Stroke(names: [.browHeadR, .browTailR], color: .purple, closed: false),
        Stroke(names: [.browHeadL, .browTailL], color: .purple, closed: false),
        Stroke(names: [.eyeOuterR, .eyeTopR, .eyeInnerR, .eyeBottomR], color: .blue, closed: true),
        Stroke(names: [.eyeOuterL, .eyeTopL, .eyeInnerL, .eyeBottomL], color: .blue, closed: true),
        Stroke(
            names: [.noseRoot, .noseBridge1, .noseBridge2, .noseBridge3, .noseBridge4, .noseTip], color: .green,
            closed: false),
        Stroke(names: [.mouthR, .lipTop, .mouthL, .lipBottom], color: .pink, closed: true)
    ]

    private func bounds(_ points: FaceFrame) -> CGRect? {
        let xs = points.values.map(\.x), ys = points.values.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max(), maxX > minX,
            maxY > minY
        else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
