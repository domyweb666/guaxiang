import SwiftUI
import UIKit

/// 這次掃的照片，疊上量測用到的位置。跟自拍一樣左右相反（跟網頁版的標註圖相同）。
/// 兩種用法：報告上半部滿版（給 fill），和標註圖那一頁的卡片（不給 fill，底下有圖例）。
struct AnnotatedPhoto: View {
    /// 現在要亮哪一區的標註
    enum Mode: Equatable {
        case overview, officials, santing, palaces
    }

    /// 滿版要多大、上下各有多少會被蓋住
    struct Fill: Equatable {
        var size: CGSize
        /// 返回鈕和瀏海那一段
        var top: CGFloat
        /// 從螢幕底往上，被視窗蓋住的那一段（含貼著視窗上緣留的一點空）
        var bottom: CGFloat
        /// 從最上面算起，照片本身至少要鋪到這裡。再往下照片不夠長，就用最後一排的顏色接到底
        var cover: CGFloat
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let photo: FacePhoto
    var mode: Mode = .overview
    var palaces: [PalaceResult] = []
    var fill: Fill?
    /// 標籤畫在 Canvas 裡，字的大小自己算好再給，不靠 Canvas 解析字型時看不看字級
    @ScaledMetric(relativeTo: .caption) var tagText: CGFloat = Theme.markText

    var body: some View {
        if let fill {
            layers(Self.crop(photo, fill: fill))
                .frame(width: fill.size.width, height: fill.size.height)
                .clipped()
        } else {
            card
        }
    }

    private var card: some View {
        let crop = Self.crop(photo)
        return VStack(alignment: .leading, spacing: 0) {
            layers(crop)
                .aspectRatio(crop.width / max(1, crop.height), contentMode: .fit)
                .frame(maxWidth: .infinity)
            legend
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    /// 照片一層、每一區的標註各一層，換區時只改透明度
    private func layers(_ crop: CGRect) -> some View {
        ZStack {
            PhotoLayer(image: photo.image, crop: crop)
            marks(.officials, crop).opacity(mode == .overview || mode == .officials ? 1 : 0)
            marks(.santing, crop).opacity(mode == .overview || mode == .santing ? 1 : 0)
            marks(.palaces, crop).opacity(mode == .palaces ? 1 : 0)
        }
        .animation(reduceMotion ? nil : Theme.transition, value: mode)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isImage)
        .accessibilityLabel(label)
    }

    private func marks(_ kind: MarkLayer.Kind, _ crop: CGRect) -> MarkLayer {
        MarkLayer(
            kind: kind, marks: photo.marks, image: photo.image.size, crop: crop,
            palaces: kind == .palaces ? palaces : [], textSize: min(tagText, Theme.markTextMax), top: fill?.top ?? 0,
            bottom: fill?.bottom ?? 0)
    }

    private var label: String {
        switch mode {
        case .overview:
            return photo.marks.hairY == nil ? "你的照片，標出五官和三停下面兩段的分界" : "你的照片，標出五官和三停的分界"
        case .officials:
            return "你的照片，標出眉、眼、鼻、嘴"
        case .santing:
            return photo.marks.hairY == nil ? "你的照片，標出三停下面兩段的分界" : "你的照片，標出三停的分界"
        case .palaces:
            let judged = palaces.filter { $0.status != .unjudged && !MarkLayer.noSpot.contains($0.id) }
            guard !judged.isEmpty else { return "你的照片，十二宮這次都沒判" }
            return "你的照片，標出判得到的宮：" + judged.map(\.palace.name).joined(separator: "、")
        }
    }

    private var legend: some View {
        HStack(spacing: Theme.group) {
            key("眉", Theme.markBrow)
            key("眼", Theme.markEye)
            key("鼻", Theme.markNose)
            key("嘴", Theme.markMouth)
            key("三停分界", Theme.markLine)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.cardPad)
        .padding(.vertical, Theme.rowPadV)
        .accessibilityHidden(true)
    }

    private func key(_ text: String, _ color: Color) -> some View {
        HStack(spacing: Theme.tight) {
            Circle().fill(color).frame(width: Theme.item, height: Theme.item)
            Text(text).font(.footnote).foregroundStyle(Theme.secondary)
        }
    }

    // MARK: 裁切

    /// 包住所有量測點和髮際線的範圍（照片像素），四周照比例再留一點
    private static func faceBox(_ photo: FacePhoto, padX: CGFloat, padY: CGFloat) -> CGRect? {
        let w = photo.image.size.width, h = photo.image.size.height
        let all = photo.marks.all
        guard let minX = all.map(\.x).min(), let maxX = all.map(\.x).max(), var minY = all.map(\.y).min(),
            let maxY = all.map(\.y).max(), maxX > minX, maxY > minY
        else { return nil }
        if let hair = photo.marks.hairY { minY = min(minY, hair) }
        let width = CGFloat(maxX - minX) * w, height = CGFloat(maxY - minY) * h
        guard width > 1, height > 1 else { return nil }
        return CGRect(
            x: CGFloat(minX) * w - width * padX, y: CGFloat(minY) * h - height * padY, width: width * (1 + padX * 2),
            height: height * (1 + padY * 2))
    }

    /// 卡片用法：照片上要留的範圍（像素），長寬比跟著臉走
    static func crop(_ photo: FacePhoto) -> CGRect {
        let full = CGRect(origin: .zero, size: photo.image.size)
        guard let box = faceBox(photo, padX: 0.28, padY: 0.14) else { return full }
        let cut = box.intersection(full)
        return cut.isNull || cut.width < 1 || cut.height < 1 ? full : cut
    }

    /// 滿版用法：臉放在沒被蓋住的那一段，左右鋪滿，往下至少鋪到 cover。
    /// 畫面再高也不放大照片，所以回傳的範圍可能超出照片下緣，超出的部分由 PhotoLayer 接
    static func crop(_ photo: FacePhoto, fill: Fill) -> CGRect {
        let full = CGRect(origin: .zero, size: photo.image.size)
        let size = fill.size
        guard size.width > 1, size.height > 1, full.width > 1, full.height > 1 else { return full }
        let face = faceBox(photo, padX: 0.28, padY: 0.06) ?? full
        let clear = max(1, size.height - fill.top - fill.bottom)
        // 照片一個像素在畫面上畫多大
        let wanted = min(size.width / face.width, clear / face.height)
        let cover = min(max(1, fill.cover), size.height)
        let scale = max(wanted, size.width / full.width, cover / full.height)
        let w = size.width / scale, h = size.height / scale
        let x = face.midX - w / 2
        let y = face.midY - (fill.top + clear / 2) / scale
        return CGRect(
            x: min(max(0, x), max(0, full.width - w)), y: min(max(0, y), max(0, full.height - cover / scale)), width: w,
            height: h)
    }
}

/// 照片那一層：裁到 crop 的範圍，左右相反。照片下面不夠的地方，把最後幾排像素往下拉到底，接縫才看不出來
private struct PhotoLayer: View {
    let image: UIImage
    let crop: CGRect

