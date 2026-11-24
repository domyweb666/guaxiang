import Foundation

/// 網格的一個頂點，用 ARKit 的臉座標：x 往本人左邊、y 往上、z 往鏡頭
struct MeshVertex: Equatable {
    var x: Double
    var y: Double
    var z: Double
}

/// 臉上的一個位置，用最多三個頂點的比例表示。
/// 網格的頂點編號是固定的，所以同一組比例在每一張畫面都指到同一個部位。
struct MeshPoint: Equatable {
    struct Part: Equatable {
        var index: Int
        var weight: Double
    }

    var parts: [Part]

    func place(_ vertices: [MeshVertex]) -> MeshVertex? {
        guard !parts.isEmpty else { return nil }
        var out = MeshVertex(x: 0, y: 0, z: 0)
        for part in parts {
            guard vertices.indices.contains(part.index) else { return nil }
            let v = vertices[part.index]
            out.x += v.x * part.weight
            out.y += v.y * part.weight
            out.z += v.z * part.weight
        }
        return out
    }
}

/// 在 ARKit 臉部網格上找出量測要用的點。看網格自己的形狀找，不需要人一點一點指定：
/// 眼睛是網格上的兩個洞、鼻尖是中線最凸的地方、鼻底是鼻尖下面凹進去最深的地方、下巴是中線最低的地方。
/// 其他點（眉心、山根、額頭側邊、下顎轉角…）照網頁版用的 MediaPipe 標準臉，換算成「眼睛到鼻底」「鼻底到下巴」的比例，
/// 再到這個網格的表面上取同樣比例的位置。
///
/// 找完會檢查上下順序、左右對稱和大小合不合理。有一項不合理就整組不用，報告寫沒判。
enum MeshLocator {
    /// 從網格拿的點。眼角、眼瞼、眉毛、嘴唇由 Vision 從照片上找；瞳孔用 ARKit 給的眼球位置
    static let landmarks: [LM] = [
        .cheekR, .cheekL, .glabella, .subnasale, .chin, .top, .templeR, .templeL, .jawR, .jawL,
        .noseRoot, .noseBridge1, .noseBridge2, .noseBridge3, .noseBridge4, .noseTip, .cheekFrontR, .cheekFrontL
    ]

    /// MediaPipe 標準臉（canonical_face_model.obj）上各點的座標，用來換算比例
    private enum Canon {
        static let eye = 2.629 // 上下眼瞼 159、145 的中間
        static let subnasale = -2.089 // 2
        static let chin = -9.403 // 152
        static let top = 8.262 // 10
        static let glabella = 4.886 // 9
        static let root = 3.271 // 168
        static let tip = -1.127 // 1
        static let bridges = [2.473, 1.728, 1.059, 0.366] // 6、197、195、5
        static let temple = 6.615 // 54
        static let cheek = 0.673 // 234
        static let jaw = -6.224 // 172
        static let frontX = 4.766 // 50
        static let frontY = -0.702
        static let halfWidth = 7.664 // 234 的 x
    }

    enum Failure: Error, Equatable {
        case empty, eyes, profile, surface, implausible
    }

    struct Sample {
        var y: Double
        var z: Double
    }

