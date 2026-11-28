import SwiftUI
import UIKit
import VeggieKit

// 確認標註（2026-11-28 多米：標註圖在 AI 拍完檢驗完以後，讓人可以再手動拉一下位置，怕標錯）。
// 掃完先到這一頁：照片上畫出會影響量測的點和髮際線。點標歪了可以拖回去，只能在原位附近移（ManualMarks.reachInEyes）。
// 沒問題直接按「看報告」。換算在 Engine/ManualMarks.swift，這個檔只管畫面。
//
// 畫面分四塊，換樣式時各自換掉就好：
//   ConfirmMarksView：上面一句說明、底部兩顆按鈕
//   MarkBoard：照片、點、髮際線、放大鏡，和唯一的一個手勢
//   NudgeBar：選到哪一個、上下左右微調鈕、還原
//   MarkPaint：照片和線怎麼畫

// MARK: 這一頁的尺寸。只有這一頁用，寫在這裡，不動共用的 Theme.swift

extension Theme {
    /// 照片上的點畫多大
    static let pinDot: CGFloat = 14
    /// 選到的點放大幾倍
    static let pinSelectedScale: CGFloat = 1.35
    /// 點的白框
    static let pinBorder: CGFloat = 2
    /// 手指按下去離點多近算按到（半徑）。比觸控區 44 的一半再多一點
    static let pinReach: CGFloat = 26
    /// 調過的點，原位畫一個小空心圈
    static let originDot: CGFloat = 8
    /// 手指動超過這麼多才算拖，沒超過算點一下
    static let tapSlop: CGFloat = 6
    /// 放大鏡多大、放大幾倍、中心在手指上方多遠
    static let loupeSize: CGFloat = 112
    static let loupeZoom: CGFloat = 2.2
    static let loupeLift: CGFloat = 96
    /// 輔助字級時整頁可以捲，照片固定這麼高
    static let boardScrollHeight: CGFloat = 440
    /// 照片上的輪廓線
    static let outlineWidth: CGFloat = 1.5
    /// 髮際線的粗細
    static let hairStroke: CGFloat = 3
    /// 可移範圍那一圈的底色和線
    static let ringFill: Double = 0.14
    static let ringStroke: Double = 0.85
    /// 微調鈕按一下移多少：照片上要看的範圍高度的 0.6%（畫面上約 2–3 點）
    static let nudgeFraction: Double = 0.006
    /// 旁白一次滑動移幾步（看不到畫面，一步太小）
    static let voiceOverSteps: Double = 4
}

// MARK: 頁面

/// 選著的是哪一個
enum MarkTarget: Hashable {
    case hairline
    case point(LM)
}

struct ConfirmMarksView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var setup: MarkSetup? = nil
    @State private var draft = MarkDraft(lineY: 0.25, edits: MarkEdits(), selected: nil)

    var body: some View {
        VStack(spacing: 0) {
            // 平常不捲：照片在捲動區裡，上下拖會被捲動搶走。輔助字級放不下才捲，照片固定高度
            if typeSize.isAccessibilitySize {
                ScrollView { page(scrolls: true) }
            } else {
                page(scrolls: false)
            }
            BottomBar {
                Button("看報告") { model.finish(hairRatio: ratio(), hairY: draft.lineY, edits: draft.edits) }
                    .buttonStyle(.primary)
                Button("我有瀏海，跳過（三段不看）") { model.finish(hairRatio: nil, edits: draft.edits) }
                    .buttonStyle(.textOnly)
            }
        }
        .background(Theme.canvas.ignoresSafeArea())
        // 返回會回到掃描、重新收畫面，所以這一頁不給返回
        .navigationBarBackButtonHidden(true)
        .onAppear(perform: prepare)
    }

    private func page(scrolls: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.group) {
            PageTitle(title: "確認標註", lead: "點標歪了就拖回去，紅線放在額頭長頭髮的地方。", pushed: true)
            if let setup {
                MarkBoard(setup: setup, draft: $draft)
                    .frame(height: scrolls ? Theme.boardScrollHeight : nil)
                    .frame(maxHeight: scrolls ? nil : CGFloat.infinity)
                NudgeBar(setup: setup, draft: $draft)
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, Theme.screenMargin)
        .padding(.bottom, Theme.item)
    }

    private func prepare() {
        guard setup == nil, let best = model.capture?.best, let ready = MarkSetup(best) else { return }
        setup = ready
        draft = MarkDraft(lineY: ready.startLine, edits: MarkEdits(reach: ready.reach), selected: nil)
    }

    /// 髮際線換成「髮際到眉心 ÷ 臉寬」。眉心、下巴調過的話用調過的位置（照片上和臉平面上都是）
    private func ratio() -> Double? {
        guard let setup, let g = draft.edits.photo(.glabella, original: setup.marks[.glabella]),
            let c = draft.edits.photo(.chin, original: setup.marks[.chin]),
            let fg = draft.edits.point(.glabella, in: setup.frame), let fc = draft.edits.point(.chin, in: setup.frame),
            let cheekR = setup.frame[.cheekR], let cheekL = setup.frame[.cheekL]
        else { return nil }
        let w = Double(setup.image.size.width), h = Double(setup.image.size.height)
        return FeatureEngine.hairRatio(
            lineY: draft.lineY * h, glabella: Pt(x: g.x * w, y: g.y * h), chin: Pt(x: c.x * w, y: c.y * h),
            faceGlabellaToChin: Geometry.dist(fg, fc), faceWidth: Geometry.dist(cheekR, cheekL))
    }
}