    var body: some View {
        Canvas { context, size in
            let scale = size.width / max(1, crop.width)
            var flipped = context
            flipped.translateBy(x: size.width, y: 0)
            flipped.scaleBy(x: -1, y: 1)
            let frame = CGRect(
                x: -crop.minX * scale, y: -crop.minY * scale, width: image.size.width * scale,
                height: image.size.height * scale)
            let gap = size.height - frame.maxY
            if gap > 0, let rows = lastRows {
                // 上下各多畫一段：上面被照片蓋住，下面在畫面外，邊緣變淡也看不到
                flipped.draw(
                    Image(uiImage: rows),
                    in: CGRect(x: frame.minX, y: frame.maxY - gap, width: frame.width, height: gap * 3))
            }
            flipped.draw(Image(uiImage: image), in: frame)
        }
    }

    /// 照片最下面幾排
    private var lastRows: UIImage? {
        guard let cg = image.cgImage else { return nil }
        let count = min(4, cg.height)
        return cg.cropping(to: CGRect(x: 0, y: cg.height - count, width: cg.width, height: count))
            .map { UIImage(cgImage: $0) }
    }
}

/// 一區的標註
private struct MarkLayer: View {
    enum Kind {
        case officials, santing, palaces
    }

    /// 這兩宮看的是整張臉，沒有一個位置可以點
    static let noSpot: Set<String> = ["fude", "xiangmao"]

    let kind: Kind
    let marks: PhotoMarks
    /// 照片的大小（像素）
    let image: CGSize
    let crop: CGRect
    let palaces: [PalaceResult]
    /// 標籤的字多大
    let textSize: CGFloat
    /// 上下被返回列和視窗蓋住的高度，十二宮的標籤不放進去
    let top: CGFloat
    let bottom: CGFloat

