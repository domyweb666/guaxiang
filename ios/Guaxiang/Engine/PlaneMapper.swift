import Foundation

/// 畫面上的一個位置，x、y 都是 0–1
struct UV: Codable, Equatable {
    var x: Double
    var y: Double
}

/// 畫面的八種轉法（轉 90 度的倍數、左右或上下翻面）。
/// 相機給的原始畫面是橫的，Vision 和畫面上看到的是轉正後的，兩邊的座標靠這個互換。
enum Dihedral: Int, CaseIterable {
    case identity, flipX, flipY, rotate180, transpose, quarterA, quarterB, antiTranspose

    func apply(_ p: UV) -> UV {
        switch self {
        case .identity: return UV(x: p.x, y: p.y)
        case .flipX: return UV(x: 1 - p.x, y: p.y)
        case .flipY: return UV(x: p.x, y: 1 - p.y)
        case .rotate180: return UV(x: 1 - p.x, y: 1 - p.y)
        case .transpose: return UV(x: p.y, y: p.x)
        case .quarterA: return UV(x: 1 - p.y, y: p.x)
        case .quarterB: return UV(x: p.y, y: 1 - p.x)
        case .antiTranspose: return UV(x: 1 - p.y, y: 1 - p.x)
        }
    }

    var inverse: Dihedral {
        switch self {
        case .quarterA: return .quarterB
        case .quarterB: return .quarterA
        default: return self
        }
    }
}

/// 把畫面上的一個點（像素）換成臉平面上的位置。
/// 做法：找最近的三個網格頂點（它們在畫面上和臉平面上的位置都知道），用這三點的比例關係內插。
/// 用途是把 Vision 在照片上找到的眉毛、嘴唇輪廓，搬到跟 ARKit 網格同一個座標裡。
struct PlaneMapper {
    let pixels: [UV]
    let face: [Pt]

    init(pixels: [UV], face: [Pt]) {
        let n = min(pixels.count, face.count)
        self.pixels = Array(pixels.prefix(n))
        self.face = Array(face.prefix(n))
    }

    /// 最近的幾個頂點，近的在前。掃一遍只留最近的幾個，不把 1220 個全排序；
    /// 距離一樣時先來的排前面，跟穩定排序挑出來的一模一樣
    func nearest(_ q: UV, count: Int = 12) -> [Int] {
        var top: [(index: Int, d: Double)] = []
        top.reserveCapacity(count + 1)
        for i in pixels.indices {
            let d = (pixels[i].x - q.x) * (pixels[i].x - q.x) + (pixels[i].y - q.y) * (pixels[i].y - q.y)
            if top.count == count, d >= top[count - 1].d { continue }
            var j = top.count
            while j > 0, top[j - 1].d > d { j -= 1 }
            top.insert((index: i, d: d), at: j)
            if top.count > count { top.removeLast() }
        }
        return top.map(\.index)
    }

    func map(_ q: UV) -> Pt? {
        guard pixels.count >= 3 else { return nil }
        let nearest = self.nearest(q)
        let i0 = nearest[0]
        let p0 = pixels[i0]
        // 另外兩個點挑跟第一個點圍出最大三角形的，避免三點幾乎一直線
        var best: (a: Int, b: Int, area: Double)?
        for a in nearest.dropFirst() {
            for b in nearest.dropFirst() where b > a {
                let area = abs(cross(pixels[a].x - p0.x, pixels[a].y - p0.y, pixels[b].x - p0.x, pixels[b].y - p0.y))
                if best == nil || area > best!.area { best = (a, b, area) }
            }
        }
        guard let tri = best, tri.area > 1e-12 else { return face[i0] }
        let v0x = pixels[tri.a].x - p0.x, v0y = pixels[tri.a].y - p0.y
        let v1x = pixels[tri.b].x - p0.x, v1y = pixels[tri.b].y - p0.y
        let v2x = q.x - p0.x, v2y = q.y - p0.y
        let den = cross(v0x, v0y, v1x, v1y)
        let s = cross(v2x, v2y, v1x, v1y) / den
        let t = cross(v0x, v0y, v2x, v2y) / den
        let f0 = face[i0], f1 = face[tri.a], f2 = face[tri.b]
        return Pt(
            x: f0.x + s * (f1.x - f0.x) + t * (f2.x - f0.x),
            y: f0.y + s * (f1.y - f0.y) + t * (f2.y - f0.y),
            z: f0.z + s * (f1.z - f0.z) + t * (f2.z - f0.z))
    }