// MARK: 狀態

/// 這一頁開始時就定好、之後不變的東西
struct MarkSetup {
    let image: UIImage
    let marks: PhotoMarks
    let frame: FaceFrame
    let mapper: PlaneMapper?
    /// 每一點最多能從原位移多遠（臉平面的單位）。0 就是這次不給拖點
    let reach: Double
    /// 可以拖的點原本在照片上的位置（0–1）。找不到原位的點不放
    let origin: [LM: UV]
    /// 照片上要看的範圍（像素）：整張臉，加上眉心往上一段，髮際線拉得到
    let focus: CGRect
    /// 髮際線一開始放哪
    let startLine: Double

    static let lineMin = 0.02
    static let lineMax = 0.98
    /// 可移範圍那一圈取幾個方向
    static let ringSteps = 16

    init?(_ best: BestShot) {
        guard let image = best.image, image.size.width >= 1, image.size.height >= 1, let g = best.glabella,
            let c = best.chin
        else { return nil }
        self.image = image
        marks = best.marks
        frame = best.frame
        mapper = best.mesh
        let reach = ManualMarks.reach(best.frame) ?? 0
        self.reach = reach
        var origin: [LM: UV] = [:]
        if let mapper = best.mesh, reach > 0 {
            for lm in ManualMarks.draggable {
                origin[lm] = ManualMarks.origin(
                    lm, frame: best.frame, marked: best.marks[lm], outline: best.marks.outline(for: lm),
                    mapper: mapper, reach: reach)
            }
        }
        self.origin = origin
        // 預設位置：眉心往上，約一個中停的長度（跟原本拉髮際線那一頁一樣）
        let line = best.subnasale.map { g.y - ($0.y - g.y) * 0.95 } ?? g.y - 0.15
        let start = min(Self.lineMax, max(Self.lineMin, line))
        startLine = start
        focus = Self.makeFocus(best.marks, image: image.size, glabella: g, chin: c, line: start)
    }

    /// 髮際線能放的高度：照片上要看的範圍以內
    var lineRange: ClosedRange<Double> {
        let top = max(Self.lineMin, Double(focus.minY / image.size.height))
        let bottom = min(Self.lineMax, Double(focus.maxY / image.size.height))
        return top <= bottom ? top...bottom : Self.lineMin...Self.lineMax
    }

    /// 包住所有標註和髮際線的範圍，眉心往上多留一個「眉心到下巴」那麼長，額頭再高也拉得到
    static func makeFocus(_ marks: PhotoMarks, image: CGSize, glabella g: UV, chin c: UV, line: Double) -> CGRect {
        let all = marks.all + [g, c]
        let span = max(0.05, c.y - g.y)
        guard var minX = all.map(\.x).min(), var maxX = all.map(\.x).max(), let lowY = all.map(\.y).min(),
            let highY = all.map(\.y).max()
        else { return CGRect(origin: .zero, size: image) }
        let padX = (maxX - minX) * 0.12
        minX = max(0, minX - padX)
        maxX = min(1, maxX + padX)
        let minY = max(0, min(lowY, g.y - span, line))
        let maxY = min(1, max(highY, c.y + span * 0.12))
        guard maxX > minX, maxY > minY else { return CGRect(origin: .zero, size: image) }
        return CGRect(
            x: CGFloat(minX) * image.width, y: CGFloat(minY) * image.height, width: CGFloat(maxX - minX) * image.width,
            height: CGFloat(maxY - minY) * image.height)
    }