    var body: some View {
        Canvas { context, size in
            switch kind {
            case .officials: drawOfficials(context, size)
            case .santing: drawSanting(context, size)
            case .palaces: drawPalaces(context, size)
            }
        }
    }

    /// 照片上的位置 → 畫面上的位置。左右相反：照片的右邊畫在左邊
    private func place(_ uv: UV, _ size: CGSize) -> CGPoint {
        let scale = size.width / max(1, crop.width)
        return CGPoint(
            x: size.width - (CGFloat(uv.x) * image.width - crop.minX) * scale,
            y: (CGFloat(uv.y) * image.height - crop.minY) * scale)
    }

    private func place(_ lm: LM, _ size: CGSize) -> CGPoint? {
        marks[lm].map { place($0, size) }
    }

    private func place(_ list: [UV], _ size: CGSize) -> [CGPoint] {
        list.map { place($0, size) }
    }

    // MARK: 五官

    private func drawOfficials(_ context: GraphicsContext, _ size: CGSize) {
        for brow in marks.brows { stroke(context, place(brow, size), Theme.markBrow, closed: false) }
        for eye in marks.eyes { stroke(context, place(eye, size), Theme.markEye, closed: true) }
        stroke(context, place(marks.lips, size), Theme.markMouth, closed: true)
        let nose: [LM] = [.noseRoot, .noseBridge1, .noseBridge2, .noseBridge3, .noseBridge4, .noseTip, .subnasale]
        stroke(context, nose.compactMap { place($0, size) }, Theme.markNose, closed: false)
    }

    private func stroke(_ context: GraphicsContext, _ points: [CGPoint], _ color: Color, closed: Bool) {
        guard points.count > 1, let first = points.first else { return }
        var path = Path()
        path.move(to: first)
        for p in points.dropFirst() { path.addLine(to: p) }
        if closed { path.closeSubpath() }
        context.stroke(
            path, with: .color(color), style: StrokeStyle(lineWidth: Theme.markWidth, lineCap: .round, lineJoin: .round))
    }

    // MARK: 三停

    private func drawSanting(_ context: GraphicsContext, _ size: CGSize) {
        let hair = marks.hairY, brow = marks[.glabella]?.y, nose = marks[.subnasale]?.y, chin = marks[.chin]?.y
        let lines: [(name: String, y: Double?)] = [("髮際", hair), ("眉心", brow), ("鼻底", nose), ("下巴", chin)]
        for line in lines {
            guard let y = line.y else { continue }
            divider(context, y: place(UV(x: 0, y: y), size).y, width: size.width, name: line.name)
        }
        // 兩條線之間寫是哪一停
        let segments: [(name: String, top: Double?, bottom: Double?)] = [
            ("上停", hair, brow), ("中停", brow, nose), ("下停", nose, chin)
        ]
        for s in segments {
            guard let top = s.top, let bottom = s.bottom else { continue }
            let y = place(UV(x: 0, y: (top + bottom) / 2), size).y
            tag(context, s.name, at: CGPoint(x: Theme.group, y: y), anchor: .leading, color: .white, fill: Theme.markShade)
        }
    }

    private func divider(_ context: GraphicsContext, y: CGFloat, width: CGFloat, name: String) {
        var path = Path()
        path.move(to: CGPoint(x: Theme.group, y: y))
        path.addLine(to: CGPoint(x: width - Theme.group, y: y))
        context.stroke(
            path, with: .color(Theme.markLine), style: StrokeStyle(lineWidth: Theme.markWidth, dash: [8, 6]))
        tag(
            context, name, at: CGPoint(x: width - Theme.group, y: y), anchor: .trailing, color: Theme.markLineText,
            fill: Theme.markLine)
    }

    // MARK: 十二宮

    /// 判得到的宮畫朱紅小標籤寫宮名，其他宮畫白色小圓點
    private func drawPalaces(_ context: GraphicsContext, _ size: CGSize) {
        var all: [PalaceMark] = []
        for x in palaces {
            let spots = palaceSpots(x.id, size).sorted { $0.x < $1.x }
            guard !spots.isEmpty else { continue }
            all.append(PalaceMark(name: x.status == .unjudged ? nil : x.palace.name, spots: spots))
        }
        let face = featureBoxes(size)
        var taken: [CGRect] = []
        for (i, mark) in all.enumerated() {
            guard let name = mark.name, let anchor = mark.spots.first else { continue }
            var avoid: [Obstacle] = face.map { Obstacle(box: $0, weight: 1) }
            for (j, other) in all.enumerated() {
                let weight: CGFloat = j == i ? 20 : 2
                for p in other.spots { avoid.append(Obstacle(box: dotBox(p), weight: weight)) }
            }
            for box in taken { avoid.append(Obstacle(box: box, weight: 20)) }
            let text = label(context, name, color: .white)
            let box = palaceTag(text, for: mark.spots, avoid: avoid, size: size)
            taken.append(box)
            lead(context, from: anchor, to: box)
            paint(context, text, in: box, fill: Theme.markPalace)
        }
        // 點最後畫，標籤再怎麼擠都蓋不到點
        for mark in all {
            let judged = mark.name != nil
            for p in mark.spots {
                dot(context, p, judged ? Theme.markPalace : Color.white, edge: judged ? Color.white : Theme.markShade)
            }
        }
    }

