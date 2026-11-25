import SwiftUI

/// 從總覽往右推入的一頁，標題在視窗最上面那一列
struct ReportSectionView: View {
    @EnvironmentObject private var model: AppModel
    let section: ReportSection
    let report: Report

    private var rules: Rules { report.rules }
    private var m: Measurement { report.measurement }

    var body: some View {
        Page {
            VStack(alignment: .leading, spacing: Theme.group) {
                if model.isSample { Note("範例報告：數字是假的，不是你的臉。", warn: true).padding(.horizontal, Theme.tight) }
                if section.locked {
                    LockedSection(section: section)
                } else {
                    content
                }
            }
            .padding(.top, Theme.item)
        }
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .wuxing: wuxingSection
        case .others: othersSection
        case .cannotSee: cannotSeeSection
        case .diagram: diagramSection
        // 這三區在「面相」那一頁
        case .officials, .santing, .palaces: EmptyView()
        }
    }

    // MARK: 臉形

    @ViewBuilder private var wuxingSection: some View {
        if let wx = report.wuxing, let type = rules.wuxing.types[wx.host] {
            Card {
                wuxingHead(wx, type)
                if let rel = wx.relation, let guest = wx.guest {
                    CardBlock {
                        HStack(spacing: Theme.tight) {
                            Text("你也帶一點\(guest)形").font(.headline)
                            InfoButton(subject: "兩種形放在一起") { report.relationNote }
                        }
                        ForEach(rel.plain, id: \.self) { Text($0).fixedSize(horizontal: false, vertical: true) }
                    }
                }
            }
        } else {
            Card { CardBlock(divider: false) { Text("臉形這次沒看。") } }
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
                HStack(spacing: Theme.tight) {
                    Text(report.shapeName).foregroundStyle(Theme.secondary)
                    InfoButton(subject: "臉形") { report.wuxingNote }
                }
                Text(report.shapeGood)
                    .font(.title2.bold())
                    .foregroundStyle(Theme.accent)
                    .multilineTextAlignment(.center)
                Text("古書說，\(type.plainLine)")
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if wx.weak { Note("這一項不太穩，只當參考", warn: true) }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: 其他說法

    @ViewBuilder private var othersSection: some View {
        if report.others.isEmpty {
            Card { CardBlock(divider: false) { Text("這次沒有對上其他古書說法。") } }
        }
        ForEach(report.others) { r in
            Card {
                CardBlock(divider: false) {
                    HStack(spacing: Theme.item) {
                        Text(r.good ?? r.headline ?? "")
                            .font(r.good == nil ? .headline : .title3.weight(.bold))
                            .foregroundStyle(r.good == nil ? Color.primary : Theme.accent)
                            .fixedSize(horizontal: false, vertical: true)
                        InfoButton(subject: r.headline ?? "") { report.note(rule: r) }
                        Spacer(minLength: 0)
                    }
                    Text(r.goodLine ?? r.baihua).fixedSize(horizontal: false, vertical: true)
                    if r.experimental == true { Note("實驗項目，只當參考", warn: true) }
                }
            }
        }
    }

    // MARK: 這次沒看的

    @ViewBuilder private var cannotSeeSection: some View {
        Card {
            ForEach(Array(rules.cannotSee.enumerated()), id: \.offset) { i, c in
                CardBlock(divider: i > 0) { unseen(c.plain, c.why) }
            }
        }
        Card {
            ForEach(Array(report.unseenTopics.enumerated()), id: \.offset) { i, g in
                CardBlock(divider: i > 0) { unseen(g.topic, g.why ?? "") }
            }
        }
        if !skipped.isEmpty {
            SectionTitle("你選了不看的")
            Card {
                ForEach(Array(skipped.enumerated()), id: \.offset) { i, s in
                    CardBlock(divider: i > 0) { unseen(s.0, s.1) }
                }
            }
        }
    }

    @ViewBuilder private func unseen(_ name: String, _ why: String) -> some View {
        Text(name).font(.body.weight(.semibold))
        Note(why)
    }

    private var skipped: [(String, String)] {
        var out: [(String, String)] = []
        if !m.hasHair { out.append(("臉的上段", "沒有拉髮際線")) }
        if m.answers.browTattoo { out.append(("眉毛、兩眉中間", "你勾了紋眉或修眉")) }
        if m.answers.noseSurgery { out.append(("鼻子", "你勾了鼻子動過")) }
        return out
    }

    // MARK: 標註圖

    private var diagramSection: some View {
        VStack(alignment: .leading, spacing: Theme.group) {
            if !model.isSample, let photo = model.photo { AnnotatedPhoto(photo: photo) }
            Card {
                CardBlock(divider: false) { FaceDiagram(frame: model.isSample ? nil : model.capture?.best.frame) }
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
                Text("完整版有運勢、臉的三段、其他古書說法，問古書 \(Paywall.includedQuestions) 題，再掃幾次都會出完整報告。")
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