    /// 這一點能移到的範圍，照片上的一圈
    func ring(_ lm: LM) -> [UV] {
        guard let from = origin[lm], let mapper, reach > 0 else { return [] }
        let far = Double(focus.height) * 0.5
        let w = Double(image.size.width), h = Double(image.size.height)
        return (0..<Self.ringSteps).compactMap { i in
            let a = Double(i) / Double(Self.ringSteps) * 2 * .pi
            let to = UV(x: from.x + cos(a) * far / w, y: from.y + sin(a) * far / h)
            return ManualMarks.place(mapper, from: from, to: to, reach: reach)?.uv
        }
    }
}

/// 使用者改到哪裡
struct MarkDraft {
    /// 髮際線的高度，佔照片高度的比例（0 在最上面）
    var lineY: Double
    var edits: MarkEdits
    var selected: MarkTarget?

    /// 這一點現在在照片上的哪裡
    func spot(_ lm: LM, _ setup: MarkSetup) -> UV? {
        guard let origin = setup.origin[lm] else { return nil }
        return edits.photo(lm, original: origin)
    }

    /// 把一點移到照片上的 uv，超出可移範圍會停在邊上。回傳有沒有被擋住
    @discardableResult
    mutating func move(_ lm: LM, to uv: UV, _ setup: MarkSetup) -> Bool {
        guard let from = setup.origin[lm], let mapper = setup.mapper,
            let placed = ManualMarks.place(mapper, from: from, to: uv, reach: setup.reach)
        else { return false }
        edits.set(lm, from: from, to: placed.uv, delta: placed.delta)
        return placed.limited
    }

    mutating func moveLine(to y: Double, _ setup: MarkSetup) {
        let range = setup.lineRange
        lineY = min(range.upperBound, max(range.lowerBound, y))
    }

    /// 微調鈕和旁白：往畫面上的左右上下移幾小步。照片跟照鏡子一樣左右相反，畫面往左是照片的 x 變大
    @discardableResult
    mutating func nudge(_ target: MarkTarget, dx: Double, dy: Double, _ setup: MarkSetup) -> Bool {
        let stepY = Double(setup.focus.height / setup.image.size.height) * Theme.nudgeFraction
        let stepX = stepY * Double(setup.image.size.height / setup.image.size.width)
        switch target {
        case .hairline:
            moveLine(to: lineY + dy * stepY, setup)
            return false
        case .point(let lm):
            guard let now = spot(lm, setup) else { return false }
            return move(lm, to: UV(x: now.x - dx * stepX, y: now.y + dy * stepY), setup)
        }
    }
}

/// 照片的哪一塊畫在畫面上、兩邊怎麼換算。跟自拍一樣左右相反（報告的標註圖也是）
struct PhotoView {
    /// 畫面多大
    let size: CGSize
    /// 照片多大（像素）
    let image: CGSize
    /// 照片上畫出來的那一塊（像素），長寬比跟畫面一樣，可能超出照片（超出的地方是底色）
    let rect: CGRect
    /// 照片一個像素在畫面上多大
    let scale: CGFloat

    init(focus: CGRect, image: CGSize, size: CGSize) {
        self.size = size
        self.image = image
        guard size.width >= 1, size.height >= 1, focus.width >= 1, focus.height >= 1 else {
            rect = focus
            scale = 1
            return
        }
        let s = min(size.width / focus.width, size.height / focus.height)
        let w = size.width / s, h = size.height / s
        // 照片夠大就往裡推，邊上不留空；照片不夠大就置中
        let x = w >= image.width ? (image.width - w) / 2 : min(max(0, focus.midX - w / 2), image.width - w)
        let y = h >= image.height ? (image.height - h) / 2 : min(max(0, focus.midY - h / 2), image.height - h)
        rect = CGRect(x: x, y: y, width: w, height: h)
        scale = s
    }