    /// 一宮：沒判的沒有名字。位置由左到右排
    private struct PalaceMark {
        let name: String?
        let spots: [CGPoint]
    }

    /// 標籤要閃開的地方，疊到一平方點扣 weight 分
    private struct Obstacle {
        let box: CGRect
        let weight: CGFloat
    }

    /// 眉、眼、鼻、嘴在畫面上的範圍。鼻翼沒有量測點，寬度照兩眼之間的距離估
    private func featureBoxes(_ size: CGSize) -> [CGRect] {
        let eyes = marks.eyes.compactMap { bounds(place($0, size)) }
        var boxes = marks.brows.compactMap { bounds(place($0, size)) } + eyes
        if let lips = bounds(place(marks.lips, size)) { boxes.append(lips) }
        let line: [LM] = [.noseRoot, .noseBridge2, .noseTip, .subnasale]
        if var nose = bounds(line.compactMap { place($0, size) }) {
            if eyes.count == 2 {
                let gap = max(eyes[0].minX, eyes[1].minX) - min(eyes[0].maxX, eyes[1].maxX)
                nose = nose.insetBy(dx: -max(0, gap * 0.8 - nose.width) / 2, dy: 0)
            }
            boxes.append(nose)
        }
        return boxes
    }

    /// 標籤放在點旁邊的哪裡：往幾個方向、由近到遠試，挑疊到最少又離點最近的。
    /// 一左一右的宮跟著左邊那個點，只往上和外側放，不擠到臉中間
    private func palaceTag(
        _ text: GraphicsContext.ResolvedText, for spots: [CGPoint], avoid: [Obstacle], size: CGSize
    ) -> CGRect {
        let anchor = spots.first ?? .zero
        let start = tagBox(text, at: anchor, anchor: .center)
        let up = CGVector(dx: 0, dy: -1), down = CGVector(dx: 0, dy: 1)
        let left = CGVector(dx: -1, dy: 0), right = CGVector(dx: 1, dy: 0)
        let upLeft = CGVector(dx: -1, dy: -1), upRight = CGVector(dx: 1, dy: -1)
        let directions: [CGVector] =
            spots.count > 1 ? [up, left, upLeft, down] : [up, right, left, upRight, upLeft, down]
        let area = CGRect(
            x: Theme.tight, y: top + Theme.tight, width: size.width - Theme.tight * 2,
            height: size.height - top - bottom - Theme.tight * 2)
        var best = start
        var bestCost = CGFloat.greatestFiniteMagnitude
        for (order, direction) in directions.enumerated() {
            for step in 0..<8 {
                let gap = Theme.tight / 2 + CGFloat(step) * Theme.item
                let reach = Theme.markDot / 2 + gap
                let dx = direction.dx * (start.width / 2 + reach)
                let dy = direction.dy * (start.height / 2 + reach)
                let box = keep(start.offsetBy(dx: dx, dy: dy), inside: area)
                var cost: CGFloat = gap * 8 + CGFloat(order) * 6
                for o in avoid { cost += overlap(box, o.box) * o.weight }
                if cost < bestCost {
                    bestCost = cost
                    best = box
                }
            }
        }
        return best
    }

    private func keep(_ box: CGRect, inside area: CGRect) -> CGRect {
        let x = min(max(area.minX, box.minX), max(area.minX, area.maxX - box.width))
        let y = min(max(area.minY, box.minY), max(area.minY, area.maxY - box.height))
        return CGRect(x: x, y: y, width: box.width, height: box.height)
    }

    private func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let hit = a.intersection(b)
        return hit.isNull ? 0 : hit.width * hit.height
    }

