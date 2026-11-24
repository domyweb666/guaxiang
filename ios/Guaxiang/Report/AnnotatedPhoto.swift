import SwiftUI

/// 這次掃的照片，疊上量測用到的位置：眉、眼、鼻、嘴的輪廓，和三停的分界線。
/// 跟自拍一樣左右相反（跟網頁版的標註圖相同）。照片裁到臉的範圍，臉才夠大看得清楚。
struct AnnotatedPhoto: View {
    let photo: FacePhoto

    var body: some View {
        let crop = Self.crop(photo)
        VStack(alignment: .leading, spacing: 0) {
            Canvas { context, size in
                draw(&context, size: size, crop: crop)
            }
            .aspectRatio(crop.width / max(1, crop.height), contentMode: .fit)
            .frame(maxWidth: .infinity)
            .accessibilityElement()
            .accessibilityLabel(photo.marks.hairY == nil ? "你的照片，標出五官和三停下面兩段的分界" : "你的照片，標出五官和三停的分界")
            legend
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
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

    /// 照片上要留的範圍（像素）：包住所有量測點和髮際線，四周再留一點
    static func crop(_ photo: FacePhoto) -> CGRect {
        let w = photo.image.size.width, h = photo.image.size.height
        let full = CGRect(x: 0, y: 0, width: w, height: h)
        let all = photo.marks.all
        guard let minX = all.map(\.x).min(), let maxX = all.map(\.x).max(), var minY = all.map(\.y).min(),
            let maxY = all.map(\.y).max(), maxX > minX, maxY > minY
        else { return full }
        if let hair = photo.marks.hairY { minY = min(minY, hair) }
        let padX = (maxX - minX) * 0.28, padY = (maxY - minY) * 0.14
        let box = CGRect(
            x: (minX - padX) * w, y: (minY - padY) * h, width: (maxX - minX + padX * 2) * w,
            height: (maxY - minY + padY * 2) * h)
        let cut = box.intersection(full)
        return cut.isNull || cut.width < 1 || cut.height < 1 ? full : cut
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, crop: CGRect) {
        let image = photo.image.size
        let scale = size.width / crop.width
        // 左右相反：照片的右邊畫在左邊
        let at: (UV) -> CGPoint = { uv in
            CGPoint(
                x: size.width - (CGFloat(uv.x) * image.width - crop.minX) * scale,
                y: (CGFloat(uv.y) * image.height - crop.minY) * scale)
        }
        var flipped = context
        flipped.translateBy(x: size.width, y: 0)
        flipped.scaleBy(x: -1, y: 1)
        flipped.draw(
            Image(uiImage: photo.image),
            in: CGRect(
                x: -crop.minX * scale, y: -crop.minY * scale, width: image.width * scale, height: image.height * scale))

        let marks = photo.marks
        marks.brows.forEach { stroke(context, $0.map(at), Theme.markBrow, closed: false) }
        marks.eyes.forEach { stroke(context, $0.map(at), Theme.markEye, closed: true) }
        stroke(context, marks.lips.map(at), Theme.markMouth, closed: true)
        let nose: [LM] = [.noseRoot, .noseBridge1, .noseBridge2, .noseBridge3, .noseBridge4, .noseTip, .subnasale]
        stroke(context, nose.compactMap { marks[$0] }.map(at), Theme.markNose, closed: false)

        let lines: [(name: String, y: Double?)] = [
            ("髮際", marks.hairY), ("眉心", marks[.glabella]?.y), ("鼻底", marks[.subnasale]?.y), ("下巴", marks[.chin]?.y)
        ]
        for line in lines {
            guard let y = line.y else { continue }
            let height = at(UV(x: 0, y: y)).y
            divider(context, y: height, width: size.width, name: line.name)
        }
        // 兩條線之間寫是哪一停
        let segments: [(name: String, top: Double?, bottom: Double?)] = [
            ("上停", marks.hairY, marks[.glabella]?.y), ("中停", marks[.glabella]?.y, marks[.subnasale]?.y),
            ("下停", marks[.subnasale]?.y, marks[.chin]?.y)
        ]
        for s in segments {
            guard let top = s.top, let bottom = s.bottom else { continue }
            tag(context, s.name, at: CGPoint(x: Theme.section, y: at(UV(x: 0, y: (top + bottom) / 2)).y))
        }
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

    private func divider(_ context: GraphicsContext, y: CGFloat, width: CGFloat, name: String) {
        var path = Path()
        path.move(to: CGPoint(x: Theme.group, y: y))
        path.addLine(to: CGPoint(x: width - Theme.group, y: y))
        context.stroke(
            path, with: .color(Theme.markLine), style: StrokeStyle(lineWidth: Theme.markWidth, dash: [8, 6]))
        tag(context, name, at: CGPoint(x: width - Theme.section - Theme.tight, y: y), solid: true)
    }

    /// 照片上的小標籤：壓一塊底色，照片亮或暗都看得到字
    private func tag(_ context: GraphicsContext, _ text: String, at center: CGPoint, solid: Bool = false) {
        let label = context.resolve(
            Text(text).font(.caption.weight(.semibold)).foregroundColor(solid ? Theme.markLineText : .white))
        let s = label.measure(in: CGSize(width: 200, height: 100))
        let box = CGRect(
            x: center.x - s.width / 2 - Theme.item, y: center.y - s.height / 2 - Theme.tight / 2,
            width: s.width + Theme.item * 2, height: s.height + Theme.tight)
        context.fill(
            Path(roundedRect: box, cornerRadius: box.height / 2),
            with: .color(solid ? Theme.markLine : .black.opacity(0.55)))
        context.draw(label, at: center, anchor: .center)
    }
}