    /// 照片上的位置（0–1）→ 畫面上的位置。照片的右邊畫在左邊
    func point(_ uv: UV) -> CGPoint {
        CGPoint(
            x: size.width - (CGFloat(uv.x) * image.width - rect.minX) * scale,
            y: (CGFloat(uv.y) * image.height - rect.minY) * scale)
    }

    /// 畫面上的位置 → 照片上的位置（0–1）
    func uv(_ p: CGPoint) -> UV {
        UV(
            x: Double((rect.minX + (size.width - p.x) / scale) / max(1, image.width)),
            y: Double((rect.minY + p.y / scale) / max(1, image.height)))
    }

    func clamp(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(0, p.x), size.width), y: min(max(0, p.y), size.height))
    }
}

// MARK: 照片和手勢

/// 手指按著的這一次
private struct Grab {
    /// 按下去的位置。換成新的一次觸碰時，這個會不一樣
    var start: CGPoint
    var target: MarkTarget?
    /// 點的位置減手指的位置：拖的時候點維持在原本的相對位置，不跳到手指底下
    var offset: CGSize
    /// 按下去之前的樣子。點一下（沒拖）時回到這裡，手指抖的那一點點不算
    var before: MarkDraft
    var finger: CGPoint
    var moved = false
    var limited = false
}

/// 照片、點、髮際線、放大鏡。只掛一個 DragGesture(minimumDistance: 0)，自己分點一下和拖
/// （onTapGesture 跟 DragGesture 掛在一起，拖要走很遠才成立）
private struct MarkBoard: View {
    let setup: MarkSetup
    @Binding var draft: MarkDraft
    @State private var grab: Grab? = nil
    /// 每一點的可移範圍，第一次選到時算，之後重用（原位不會變）
    @State private var rings: [LM: [UV]] = [:]

    var body: some View {
        GeometryReader { geo in
            let view = PhotoView(focus: setup.focus, image: setup.image.size, size: geo.size)
            let marks = setup.marks.applying(draft.edits)
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    MarkPaint.photo(context, view, setup.image)
                    MarkPaint.outlines(context, view, marks)
                    if case .point(let lm) = draft.selected, let ring = rings[lm] { MarkPaint.ring(context, view, ring) }
                    MarkPaint.origins(context, view, draft.edits)
                    MarkPaint.hairline(context, view, draft.lineY)
                }
                .accessibilityHidden(true)
                hairTag(view)
                ForEach(ManualMarks.draggable, id: \.self) { lm in
                    if let uv = draft.spot(lm, setup) { pin(lm, at: view.point(uv)) }
                }
                if let grab, grab.moved, let target = grab.target {
                    loupe(target, grab: grab, view: view, marks: marks)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(drag(view))
        }
        .background(Theme.fill)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .onChange(of: draft.selected) { _, selected in
            guard case .point(let lm) = selected, rings[lm] == nil else { return }
            rings[lm] = setup.ring(lm)
        }
    }

    // MARK: 手勢

