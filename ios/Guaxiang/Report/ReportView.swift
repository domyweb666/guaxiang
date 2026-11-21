import SwiftUI

/// 報告。區塊順序和白話用語照網頁版：古書怎麼說你 → 臉形 → 五官 → 三停 → 十二宮 → 其他條文 → 標註圖 → 這次沒看的 → 數字明細
struct ReportView: View {
    @EnvironmentObject private var model: AppModel
    let report: Report
    @State private var showAsk = false
    @State private var showSettings = false
    @State private var confirmErase = false

    private var rules: Rules { report.rules }
    private var m: Measurement { report.measurement }

    var body: some View {
        Page {
            PageTitle(
                title: "你的面相",
                lead: "\(m.when.formatted(date: .numeric, time: .omitted))・從 \(m.frames) 張畫面量出來")
            summary
            if !m.gaps.isEmpty { gaps }
            Button("問古書一個問題") { showAsk = true }
                .buttonStyle(.primary)
            Note("填年紀、性別等簡介後，可以問錢財、感情、今年運勢，回答只根據這份報告。")

            wuxingSection
            officialsSection
            santingSection
            palacesSection
            othersSection

            SectionTitle("標註圖")
            Card {
                CardBlock(divider: false) {
                    FaceDiagram(frame: model.capture?.best.frame, hasHair: m.hasHair)
                    Note("橘色虛線是三段的分界線。這張圖只畫量測用到的點，不是照片；照片沒有存下來。")
                }
            }

            SectionTitle("這次沒看的")
            Card {
                DisclosureGroup("算命先生當面會看、相機拍不到的 \(rules.cannotSee.count) 項") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(rules.cannotSee, id: \.name) { c in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(c.plain)（古書叫「\(c.name)」）").font(.body.weight(.semibold))
                                Note(c.why)
                            }
                        }
                        if !m.hasHair { skipped("臉的上段", "沒有拉髮際線") }
                        if m.answers.browTattoo { skipped("眉毛", "你勾了紋眉或修眉") }
                        if m.answers.noseSurgery { skipped("鼻子", "你勾了鼻子動過") }
                    }
                    .padding(.top, 8)
                }
                .padding(Theme.cardPadding)
            }

            SectionTitle("數字明細")
            Card {
                DisclosureGroup("給想核對算法的人") { numbers.padding(.top, 8) }
                    .padding(Theme.cardPadding)
            }

            Button("再掃一次") { model.startOver() }
                .buttonStyle(.primary)
            ShareLink(item: exportJSON, preview: SharePreview("瓜相量測數字")) {
                Text("匯出數字（不含照片）")
            }
            .buttonStyle(.ghost)
            Button("設定") { showSettings = true }
                .buttonStyle(.ghost)
            Button("清除我的資料") { confirmErase = true }
                .buttonStyle(.ghost)
            Note("古書的說法沒有經過現代方法檢驗。這份報告是傳統文化解讀，不能用來判斷健康、替你或別人做重大決定。")
        }
        .sheet(isPresented: $showAsk) { AskView(report: report) }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .confirmationDialog("清除報告、簡介和問答紀錄？清掉就救不回來。", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("清除所有資料", role: .destructive) { model.eraseAll() }
        }
    }

    private func skipped(_ title: String, _ why: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.body.weight(.semibold))
            Note(why)
        }
    }

    // MARK: 古書怎麼說你

    private var summary: some View {
        Card {
            CardBlock(divider: false) {
                Text("古書怎麼說你").font(.title3.bold())
                ForEach(report.summaryPoints) { p in
                    (Text(p.title).bold() + Text(p.body.isEmpty ? "" : "：" + p.body))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                Note(
                    "這些都是古代相書的說法，沒有經過科學驗證。這次只看臉的形狀，古書還要看的眼神、氣色、聲音、頭形、身材、耳朵，這次都沒看（最下面有原因）。往下滑，每一項都有「怎麼看出來的」。"
                )
                .padding(.top, 6)
                if !report.unstableNames.isEmpty {
                    Note(
                        "有幾項在 \(m.frames) 張畫面之間差很多，結果只當參考：\(report.unstableNames.joined(separator: "、"))。",
                        warn: true)
                }
            }
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

    // MARK: 臉形

    @ViewBuilder private var wuxingSection: some View {
        let W = rules.wuxing
        if let wx = report.wuxing, let type = W.types[wx.host] {
            SectionTitle("臉形：\(wx.host)形人")
            Card {
                CardBlock(divider: false) {
                    VStack(spacing: 6) {
                        Note("古書把人分成金、木、水、火、土五種形")
                        Text("\(wx.host)形人").font(.system(size: 44, weight: .bold))
                        Note(
                            (wx.guest.map { "也帶一點\($0)形" } ?? "沒有明顯帶別的形")
                                + (wx.weak ? "・特徵不明顯，接近中間型" : ""))
                        Text(type.yuanwen).font(Theme.quote).padding(.top, 8)
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
            SectionTitle("臉形")
            Card { CardBlock(divider: false) { Note("量測資料不足，這次沒判臉形。") } }
        }
    }

    // MARK: 五官

    @ViewBuilder private var officialsSection: some View {
        SectionTitle("五官")
        Card {
            CardBlock(divider: false) {
                Text("\(report.count(.pass)) 個合格・\(report.count(.fail)) 個不合格・\(report.count(.unjudged)) 個沒判")
                    .font(.headline)
                Text(rules.wuxing.guan)
                Note("「沒判」的不能當成合格來算；「十年」也只是概數。點每一項看細節。")
            }
        }
        ForEach(report.officials) { x in
            Card {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 10) {
                        Note(x.official.governs)
                        if !x.rows.isEmpty {
                            Note("你的結果")
                            ForEach(Array(x.rows.enumerated()), id: \.offset) { _, row in
                                rowLine(row)
                            }
                        }
                        if let notMeasured = x.official.notMeasured {
                            Note(
                                "古書還要看、但相機量不到的：\(notMeasured.joined(separator: "、"))。"
                                    + (x.status == .pass ? "所以這裡的合格，只代表量得到的幾條合格。" : ""))
                        }
                        Note("古書的合格標準")
                        Text(x.official.baihua)
                        Note("\(x.official.source)・文獻 \(x.official.lit)")
                        if x.rows.contains(where: { $0.result.x != nil }) {
                            Note(
                                "看數字："
                                    + x.rows.map(numberLine).joined(separator: "；"))
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Tag.status(x.status)
                            Text(x.official.plain).font(.body.weight(.semibold)).foregroundStyle(Color.primary)
                        }
                        Note(Report.officialLine(x))
                    }
                }
                .padding(Theme.cardPadding)
            }
        }
    }

    private func numberLine(_ row: ConditionRow) -> String {
        let key = row.condition.feature ?? ""
        let value = report.format(key, row.result.x)
        let standard = report.format(key, row.result.t)
        return "\(row.condition.label ?? "") \(value)（標準 \(row.condition.op ?? "") \(standard)）"
    }

    @ViewBuilder private func rowLine(_ row: ConditionRow) -> some View {
        if let pass = row.result.pass {
            VStack(alignment: .leading, spacing: 2) {
                Text((pass ? "✓ " : "✗ ") + ((pass ? row.condition.yes : row.condition.no) ?? ""))
                if row.result.edge { Note("剛好在標準線附近，換個光線再掃可能會變", warn: true) }
                if row.result.unstable { Note("\(m.frames) 張畫面之間差很多，只當參考", warn: true) }
            }
        } else {
            Note("\(row.condition.label ?? "")：這次量不到")
        }
    }

    // MARK: 三停

    @ViewBuilder private var santingSection: some View {
        SectionTitle("臉的三段（三停）")
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
        SectionTitle("十二宮：人生十二件事")
        Card { CardBlock(divider: false) { Text(rules.palacesNote) } }
        ForEach(report.palaces) { x in
            let g = x.palace
            Card {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 10) {
                        Note("在臉上哪裡")
                        Text(g.place)
                        if g.measure != nil {
                            Note("你的結果")
                            Text((x.status == .unjudged ? "" : x.status == .pass ? "✓ " : "✗ ") + x.line)
                            if x.edge { Note("剛好在標準線附近，換個光線再掃可能會變", warn: true) }
                            if x.unstable { Note("\(m.frames) 張畫面之間差很多，只當參考", warn: true) }
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
                    .padding(.top, 8)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Tag.status(x.status)
                            Text(g.topic).font(.body.weight(.semibold)).foregroundStyle(Color.primary)
                            Note(g.name + (g.modern.map { "（現代叫\($0)）" } ?? ""))
                        }
                        Note(x.line)
                    }
                }
                .padding(Theme.cardPadding)
            }
        }
    }

    // MARK: 其他條文

    @ViewBuilder private var othersSection: some View {
        if !report.others.isEmpty {
            SectionTitle("其他古書條文")
            ForEach(report.others) { r in
                Card {
                    CardBlock(divider: false) {
                        HStack(alignment: .top) {
                            Text(r.headline ?? r.part).font(.body.weight(.semibold))
                            if r.experimental == true { Tag(text: "實驗", color: Theme.accent) }
                        }
                        Text(r.baihua)
                        if let yuanwen = r.yuanwen { Text(yuanwen).font(Theme.quote) }
                        if let note = r.note { Note(note) }
                        Note("\(r.source)・文獻 \(r.lit)")
                    }
                }
            }
        }
    }

    // MARK: 數字明細

    private var numbers: some View {
        VStack(alignment: .leading, spacing: 10) {
            Note("每一項都是比例，不受臉離鏡頭遠近影響；數字是 \(m.frames) 張畫面的中位數，「波動」是四分位距。門檻是暫定值。")
            ForEach(FeatureEngine.order, id: \.self) { key in
                if let stat = m.F[key], let def = rules.features[key] {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(def.name).font(.subheadline.weight(.semibold))
                            if stat.unstable { Tag(text: "不穩", color: Theme.accent) }
                            Spacer()
                            Text("\(report.format(key, stat.v))　±\(report.format(key, stat.iqr))")
                                .font(.subheadline.monospacedDigit())
                        }
                        Note(def.formula)
                    }
                }
            }
            if let wx = report.wuxing {
                Text("五行計分").font(.subheadline.weight(.semibold))
                Text(wx.scores.map { "\($0.name) " + String(format: "%.2f", $0.score) }.joined(separator: "　"))
                    .font(.subheadline.monospacedDigit())
                Note(rules.wuxing.note)
            }
            Note("公式裡括號的數字是網頁版的點位編號；iOS 版用的是同一個位置的 ARKit 網格頂點。")
            Note(String(format: "平均光線亮度 %.0f／255・規則庫 %@", m.light, m.rulesVersion))
        }
    }

    private var exportJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(m) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

/// 標註圖：把量測用到的點畫成線條。沒有這次掃描的點（例如打開的是上一次的報告）就說明原因。
struct FaceDiagram: View {
    let frame: FaceFrame?
    let hasHair: Bool

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
                        path, with: .color(.orange), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                }
            }
            .aspectRatio(box.width / box.height, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("量測點的線條圖")
        } else {
            Note("這是之前存下來的報告，只存了數字，沒有存臉上的點，所以畫不出標註圖。再掃一次就會有。")
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
