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
/// 內容和白話用語照網頁版，只是從一條長捲軸拆開
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
        case .officials: return "古書把耳、眉、眼、鼻、口叫五官。每一官的條件全部符合才算合格。"
        case .santing: return "古書把臉從上到下分成三段，各管人生的一段時間。"
        case .palaces: return rules.palacesNote
        case .others: return "這次量測對得上的其他古書條文。"
        case .cannotSee: return "算命先生當面會看、相機拍不到的。"
        case .diagram: return "量測用到的位置。照片只存在這支手機。"
        case .numbers: return "給想核對算法的人。"
        }
    }

    // MARK: 臉形

    @ViewBuilder private var wuxingSection: some View {
        let W = rules.wuxing
        if let wx = report.wuxing, let type = W.types[wx.host] {
            Card {
                CardBlock(divider: false) {
                    VStack(spacing: Theme.item) {
                        Text(wx.host)
                            .font(Theme.mark)
                            .foregroundStyle(Theme.accent)
                            .frame(width: Theme.markSize, height: Theme.markSize)
                            .background(Theme.accentSoft)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous))
                            .accessibilityHidden(true)
                        Text("\(wx.host)形人").font(.title.bold())
                        Note(
                            (wx.guest.map { "也帶一點\($0)形" } ?? "沒有明顯帶別的形")
                                + (wx.weak ? "・特徵不明顯，接近中間型" : ""))
                        Text(type.yuanwen).font(Theme.quote).multilineTextAlignment(.center).padding(.top, Theme.item)
                        Text(type.plainLine).multilineTextAlignment(.center)
                        Note(W.source)
                    }
                    .frame(maxWidth: .infinity)
                }
                CardBlock {
                    Note("怎麼看出來的")
                    Text((report.wuxingWhy ?? "") + "五形裡最接近\(wx.host)形（\(type.plainShape)）。")
                    Note("古書只說「金方、木瘦、水圓、火尖、土厚」，沒有給數字。用多少比例算哪一形，是本工具暫定的算法。")
                }
                if let rel = wx.relation, let guest = wx.guest {
                    CardBlock {
                        Note("你主要是\(wx.host)形，也帶一點\(guest)形：\(report.wuxingRelationPlain ?? "")")
                        ForEach(rel.lines, id: \.self) { Text($0) }
                        if rel.kind.contains("剋") { Note("兩本古書對這一組的看法剛好相反，所以兩種都列出來。") }
                    }
                }
                CardBlock {
                    Note(W.notFaultPlain + "\n另外，五行形本來要看全身和膚色，這裡只看臉形，所以只是推估。")
                }
            }
        } else {
            Card { CardBlock(divider: false) { Note("量測資料不足，這次沒判臉形。") } }
        }
    }

    // MARK: 五官

    @ViewBuilder private var officialsSection: some View {
        VStack(alignment: .leading, spacing: Theme.item) {
            StatusBar(pass: report.count(.pass), fail: report.count(.fail), unjudged: report.count(.unjudged))
            Text("\(report.count(.pass)) 合格・\(report.count(.fail)) 不合格・\(report.count(.unjudged)) 沒判")
                .font(.headline)
            Text(rules.wuxing.guan).font(.subheadline)
            Note("「沒判」的不能當成合格來算；「十年」也只是概數。")
        }
        .padding(.horizontal, Theme.tight)
        ForEach(report.officials) { x in
            Card {
                CardBlock(divider: false) {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.item) {
                        if let color = markColor(x.official.id) {
                            // 跟照片上那一圈同一個顏色
                            Circle().fill(color).frame(width: Theme.markDot, height: Theme.markDot).accessibilityHidden(true)
                        }
                        (Text(x.official.plain).font(.title3.weight(.semibold))
                            + Text("・" + x.official.name).font(.subheadline).foregroundColor(Theme.secondary))
                        Spacer()
                        Tag.status(x.status)
                    }
                    Note(x.official.governs)
                    if x.status == .unjudged {
                        Text(x.why ?? "")
                        Note("不判的不算合格，也不算不合格。")
                    }
                    ForEach(Array(x.rows.enumerated()), id: \.offset) { _, row in rowLine(row) }
                }
                CardBlock {
                    Note("古書的合格標準（白話整理）")
                    Text(x.official.baihua)
                    Note("\(x.official.source)・文獻 \(x.official.lit)")
                }
                if let notMeasured = x.official.notMeasured, !notMeasured.isEmpty {
                    CardBlock {
                        DisclosureGroup("這一官還有 \(notMeasured.count) 條量不到") {
                            Text(
                                notMeasured.joined(separator: "、") + "。"
                                    + (x.status == .pass ? "所以這裡的合格，只代表量得到的幾條合格。" : "")
                            )
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, Theme.item)
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
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

    @ViewBuilder private func rowLine(_ row: ConditionRow) -> some View {
        if let pass = row.result.pass {
            HStack(alignment: .firstTextBaseline, spacing: Theme.item) {
                Image(systemName: pass ? "checkmark" : "xmark")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(pass ? Theme.ok : Theme.bad)
                    .accessibilityLabel(pass ? "符合" : "不符合")
                VStack(alignment: .leading, spacing: Theme.tight / 2) {
                    Text((pass ? row.condition.yes : row.condition.no) ?? "")
                    if row.result.x != nil { Note(numberLine(row)) }
                    if row.result.edge { Note("邊緣：剛好在標準線附近，換個光線再掃可能會變", warn: true) }
                    if row.result.unstable { Note("不穩：\(m.frames) 張畫面之間差很多，只當參考", warn: true) }
                }
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: Theme.item) {
                Image(systemName: "minus").foregroundStyle(Theme.secondary).accessibilityHidden(true)
                Note("\(row.condition.label ?? "")：這次量不到")
            }
        }
    }

    private func numberLine(_ row: ConditionRow) -> String {
        let key = row.condition.feature ?? ""
        let value = report.format(key, row.result.x)
        let standard = report.format(key, row.result.t)
        return "\(row.condition.label ?? "") \(value)（標準 \(row.condition.op ?? "") \(standard)）"
    }

    // MARK: 三停

    @ViewBuilder private var santingSection: some View {
        if let segments = report.segments, let st = report.santingRule {
            Card {
                CardBlock(divider: false) { Text(report.santingHeadline ?? "") }
                ForEach(segments) { s in
                    CardBlock {
                        HStack {
                            Text(s.k).bold() + Text("・管\(s.life)")
                            Spacer()
                            Note(s.v < 0.95 ? "偏短" : s.v > 1.05 ? "偏長" : "接近平均")
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
                CardBlock {
                    Text(st.yuanwen ?? "").font(Theme.quote)
                    Note(st.baihua)
                    Note(st.source)
                }
            }
        } else {
            Card {
                CardBlock(divider: false) { Note("沒有拉髮際線，上段量不到，這次沒判。有瀏海的話，撥開再掃一次就能看。") }
            }
        }
    }

    // MARK: 十二宮

    @ViewBuilder private var palacesSection: some View {
        Note("判了 \(report.judgedPalaces) 宮，\(report.palaces.count - report.judgedPalaces) 宮這次量不到。點每一宮看細節。")
            .padding(.horizontal, Theme.tight)
        ForEach(report.palaces) { x in
            let g = x.palace
            Card {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: Theme.group) {
                        Note("在臉上哪裡")
                        Text(g.place)
                        if g.measure != nil {
                            Note("你的結果")
                            Text(x.line)
                            if x.edge { Note("邊緣：剛好在標準線附近，換個光線再掃可能會變", warn: true) }
                            if x.unstable { Note("不穩：\(m.frames) 張畫面之間差很多，只當參考", warn: true) }
                            if let notMeasured = g.notMeasured { Note(notMeasured) }
                        } else {
                            Note("為什麼這次沒判")
                            Text(g.why ?? "")
                        }
                        if let yuanwen = g.yuanwen {
                            Note("古書怎麼說")
                            Text(yuanwen).font(Theme.quote)
                            Text(g.baihua ?? "")
                            if let source = g.source { Note(source) }
                        }
                        if let note = g.note { Note(note) }
                    }
                    .padding(.top, Theme.item)
                } label: {
                    VStack(alignment: .leading, spacing: Theme.tight) {
                        HStack(spacing: Theme.item) {
                            Text(g.topic).font(.body.weight(.semibold)).foregroundStyle(Color.primary)
                            Spacer()
                            Tag.status(x.status)
                        }
                        Note(g.name + (g.modern.map { "（現代叫\($0)）" } ?? "") + "・" + x.line)
                    }
                }
                .padding(Theme.cardPad)
            }
        }
    }

    // MARK: 其他條文

    @ViewBuilder private var othersSection: some View {
        if report.others.isEmpty {
            Card { CardBlock(divider: false) { Note("這次的量測沒有對到其他條文。") } }
        }
        ForEach(report.others) { r in
            Card {
                CardBlock(divider: false) {
                    HStack(alignment: .top) {
                        Text(r.headline ?? r.part).font(.body.weight(.semibold))
                        Spacer()
                        if r.experimental == true { Tag(text: "實驗", color: Theme.bad, background: Theme.badSoft) }
                    }
                    Text(r.baihua)
                    if let yuanwen = r.yuanwen { Text(yuanwen).font(Theme.quote) }
                    if let note = r.note { Note(note) }
                    Note("\(r.source)・文獻 \(r.lit)")
                }
            }
        }
    }

    // MARK: 這次沒看的

    @ViewBuilder private var cannotSeeSection: some View {
        Card {
            ForEach(Array(rules.cannotSee.enumerated()), id: \.offset) { i, c in
                CardBlock(divider: i > 0) {
                    Text("\(c.plain)（古書叫「\(c.name)」）").font(.body.weight(.semibold))
                    Note(c.why)
                }
            }
        }
        let skipped: [(String, String)] =
            (m.hasHair ? [] : [("臉的上段", "沒有拉髮際線")])
            + (m.answers.browTattoo ? [("眉毛", "你勾了紋眉或修眉")] : [])
            + (m.answers.noseSurgery ? [("鼻子", "你勾了鼻子動過")] : [])
        if !skipped.isEmpty {
            SectionTitle("你選了不判的")
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
                Note("每一項都是比例，不受臉離鏡頭遠近影響；數字是 \(m.frames) 張畫面的中位數，「±」是四分位距。門檻是暫定值。")
            }
            ForEach(FeatureEngine.order, id: \.self) { key in
                if let stat = m.F[key], let def = rules.features[key] {
                    CardBlock {
                        HStack {
                            Text(def.name).font(.subheadline.weight(.semibold))
                            if stat.unstable { Tag(text: "不穩", color: Theme.bad, background: Theme.badSoft) }
                            Spacer()
                            Text("\(report.format(key, stat.v))　±\(report.format(key, stat.iqr))")
                                .font(.subheadline.monospacedDigit())
                        }
                        Note(def.formula)
                    }
                }
            }
            if let wx = report.wuxing {
                CardBlock {
                    Text("五行計分").font(.subheadline.weight(.semibold))
                    Text(wx.scores.map { "\($0.name) " + String(format: "%.2f", $0.score) }.joined(separator: "　"))
                        .font(.subheadline.monospacedDigit())
                    Note(rules.wuxing.note)
                }
            }
            CardBlock {
                Note("公式裡括號的數字是網頁版的點位編號；iOS 版在臉部網格和照片上取同一個位置。")
                Note(String(format: "平均光線亮度 %.0f／255・規則庫 %@", m.light, m.rulesVersion))
            }
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
                Text("完整版有三停、十二宮、其他古書條文，問古書 \(Paywall.includedQuestions) 題，再掃幾次都會出完整報告。")
                Note("一次付清，這支 Apple ID 之後都能用。")
            }
        }
    }
}

/// 合格／不合格／沒判的比例條
struct StatusBar: View {
    let pass: Int
    let fail: Int
    let unjudged: Int

    var body: some View {
        GeometryReader { geo in
            let total = max(1, pass + fail + unjudged)
            let gap = Theme.tight / 2
            let usable = geo.size.width - gap * 2
            HStack(spacing: gap) {
                Theme.ok.frame(width: usable * CGFloat(pass) / CGFloat(total))
                Theme.bad.frame(width: usable * CGFloat(fail) / CGFloat(total))
                Theme.tertiary.frame(width: usable * CGFloat(unjudged) / CGFloat(total))
            }
        }
        .frame(height: Theme.barHeight)
        .clipShape(Capsule())
        .accessibilityHidden(true)
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