    /// 標籤離點有一段距離時，拉一條細線連起來，才看得出是誰的
    private func lead(_ context: GraphicsContext, from p: CGPoint, to box: CGRect) {
        let end = CGPoint(x: min(max(p.x, box.minX), box.maxX), y: min(max(p.y, box.minY), box.maxY))
        guard hypot(end.x - p.x, end.y - p.y) > Theme.markDot else { return }
        var path = Path()
        path.move(to: p)
        path.addLine(to: end)
        context.stroke(path, with: .color(Theme.markPalace), lineWidth: Theme.hairline)
    }

    /// 每一宮在畫面上的位置。量不到那個點就不畫
    private func palaceSpots(_ id: String, _ size: CGSize) -> [CGPoint] {
        let eyes = marks.eyes.compactMap { bounds(place($0, size)) }
        switch id {
        case "ming": return [place(.glabella, size)].compactMap { $0 }
        case "caibo": return [place(.noseTip, size)].compactMap { $0 }
        case "jie": return [place(.noseRoot, size)].compactMap { $0 }
        case "xiongdi":
            return marks.brows.compactMap { bounds(place($0, size)) }.map { CGPoint(x: $0.midX, y: $0.midY) }
        case "tianzhai":
            // 規則庫只寫「兩隻眼睛」。點放在上眼瞼上方一點，不壓在瞳孔上
            return eyes.map { CGPoint(x: $0.midX, y: $0.minY - Theme.item) }
        case "nannv":
            return eyes.map { CGPoint(x: $0.midX, y: $0.maxY + $0.width * 0.35) }
        case "qiqie":
            guard eyes.count == 2 else { return [] }
            let middle = (eyes[0].midX + eyes[1].midX) / 2
            return eyes.map { eye in
                let out = eye.width * 0.35
                return CGPoint(x: eye.midX < middle ? eye.minX - out : eye.maxX + out, y: eye.midY)
            }
        case "guanlu":
            guard let g = place(.glabella, size), let top = place(.top, size) else { return [] }
            return [CGPoint(x: (g.x + top.x) / 2, y: (g.y + top.y) / 2)]
        case "qianyi":
            return [place(.templeR, size), place(.templeL, size)].compactMap { $0 }
        case "nupu":
            guard let chin = place(.chin, size), let nose = place(.subnasale, size) else { return [] }
            return [CGPoint(x: chin.x + (nose.x - chin.x) * 0.2, y: chin.y + (nose.y - chin.y) * 0.2)]
        default:
            return []
        }
    }

    private func bounds(_ points: [CGPoint]) -> CGRect? {
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(), let minY = points.map(\.y).min(),
            let maxY = points.map(\.y).max()
        else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func dotBox(_ p: CGPoint) -> CGRect {
        let r = Theme.markDot / 2
        return CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
    }

    private func dot(_ context: GraphicsContext, _ p: CGPoint, _ color: Color, edge: Color) {
        let path = Path(ellipseIn: dotBox(p))
        context.fill(path, with: .color(color))
        context.stroke(path, with: .color(edge), lineWidth: Theme.hairline)
    }

    // MARK: 照片上的小標籤：壓一塊底色，照片亮或暗都看得到字

    private func label(_ context: GraphicsContext, _ text: String, color: Color) -> GraphicsContext.ResolvedText {
        // 固定大小的字型不會再跟著字級放大，上限在 textSize 就算好了
        context.resolve(Text(text).font(.system(size: textSize, weight: .semibold)).foregroundColor(color))
    }

    private func tagBox(_ text: GraphicsContext.ResolvedText, at p: CGPoint, anchor: UnitPoint) -> CGRect {
        let s = text.measure(in: CGSize(width: 200, height: 100))
        let w = s.width + Theme.item * 2, h = s.height + Theme.tight
        return CGRect(x: p.x - w * anchor.x, y: p.y - h * anchor.y, width: w, height: h)
    }

    private func paint(_ context: GraphicsContext, _ text: GraphicsContext.ResolvedText, in box: CGRect, fill: Color) {
        context.fill(Path(roundedRect: box, cornerRadius: box.height / 2), with: .color(fill))
        context.draw(text, at: CGPoint(x: box.midX, y: box.midY), anchor: .center)
    }

    private func tag(
        _ context: GraphicsContext, _ text: String, at p: CGPoint, anchor: UnitPoint, color: Color, fill: Color
    ) {
        let resolved = label(context, text, color: color)
        paint(context, resolved, in: tagBox(resolved, at: p, anchor: anchor), fill: fill)
    }
}