    /// - Parameters:
    ///   - triangles: 三個一組的頂點編號
    ///   - eyeY: 眼睛的高度。網格上找不到眼睛的洞時才用
    static func locate(
        vertices: [MeshVertex], triangles: [Int], eyeY: Double? = nil
    ) -> Result<[LM: MeshPoint], Failure> {
        let mesh = FaceMesh(vertices: vertices, triangles: triangles)
        guard vertices.count > 100, mesh.faces.count > 100 else { return .failure(.empty) }
        guard let eye = mesh.eyeHeight() ?? eyeY else { return .failure(.eyes) }

        // 臉的正中線，從上到下每 0.25 公釐取一個高度和深度
        let profile = mesh.midline(step: 0.00025)
        guard let highest = profile.first?.y, let chin = profile.last?.y, eye - chin > 0.03, highest > eye else {
            return .failure(.profile)
        }
        let span = eye - chin
        // 鼻尖：眼睛和下巴之間的上半段，最凸的一點
        let noseRange = profile.filter { $0.y < eye && $0.y > chin + span * 0.5 }
        guard let tip = noseRange.max(by: { $0.z < $1.z }) else { return .failure(.profile) }
        // 嘴唇最凸的一點，只拿來當鼻底那條弦的下端
        let lipRange = profile.filter { $0.y < chin + span * 0.56 && $0.y > chin + span * 0.4 && $0.y < tip.y }
        guard let lip = lipRange.max(by: { $0.z < $1.z }) else { return .failure(.profile) }
        // 鼻底：鼻尖到嘴唇連一條線，離線最遠、凹在線後面的那一點
        let underNose = profile.filter { $0.y < tip.y && $0.y > lip.y }
        guard let subnasale = underNose.max(by: { recess($0, tip, lip) < recess($1, tip, lip) }),
            recess(subnasale, tip, lip) > 0
        else { return .failure(.profile) }

        // 眼睛到鼻底的距離當尺
        let upper = eye - subnasale.y
        let byEye: (Double) -> Double = { eye + ($0 - Canon.eye) / (Canon.eye - Canon.subnasale) * upper }
        let jawShare = (Canon.subnasale - Canon.jaw) / (Canon.subnasale - Canon.chin)
        let jawY = subnasale.y - jawShare * (subnasale.y - chin)
        let rootY = byEye(Canon.root)

        var found: [LM: MeshPoint] = [:]
        found[.top] = mesh.surface(x: 0, y: min(byEye(Canon.top), highest))
        found[.glabella] = mesh.surface(x: 0, y: byEye(Canon.glabella))
        found[.noseRoot] = mesh.surface(x: 0, y: rootY)
        let bridgeNames: [LM] = [.noseBridge1, .noseBridge2, .noseBridge3, .noseBridge4]
        for (lm, canon) in zip(bridgeNames, Canon.bridges) {
            let t = (Canon.root - canon) / (Canon.root - Canon.tip)
            found[lm] = mesh.surface(x: 0, y: rootY + (tip.y - rootY) * t)
        }
        found[.noseTip] = mesh.surface(x: 0, y: tip.y)
        found[.subnasale] = mesh.surface(x: 0, y: subnasale.y)
        found[.chin] = mesh.surface(x: 0, y: chin)
        let sides: [(right: LM, left: LM, y: Double)] = [
            (.cheekR, .cheekL, byEye(Canon.cheek)), (.templeR, .templeL, byEye(Canon.temple)), (.jawR, .jawL, jawY)
        ]
        for side in sides {
            found[side.right] = mesh.silhouette(y: side.y, side: -1)
            found[side.left] = mesh.silhouette(y: side.y, side: 1)
        }
        guard let cheekR = found[.cheekR]?.place(vertices), let cheekL = found[.cheekL]?.place(vertices) else {
            return .failure(.surface)
        }
        let half = (cheekL.x - cheekR.x) / 2
        let frontX = Canon.frontX / Canon.halfWidth * half, frontY = byEye(Canon.frontY)
        found[.cheekFrontR] = mesh.surface(x: -frontX, y: frontY)
        found[.cheekFrontL] = mesh.surface(x: frontX, y: frontY)

        let placed = found.compactMapValues { $0.place(vertices) }
        guard landmarks.allSatisfy({ placed[$0] != nil }) else { return .failure(.surface) }
        guard plausible(placed, eye: eye, half: half) else { return .failure(.implausible) }
        return .success(found)
    }

