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
    /// 對上的誤差（佔畫面的比例），越小越好
    let score: Double

    /// 沒對上時的預設：直拿手機、前鏡頭
    static let fallback = VisionCalibration(orientation: .right, toBuffer: .antiTranspose, score: .infinity)

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

    /// 試四個方向，看哪一個方向 Vision 找到的眼睛和嘴，跟 ARKit 算出來的位置對得上。
    /// - Parameters:
    ///   - eyes: ARKit 兩顆眼球在原始畫面上的位置
    ///   - mouth: ARKit 估的嘴巴位置（用來分辨上下顛倒）
    static func calibrate(_ buffer: CVPixelBuffer, eyes: [UV], mouth: UV) -> VisionCalibration? {
        guard eyes.count == 2 else { return nil }
        var best: VisionCalibration?
        for (orientation, dihedral) in candidates {
            guard let face = detect(buffer, orientation: orientation), face.eyes.count == 2, !face.outerLips.isEmpty
            else { continue }
            let seen = face.eyes.map(dihedral.apply)
            let n = Double(face.outerLips.count)
            let lips = dihedral.apply(
                UV(x: face.outerLips.map(\.x).reduce(0, +) / n, y: face.outerLips.map(\.y).reduce(0, +) / n))
            let straight = (gap(seen[0], eyes[0]) + gap(seen[1], eyes[1])) / 2
            let crossed = (gap(seen[0], eyes[1]) + gap(seen[1], eyes[0])) / 2
            let score = min(straight, crossed) + gap(lips, mouth) / 2
            if best == nil || score < best!.score {
                best = VisionCalibration(orientation: orientation, toBuffer: dihedral, score: score)
            }
        }
        guard let best, best.score < 0.08 else { return nil }
        return best
    }

    private static func gap(_ a: UV, _ b: UV) -> Double {
        hypot(a.x - b.x, a.y - b.y)
    }
}