    private func cross(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> Double {
        ax * by - ay * bx
    }
}

/// 從輪廓點找出叫得出名字的點。Vision 給的是一圈輪廓，不保證哪一點是眉頭眉尾，所以用位置來認。
enum Outline {
    /// 一道眉毛：離臉中線最近的是眉頭，最遠的是眉尾
    static func brow(_ points: [Pt], midX: Double) -> (head: Pt, tail: Pt)? {
        guard points.count >= 2,
            let head = points.min(by: { abs($0.x - midX) < abs($1.x - midX) }),
            let tail = points.max(by: { abs($0.x - midX) < abs($1.x - midX) })
        else { return nil }
        return (head, tail)
    }

    struct Eye {
        var outer: Pt
        var inner: Pt
        var top: Pt
        var bottom: Pt
    }

    /// 一隻眼睛：離臉中線最近的是內眼角，最遠的是外眼角；上下眼瞼取兩個眼角正中間那個位置的高度
    static func eye(_ points: [Pt], midX: Double) -> Eye? {
        guard points.count >= 4,
            let inner = points.min(by: { abs($0.x - midX) < abs($1.x - midX) }),
            let outer = points.max(by: { abs($0.x - midX) < abs($1.x - midX) }),
            abs(outer.x - inner.x) > 0
        else { return nil }
        let line: (Double) -> Double = { x in
            inner.y + (outer.y - inner.y) * (x - inner.x) / (outer.x - inner.x)
        }
        let rest = points.filter { $0 != inner && $0 != outer }
        let upper = rest.filter { $0.y < line($0.x) } + [inner, outer]
        let lower = rest.filter { $0.y > line($0.x) } + [inner, outer]
        let centre = (inner.x + outer.x) / 2
        guard upper.count > 2, lower.count > 2, let top = height(upper, at: centre),
            let bottom = height(lower, at: centre)
        else { return nil }
        return Eye(outer: outer, inner: inner, top: top, bottom: bottom)
    }

    /// 把點照左右排成一條折線，取某個 x 的高度
    private static func height(_ points: [Pt], at x: Double) -> Pt? {
        let path = points.sorted { $0.x < $1.x }
        for (a, b) in zip(path, path.dropFirst()) where a.x <= x && b.x >= x && b.x > a.x {
            let t = (x - a.x) / (b.x - a.x)
            return Pt(x: x, y: a.y + (b.y - a.y) * t, z: a.z + (b.z - a.z) * t)
        }
        return nil
    }

    struct Lips {
        var cornerR: Pt
        var cornerL: Pt
        var top: Pt
        var bottom: Pt
        var innerTop: Pt
        var innerBottom: Pt
    }

    /// 嘴唇：外圈最左最右是嘴角；靠中線、在嘴角連線上面的是上唇峰，下面的是下唇底；內圈同理是唇縫上下
    static func lips(outer: [Pt], inner: [Pt]) -> Lips? {
        guard outer.count >= 4,
            let cornerR = outer.min(by: { $0.x < $1.x }),
            let cornerL = outer.max(by: { $0.x < $1.x })
        else { return nil }
        let midX = (cornerR.x + cornerL.x) / 2
        let midY = (cornerR.y + cornerL.y) / 2
        let nearMid: ([Pt]) -> Pt? = { set in set.min(by: { abs($0.x - midX) < abs($1.x - midX) }) }
        guard let top = nearMid(outer.filter { $0.y < midY }), let bottom = nearMid(outer.filter { $0.y > midY })
        else { return nil }
        // 嘴閉著的時候內圈上下會疊在一起，這是正常的
        let innerMidY = inner.isEmpty ? midY : inner.map(\.y).reduce(0, +) / Double(inner.count)
        let seam = Pt(x: midX, y: innerMidY, z: (top.z + bottom.z) / 2)
        let innerTop = nearMid(inner.filter { $0.y <= innerMidY }) ?? seam
        let innerBottom = nearMid(inner.filter { $0.y >= innerMidY }) ?? seam
        return Lips(
            cornerR: cornerR, cornerL: cornerL, top: top, bottom: bottom, innerTop: innerTop,
            innerBottom: innerBottom)
    }
}
