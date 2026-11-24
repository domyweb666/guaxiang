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
        /// 被視窗蓋住的那一段
        var bottom: CGFloat
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let photo: FacePhoto
    var mode: Mode = .overview
    var palaces: [PalaceResult] = []
    var fill: Fill?

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
            palaces: kind == .palaces ? palaces : [])
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

    /// 滿版用法：臉放在沒被蓋住的那一段，再補成畫面的長寬比。照片不夠大就縮到照片範圍內
    static func crop(_ photo: FacePhoto, fill: Fill) -> CGRect {
        let full = CGRect(origin: .zero, size: photo.image.size)
        let size = fill.size
        guard size.width > 1, size.height > 1, full.width > 1, full.height > 1 else { return full }
        let face = faceBox(photo, padX: 0.28, padY: 0.06) ?? full
        let clear = max(1, size.height - fill.top - fill.bottom)
        // 照片一個像素在畫面上畫多大
        let wanted = min(size.width / face.width, clear / face.height)
        let scale = max(wanted, size.width / full.width, size.height / full.height)
        let w = size.width / scale, h = size.height / scale
        let x = face.midX - w / 2
        let y = face.midY - (fill.top + clear / 2) / scale
        return CGRect(
            x: min(max(0, x), max(0, full.width - w)), y: min(max(0, y), max(0, full.height - h)), width: w, height: h)
    }
}

/// 照片那一層：裁到 crop 的範圍，左右相反
private struct PhotoLayer: View {
    let image: UIImage
    let crop: CGRect

    var body: some View {
        Canvas { context, size in
            let scale = size.width / max(1, crop.width)
            var flipped = context
            flipped.translateBy(x: size.width, y: 0)
            flipped.scaleBy(x: -1, y: 1)
            flipped.draw(
                Image(uiImage: image),
                in: CGRect(
                    x: -crop.minX * scale, y: -crop.minY * scale, width: image.size.width * scale,
                    height: image.size.height * scale))
        }
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
        var judged: [(name: String, spots: [CGPoint])] = []
        for x in palaces {
            let spots = palaceSpots(x.id, size)
            guard !spots.isEmpty else { continue }
            if x.status == .unjudged {
                for p in spots { dot(context, p, Color.white, edge: Theme.markShade) }
            } else {
                judged.append((name: x.palace.name, spots: spots))
            }
        }
        var taken: [CGRect] = []
        for item in judged {
            let spots = item.spots.sorted { $0.x < $1.x }
            for p in spots { dot(context, p, Theme.markPalace, edge: Color.white) }
            guard let anchor = spots.first else { continue }
            let text = label(context, item.name, color: .white)
            var box = tagBox(text, at: anchor, anchor: .center)
            // 一左一右的宮，標籤寫在左邊那個點的外側，不擠到臉中間
            if spots.count > 1 { box.origin.x = anchor.x + Theme.item - box.width }
            box.origin.x = min(max(Theme.tight, box.minX), max(Theme.tight, size.width - box.width - Theme.tight))
            // 疊到別的標籤就往下挪，最多三次
            for _ in 0..<3 {
                guard let hit = taken.first(where: { $0.intersects(box) }) else { break }
                box.origin.y = hit.maxY + Theme.tight / 2
            }
            taken.append(box)
            paint(context, text, in: box, fill: Theme.markPalace)
        }
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
            return eyes.map { CGPoint(x: $0.midX, y: $0.midY) }
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

    private func dot(_ context: GraphicsContext, _ p: CGPoint, _ color: Color, edge: Color) {
        let r = Theme.markDot / 2
        let path = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        context.fill(path, with: .color(color))
        context.stroke(path, with: .color(edge), lineWidth: Theme.hairline)
    }

    // MARK: 照片上的小標籤：壓一塊底色，照片亮或暗都看得到字

    private func label(_ context: GraphicsContext, _ text: String, color: Color) -> GraphicsContext.ResolvedText {
        context.resolve(Text(text).font(.caption.weight(.semibold)).foregroundColor(color))
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