    private func drag(_ view: PhotoView) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if grab == nil || grab?.start != value.startLocation {
                    grab = begin(at: value.startLocation, view)
                }
                guard var g = grab, let target = g.target else { return }
                if !g.moved, hypot(value.translation.width, value.translation.height) >= Theme.tapSlop {
                    g.moved = true
                }
                g.finger = value.location
                let p = view.clamp(CGPoint(x: value.location.x + g.offset.width, y: value.location.y + g.offset.height))
                let limited = place(target, at: p, view)
                if limited, !g.limited, VeggieHaptics.isEnabled {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                g.limited = limited
                grab = g
            }
            .onEnded { _ in
                guard let g = grab else { return }
                grab = nil
                guard let target = g.target else {
                    // 點到空白的地方：取消選取
                    draft.selected = nil
                    return
                }
                if g.moved {
                    draft.selected = target
                } else {
                    // 點一下：回到按下去之前（手指抖的不算），再點一次已經選著的就取消
                    let wasSelected = g.before.selected == target
                    draft = g.before
                    draft.selected = wasSelected ? nil : target
                }
            }
    }

    /// 按下去的地方離哪個點或髮際線最近（要在按得到的距離內）
    private func begin(at p: CGPoint, _ view: PhotoView) -> Grab {
        var best: (target: MarkTarget, d: CGFloat, at: CGPoint)?
        for lm in ManualMarks.draggable {
            guard let uv = draft.spot(lm, setup) else { continue }
            let q = view.point(uv)
            let d = hypot(q.x - p.x, q.y - p.y)
            if d <= Theme.pinReach, best == nil || d < best!.d { best = (.point(lm), d, q) }
        }
        let lineY = view.point(UV(x: 0, y: draft.lineY)).y
        let toLine = abs(lineY - p.y)
        if toLine <= Theme.touch / 2, best == nil || toLine < best!.d {
            best = (.hairline, toLine, CGPoint(x: p.x, y: lineY))
        }
        let before = draft
        guard let best else { return Grab(start: p, target: nil, offset: .zero, before: before, finger: p) }
        if VeggieHaptics.isEnabled { UISelectionFeedbackGenerator().selectionChanged() }
        // 一按下去就選它：可移範圍那一圈拖的時候就看得到
        draft.selected = best.target
        return Grab(
            start: p, target: best.target, offset: CGSize(width: best.at.x - p.x, height: best.at.y - p.y),
            before: before, finger: p)
    }

    /// 移到畫面上的 p。回傳有沒有被可移範圍擋住
    private func place(_ target: MarkTarget, at p: CGPoint, _ view: PhotoView) -> Bool {
        switch target {
        case .hairline:
            draft.moveLine(to: view.uv(p).y, setup)
            return false
        case .point(let lm):
            return draft.move(lm, to: view.uv(p), setup)
        }
    }

    private func nudge(_ target: MarkTarget, dx: Double, dy: Double) {
        draft.nudge(target, dx: dx * Theme.voiceOverSteps, dy: dy * Theme.voiceOverSteps, setup)
    }

    // MARK: 點、髮際線的標籤、放大鏡

    private func pin(_ lm: LM, at p: CGPoint) -> some View {
        let selected = draft.selected == .point(lm)
        let adjusted = draft.edits.moves[lm] != nil
        return Circle()
            .fill(MarkPaint.color(lm))
            .overlay { Circle().strokeBorder(Color.white, lineWidth: Theme.pinBorder) }
            .frame(width: Theme.pinDot, height: Theme.pinDot)
            .scaleEffect(selected ? Theme.pinSelectedScale : 1)
            .shadow(color: Theme.markShade, radius: Theme.hairline)
            // 旁白的框和手指按得到的範圍一樣大。旁白的設定要寫在 position 前面，不然框會變成整張照片
            .frame(width: Theme.touch, height: Theme.touch)
            .accessibilityElement()
            .accessibilityLabel(ManualMarks.name(lm))
            .accessibilityValue(adjusted ? "手動調過" : "原位")
            .accessibilityHint("上下滑動調高低，左右移和還原在動作裡")
            .accessibilityAdjustableAction { direction in
                nudge(.point(lm), dx: 0, dy: direction == .increment ? -1 : 1)
            }
            .accessibilityAction(named: "往左移") { nudge(.point(lm), dx: -1, dy: 0) }
            .accessibilityAction(named: "往右移") { nudge(.point(lm), dx: 1, dy: 0) }
            .accessibilityAction(named: "還原") { draft.edits.reset(lm) }
            .position(p)
    }

    /// 「髮際」小標籤，貼在線的右端上面；線太靠上就放到線下面
    private func hairTag(_ view: PhotoView) -> some View {
        let y = view.point(UV(x: 0, y: draft.lineY)).y
        let above = y > Theme.touch
        let selected = draft.selected == .hairline
        return Color.clear
            .frame(height: 0)
            .overlay(alignment: above ? .bottomTrailing : .topTrailing) {
                Text("髮際")
                    .font(.footnote.weight(.semibold))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, Theme.group)
                    .padding(.vertical, Theme.tight)
                    .background(Theme.accent)
                    .clipShape(Capsule())
                    .overlay { Capsule().strokeBorder(Color.white, lineWidth: selected ? Theme.pinBorder : 0) }
                    .fixedSize()
                    .padding(.trailing, Theme.group)
                    .padding(above ? .bottom : .top, Theme.tight)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("髮際線")
                    .accessibilityHint("上下滑動移動紅線")
                    .accessibilityAdjustableAction { direction in
                        nudge(.hairline, dx: 0, dy: direction == .increment ? -1 : 1)
                    }
            }
            .offset(y: y)
    }

    /// 手指會蓋住點：拖的時候在手指上方放一個放大鏡，正中間就是點現在的位置
    private func loupe(_ target: MarkTarget, grab: Grab, view: PhotoView, marks: PhotoMarks) -> some View {
        let at: CGPoint
        let color: Color
        switch target {
        case .hairline:
            at = CGPoint(x: view.clamp(grab.finger).x, y: view.point(UV(x: 0, y: draft.lineY)).y)
            color = Theme.accent
        case .point(let lm):
            at = draft.spot(lm, setup).map { view.point($0) } ?? grab.finger
            color = MarkPaint.color(lm)
        }
        let r = Theme.loupeSize / 2
        let up = at.y - Theme.loupeLift - r >= 0
        let center = CGPoint(
            x: min(max(r, at.x), max(r, view.size.width - r)), y: up ? at.y - Theme.loupeLift : at.y + Theme.loupeLift)
        return Canvas { context, size in
            var zoomed = context
            let z = Theme.loupeZoom
            zoomed.translateBy(x: size.width / 2 - at.x * z, y: size.height / 2 - at.y * z)
            zoomed.scaleBy(x: z, y: z)
            MarkPaint.photo(zoomed, view, setup.image)
            MarkPaint.outlines(zoomed, view, marks)
            MarkPaint.hairline(zoomed, view, draft.lineY)
            MarkPaint.cross(context, CGPoint(x: size.width / 2, y: size.height / 2), color)
        }
        .frame(width: Theme.loupeSize, height: Theme.loupeSize)
        .background(Theme.fill)
        .clipShape(Circle())
        .overlay { Circle().strokeBorder(Color.white, lineWidth: Theme.pinBorder) }
        .shadow(color: Theme.markShade, radius: Theme.tight)
        .position(center)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: 微調列

/// 照片下面一列：現在選著哪一個、上下左右微調鈕（手勢只當捷徑，準則 3-21）、還原
private struct NudgeBar: View {
    let setup: MarkSetup
    @Binding var draft: MarkDraft

    var body: some View {
        // 放得下就排一列；字放大放不下，按鈕換到下一行
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.item) {
                caption
                Spacer(minLength: 0)
                buttons
            }
            VStack(alignment: .leading, spacing: Theme.item) {
                caption
                buttons
            }
        }
        .frame(minHeight: Theme.touch)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: Theme.tight / 2) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(detail).font(.footnote).foregroundStyle(Theme.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var title: String {
        switch draft.selected {
        case .some(.hairline): return "髮際線"
        case .some(.point(let lm)): return ManualMarks.name(lm)
        case .none: return setup.origin.isEmpty ? "拖紅線到髮際" : "點一下要調的點，或直接拖"
        }
    }

    private var detail: String {
        let count = draft.edits.adjusted.count
        switch draft.selected {
        case .some(.hairline): return "上下拖，或用旁邊的按鈕微調"
        case .some(.point(let lm)):
            return draft.edits.moves[lm] != nil ? "調過了。只能在原位附近移" : "只能在原位附近移"
        case .none:
            return count > 0 ? "調了 \(count) 個點" : "沒問題就直接看報告"
        }
    }

    @ViewBuilder private var buttons: some View {
        HStack(spacing: Theme.item) {
            switch draft.selected {
            case .some(.hairline):
                nudge("chevron.up", "往上移", .hairline, dx: 0, dy: -1)
                nudge("chevron.down", "往下移", .hairline, dx: 0, dy: 1)
            case .some(.point(let lm)):
                nudge("chevron.left", "往左移", .point(lm), dx: -1, dy: 0)
                nudge("chevron.up", "往上移", .point(lm), dx: 0, dy: -1)
                nudge("chevron.down", "往下移", .point(lm), dx: 0, dy: 1)
                nudge("chevron.right", "往右移", .point(lm), dx: 1, dy: 0)
                if draft.edits.moves[lm] != nil {
                    Button("還原") { draft.edits.reset(lm) }
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: Theme.touch, minHeight: Theme.touch)
                }
            case .none:
                EmptyView()
            }
        }
    }

    private func nudge(_ icon: String, _ label: String, _ target: MarkTarget, dx: Double, dy: Double) -> some View {
        Button {
            let limited = draft.nudge(target, dx: dx, dy: dy, setup)
            if VeggieHaptics.isEnabled {
                if limited {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } else {
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }
        } label: {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.primary)
                .frame(width: Theme.rowHeight, height: Theme.touch)
                .background(Theme.fill)
                .clipShape(RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }
}

// MARK: 畫圖

private enum MarkPaint {
    static func color(_ lm: LM) -> Color {
        switch ManualMarks.source(lm) {
        case .brow: return Theme.markBrow
        case .eye: return Theme.markEye
        case .lips: return Theme.markMouth
        case .mesh: return Theme.markLine
        }
    }

    /// 照片，左右相反
    static func photo(_ context: GraphicsContext, _ view: PhotoView, _ image: UIImage) {
        var flipped = context
        flipped.translateBy(x: view.size.width, y: 0)
        flipped.scaleBy(x: -1, y: 1)
        let s = view.scale
        flipped.draw(
            Image(uiImage: image),
            in: CGRect(
                x: -view.rect.minX * s, y: -view.rect.minY * s, width: view.image.width * s,
                height: view.image.height * s))
    }

    /// Vision 找到的眉毛、眼睛、嘴唇輪廓（細線），讓人看得出點是貼著什麼
    static func outlines(_ context: GraphicsContext, _ view: PhotoView, _ marks: PhotoMarks) {
        for brow in marks.brows { line(context, brow.map { view.point($0) }, Theme.markBrow, closed: false) }
        for eye in marks.eyes { line(context, eye.map { view.point($0) }, Theme.markEye, closed: true) }
        line(context, marks.lips.map { view.point($0) }, Theme.markMouth, closed: true)
    }

    static func hairline(_ context: GraphicsContext, _ view: PhotoView, _ y: Double) {
        let py = view.point(UV(x: 0, y: y)).y
        context.fill(
            Path(CGRect(x: 0, y: py - Theme.hairStroke / 2, width: view.size.width, height: Theme.hairStroke)),
            with: .color(Theme.accent))
    }

    /// 調過的點：原位畫小空心圈，虛線連到現在的位置
    static func origins(_ context: GraphicsContext, _ view: PhotoView, _ edits: MarkEdits) {
        for move in edits.moves.values {
            let a = view.point(move.from), b = view.point(move.to)
            var path = Path()
            path.move(to: a)
            path.addLine(to: b)
            context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: Theme.hairline, dash: Theme.verdictDash))
            let r = Theme.originDot / 2
            context.stroke(
                Path(ellipseIn: CGRect(x: a.x - r, y: a.y - r, width: r * 2, height: r * 2)), with: .color(.white),
                lineWidth: Theme.hairline)
        }
    }

    /// 選到的點能移到哪裡
    static func ring(_ context: GraphicsContext, _ view: PhotoView, _ ring: [UV]) {
        guard ring.count > 2, let first = ring.first else { return }
        var path = Path()
        path.move(to: view.point(first))
        for uv in ring.dropFirst() { path.addLine(to: view.point(uv)) }
        path.closeSubpath()
        context.fill(path, with: .color(Color.white.opacity(Theme.ringFill)))
        context.stroke(
            path, with: .color(Color.white.opacity(Theme.ringStroke)),
            style: StrokeStyle(lineWidth: Theme.hairline, dash: Theme.cardDash))
    }

    /// 放大鏡正中間的十字
    static func cross(_ context: GraphicsContext, _ c: CGPoint, _ color: Color) {
        let r = Theme.pinDot
        var path = Path()
        path.move(to: CGPoint(x: c.x - r, y: c.y))
        path.addLine(to: CGPoint(x: c.x + r, y: c.y))
        path.move(to: CGPoint(x: c.x, y: c.y - r))
        path.addLine(to: CGPoint(x: c.x, y: c.y + r))
        context.stroke(path, with: .color(.white), lineWidth: Theme.markWidth + Theme.hairline)
        context.stroke(path, with: .color(color), lineWidth: Theme.hairline)
    }

    private static func line(_ context: GraphicsContext, _ points: [CGPoint], _ color: Color, closed: Bool) {
        guard points.count > 1, let first = points.first else { return }
        var path = Path()
        path.move(to: first)
        for p in points.dropFirst() { path.addLine(to: p) }
        if closed { path.closeSubpath() }
        context.stroke(
            path, with: .color(color),
            style: StrokeStyle(lineWidth: Theme.outlineWidth, lineCap: .round, lineJoin: .round))
    }
}