    /// 點凹在「鼻尖到嘴唇」那條線後面多遠
    private static func recess(_ p: Sample, _ tip: Sample, _ lip: Sample) -> Double {
        let dy = lip.y - tip.y, dz = lip.z - tip.z
        return ((p.z - tip.z) * dy - (p.y - tip.y) * dz) / hypot(dy, dz)
    }

    /// 上下順序、左右對稱、大小比例都要像一張臉
    private static func plausible(_ p: [LM: MeshVertex], eye: Double, half: Double) -> Bool {
        let order: [LM] = [
            .top, .glabella, .noseRoot, .noseBridge1, .noseBridge2, .noseBridge3, .noseBridge4, .noseTip, .subnasale,
            .chin
        ]
        let heights = order.map { p[$0]!.y }
        for (a, b) in zip(heights, heights.dropFirst()) where a <= b { return false }
        guard half > 0.045, half < 0.11, p[.noseTip]!.z > p[.subnasale]!.z else { return false }
        let pairs: [(LM, LM)] = [
            (.cheekR, .cheekL), (.templeR, .templeL), (.jawR, .jawL), (.cheekFrontR, .cheekFrontL)
        ]
        for (r, l) in pairs {
            guard p[r]!.x < 0, p[l]!.x > 0, abs(p[r]!.x + p[l]!.x) < half * 0.1 else { return false }
        }
        let chin = p[.chin]!.y
        let lowerShare = (p[.subnasale]!.y - chin) / (eye - chin)
        guard lowerShare > 0.45, lowerShare < 0.75 else { return false }
        let faceRatio = (p[.top]!.y - chin) / (half * 2)
        guard faceRatio > 0.9, faceRatio < 1.8 else { return false }
        let jaw = (p[.jawL]!.x - p[.jawR]!.x) / (half * 2)
        let temple = (p[.templeL]!.x - p[.templeR]!.x) / (half * 2)
        return jaw > 0.4 && jaw < 1.02 && temple > 0.6 && temple < 1.05
    }
}

/// 一張三角網格，和幾種「從正面看過去」的問法
private struct FaceMesh {
    let vertices: [MeshVertex]
    let faces: [[Int]]

    init(vertices: [MeshVertex], triangles: [Int]) {
        self.vertices = vertices
        var list: [[Int]] = []
        var i = 0
        while i + 2 < triangles.count {
            let t = [triangles[i], triangles[i + 1], triangles[i + 2]]
            if t.allSatisfy({ vertices.indices.contains($0) }) { list.append(t) }
            i += 3
        }
        faces = list
    }

    /// 從正面看過去，(x, y) 這個位置打到網格最前面的哪裡
    func surface(x: Double, y: Double) -> MeshPoint? {
        hit(x: x, y: y, in: faces)?.point
    }

    /// 臉的正中線，從上到下的高度和深度
    func midline(step: Double) -> [MeshLocator.Sample] {
        // 先留下跨過中線的三角形，省得每個高度都把整張網格找一遍
        let middle = faces.filter { f in
            let xs = f.map { vertices[$0].x }
            return xs.min()! <= 1e-6 && xs.max()! >= -1e-6
        }
        let ys = middle.flatMap { f in f.map { vertices[$0].y } }
        guard let top = ys.max(), let bottom = ys.min() else { return [] }
        var out: [MeshLocator.Sample] = []
        var y = top
        while y >= bottom {
            if let h = hit(x: 0, y: y, in: middle) { out.append(MeshLocator.Sample(y: y, z: h.z)) }
            y -= step
        }
        return out
    }

