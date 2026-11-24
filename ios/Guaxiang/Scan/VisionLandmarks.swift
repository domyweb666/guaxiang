import CoreGraphics
import CoreVideo
import ImageIO
import Vision

/// Vision 找到的輪廓點。座標是 Vision 的算法：轉正後的畫面、0–1、左下角是原點
struct VisionFace {
    var browA: [UV]
    var browB: [UV]
    var outerLips: [UV]
    var innerLips: [UV]
    /// 兩隻眼睛的中心
    var eyes: [UV]
    /// 兩隻眼睛的輪廓
    var eyeA: [UV]
    var eyeB: [UV]
}

/// 相機原始畫面是橫的。這裡記著：轉哪個方向臉才是正的，以及 Vision 的座標怎麼換回原始畫面的座標。
struct VisionCalibration {
    let orientation: CGImagePropertyOrientation
    /// Vision 的座標 → 原始畫面的座標（0–1，左上角是原點）
    let toBuffer: Dihedral
    /// 對上的誤差（佔畫面的比例），越小越好。只知道方向、還沒跟 Vision 對過的是無限大
    var score = Double.infinity

    /// 原始畫面的座標 → 轉正後照片上的位置（0–1，左上角是原點）
    func displayPoint(_ buffer: UV) -> UV {
        let v = toBuffer.inverse.apply(buffer)
        return UV(x: v.x, y: 1 - v.y)
    }

    /// 轉正後照片上的位置 → 原始畫面的座標
    func bufferPoint(fromDisplay p: UV) -> UV {
        toBuffer.apply(UV(x: p.x, y: 1 - p.y))
    }
}

/// 用 Vision 在照片上找眉毛、眼睛和嘴唇的輪廓。ARKit 的網格是皮膚表面，量不到眉毛（毛髮），嘴唇輪廓也被抹平了（HANDOFF 4-2）；
/// 網格上眼睛的洞是往裡摺的眼皮，比看得到的眼睛窄，而且眉毛要跟眼角比，所以眼睛也用同一個來源。
/// 全部在手機上算，不連網。
enum VisionLandmarks {
    /// 四個方向各自對應的座標換法（照 CGImagePropertyOrientation 的定義推出來的）
    static let candidates: [(CGImagePropertyOrientation, Dihedral)] = [
        (.right, .antiTranspose), (.left, .transpose), (.up, .flipY), (.down, .flipX)
    ]

    /// 轉哪個方向臉才是正的：看 ARKit 算出來的嘴和兩眼，挑轉完以後眼睛最在嘴正上方的那個方向。
    /// 不准改成由 Vision 的分數挑：Vision 躺著的臉也找得到，四個方向的分數幾乎一樣，等於隨機挑。
    /// - Parameters:
    ///   - eyes: 兩顆眼球在原始畫面上的位置（0–1）
    ///   - mouth: 嘴巴在原始畫面上的位置（0–1）
    ///   - size: 原始畫面的像素大小。畫面不是正方形，比方向之前要換成像素
    static func upright(eyes: [UV], mouth: UV, size: CGSize) -> VisionCalibration {
        let n = Double(max(1, eyes.count))
        let upX = (eyes.map(\.x).reduce(0, +) / n - mouth.x) * Double(size.width)
        let upY = (eyes.map(\.y).reduce(0, +) / n - mouth.y) * Double(size.height)
        let all = candidates.map { VisionCalibration(orientation: $0.0, toBuffer: $0.1) }
        // 照片正上方在原始畫面上是哪一邊（一定貼著畫面的某一條邊，長度是 1）
        let match: (VisionCalibration) -> Double = { c in
            let top = c.bufferPoint(fromDisplay: UV(x: 0.5, y: 0))
            let bottom = c.bufferPoint(fromDisplay: UV(x: 0.5, y: 1))
            return (top.x - bottom.x) * upX + (top.y - bottom.y) * upY
        }
        var best = all[0]
        for c in all.dropFirst() where match(c) > match(best) { best = c }
        return best
    }

    static func detect(_ buffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> VisionFace? {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: orientation, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        // 畫面裡最大的那張臉
        guard
            let face = request.results?.max(by: {
                $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
            }), let marks = face.landmarks
        else { return nil }
        let unit = CGSize(width: 1, height: 1)
        let points: (VNFaceLandmarkRegion2D?) -> [UV] = { region in
            guard let region else { return [] }
            return region.pointsInImage(imageSize: unit).map { UV(x: Double($0.x), y: Double($0.y)) }
        }
        let centre: ([UV]) -> UV? = { set in
            guard !set.isEmpty else { return nil }
            let n = Double(set.count)
            return UV(x: set.map(\.x).reduce(0, +) / n, y: set.map(\.y).reduce(0, +) / n)
        }
        var eyes: [UV] = []
        for (pupil, outline) in [(marks.leftPupil, marks.leftEye), (marks.rightPupil, marks.rightEye)] {
            if let p = centre(points(pupil)) ?? centre(points(outline)) { eyes.append(p) }
        }
        return VisionFace(
            browA: points(marks.leftEyebrow), browB: points(marks.rightEyebrow), outerLips: points(marks.outerLips),
            innerLips: points(marks.innerLips), eyes: eyes, eyeA: points(marks.leftEye),
            eyeB: points(marks.rightEye))
    }

    /// 方向已經由 upright 定好，這裡只看那個方向 Vision 找到的眼睛和嘴，跟 ARKit 算出來的位置對不對得上。
    /// - Parameters:
    ///   - upright: 臉朝上的那個方向
    ///   - eyes: ARKit 兩顆眼球在原始畫面上的位置
    ///   - mouth: ARKit 估的嘴巴位置
    static func calibrate(
        _ buffer: CVPixelBuffer, upright: VisionCalibration, eyes: [UV], mouth: UV
    ) -> VisionCalibration? {
        guard eyes.count == 2, let face = detect(buffer, orientation: upright.orientation), face.eyes.count == 2,
            !face.outerLips.isEmpty
        else { return nil }
        let seen = face.eyes.map(upright.toBuffer.apply)
        let n = Double(face.outerLips.count)
        let lips = upright.toBuffer.apply(
            UV(x: face.outerLips.map(\.x).reduce(0, +) / n, y: face.outerLips.map(\.y).reduce(0, +) / n))
        let straight = (gap(seen[0], eyes[0]) + gap(seen[1], eyes[1])) / 2
        let crossed = (gap(seen[0], eyes[1]) + gap(seen[1], eyes[0])) / 2
        var result = upright
        result.score = min(straight, crossed) + gap(lips, mouth) / 2
        return result.score < 0.08 ? result : nil
    }

    private static func gap(_ a: UV, _ b: UV) -> Double {
        hypot(a.x - b.x, a.y - b.y)
    }
}