    private func hit(x: Double, y: Double, in list: [[Int]]) -> (z: Double, point: MeshPoint)? {
        var best: (z: Double, point: MeshPoint)?
        for f in list {
            let a = vertices[f[0]], b = vertices[f[1]], c = vertices[f[2]]
            if min(a.y, b.y, c.y) > y + 1e-7 || max(a.y, b.y, c.y) < y - 1e-7 { continue }
            if min(a.x, b.x, c.x) > x + 1e-7 || max(a.x, b.x, c.x) < x - 1e-7 { continue }
            let den = (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
            guard abs(den) > 1e-13 else { continue }
            let wa = ((b.y - c.y) * (x - c.x) + (c.x - b.x) * (y - c.y)) / den
            let wb = ((c.y - a.y) * (x - c.x) + (a.x - c.x) * (y - c.y)) / den
            let wc = 1 - wa - wb
            guard wa > -1e-4, wb > -1e-4, wc > -1e-4 else { continue }
            let z = wa * a.z + wb * b.z + wc * c.z
            if best == nil || z > best!.z {
                let parts = [
                    MeshPoint.Part(index: f[0], weight: wa), MeshPoint.Part(index: f[1], weight: wb),
                    MeshPoint.Part(index: f[2], weight: wc)
                ]
                best = (z, MeshPoint(parts: parts))
            }
        }
        return best
    }

    /// 從正面看過去，這個高度臉最外側的那一點。side：-1 本人右邊、+1 本人左邊
    func silhouette(y: Double, side: Double) -> MeshPoint? {
        var best: (x: Double, point: MeshPoint)?
        for f in faces {
            for (i, j) in [(f[0], f[1]), (f[1], f[2]), (f[2], f[0])] {
                let a = vertices[i], b = vertices[j]
                guard (a.y - y) * (b.y - y) <= 0, abs(a.y - b.y) > 1e-12 else { continue }
                let t = (y - a.y) / (b.y - a.y)
                let x = (a.x + (b.x - a.x) * t) * side
                if best == nil || x > best!.x {
                    let parts = [MeshPoint.Part(index: i, weight: 1 - t), MeshPoint.Part(index: j, weight: t)]
                    best = (x, MeshPoint(parts: parts))
                }
            }
        }
        return best?.point
    }

    private struct Edge: Hashable {
        var a: Int
        var b: Int
    }

    private struct Ring {
        var centre: Double
        var low: Double
        var high: Double
        var width: Double
    }

    /// 眼睛的高度：網格上左右各一個洞（只屬於一個三角形的邊圍成的圈），取兩個洞的上下中間
    func eyeHeight() -> Double? {
        let eyes = holes().filter { abs($0.centre) > 0.015 && $0.width > 0.01 && $0.width < 0.05 }
        let right = eyes.filter { $0.centre < 0 }.max { $0.high < $1.high }
        let left = eyes.filter { $0.centre > 0 }.max { $0.high < $1.high }
        guard let right, let left, abs(right.centre + left.centre) < 0.008, abs(right.high - left.high) < 0.008
        else { return nil }
        return (right.low + right.high + left.low + left.high) / 4
    }

    private func holes() -> [Ring] {
        var uses: [Edge: Int] = [:]
        for f in faces {
            for (i, j) in [(f[0], f[1]), (f[1], f[2]), (f[2], f[0])] {
                uses[Edge(a: min(i, j), b: max(i, j)), default: 0] += 1
            }
        }
        var next: [Int: [Int]] = [:]
        for (e, n) in uses where n == 1 {
            next[e.a, default: []].append(e.b)
            next[e.b, default: []].append(e.a)
        }
        var seen: Set<Int> = []
        var rings: [Ring] = []
        for start in next.keys.sorted() where !seen.contains(start) {
            var stack = [start]
            var members: [MeshVertex] = []
            seen.insert(start)
            while let i = stack.popLast() {
                members.append(vertices[i])
                for j in next[i] ?? [] where !seen.contains(j) {
                    seen.insert(j)
                    stack.append(j)
                }
            }
            let xs = members.map(\.x), ys = members.map(\.y)
            rings.append(
                Ring(
                    centre: xs.reduce(0, +) / Double(xs.count), low: ys.min()!, high: ys.max()!,
                    width: xs.max()! - xs.min()!))
        }
        return rings
    }
}
