import ARKit
import CoreImage
import SwiftUI
import UIKit
import Vision

/// 掃完之後交出去的東西
struct ScanCapture {
    var frames: [FaceFrame]
    var lights: [Double]
    var best: BestShot
    /// 這次哪些量測來源沒接上
    var gaps: [String]
}

struct BestShot {
    var image: UIImage?
    var frame: FaceFrame
    /// 量測點在照片上的位置，拉髮際線和報告最上面的標註用
    var marks: PhotoMarks

    var glabella: UV? { marks[.glabella] }
    var subnasale: UV? { marks[.subnasale] }
    var chin: UV? { marks[.chin] }
}

/// ARKit 臉部追蹤。每 0.09 秒看一張畫面：合格就收下，收滿 30 張結束。
/// 相機畫面、網格、深度都只在這裡用，算完特徵點就丟掉。留下來的只有最正的那一張照片，存在這支手機、不上傳（鐵則 1）。
final class FaceScanSession: NSObject, ObservableObject, ARSessionDelegate {
    @Published var hint = "拿下眼鏡，把臉放進框裡"
    @Published var isGood = false
    @Published var count = 0
    @Published var finished: ScanCapture?
    @Published var failure: String?
    /// 掃不了的兩種情況，畫面換成整頁說明（準則 3-32、10-7）
    enum Blocked { case denied, unsupported }
    @Published var blocked: Blocked?
    @Published var debugLine = ""

    let view = ARSCNView(frame: .zero)

    static var isSupported: Bool { ARFaceTrackingConfiguration.isSupported }

    private let queue = DispatchQueue(label: "org.domyweb.guaxiang.scan")
    private let ciContext = CIContext()
    private var collecting = false
    private var lastTime: TimeInterval = 0
    private var frames: [FaceFrame] = []
    private var lights: [Double] = []
    private var best: BestShot?
    private var bestScore = Double.greatestFiniteMagnitude
    /// 量測點在標準臉上的位置。標準臉每次都一樣，所以整個 app 只找一次
    private static var standardMap: [LM: MeshPoint]?
    private var meshMap: [LM: MeshPoint] = [:]
    private var meshFailure: MeshLocator.Failure?
    private var calibration: VisionCalibration?
    private var calibrationTries = 0
    private var visionHits = 0

    func start() {
        queue.sync {
            collecting = true
            lastTime = 0
            frames = []
            lights = []
            best = nil
            bestScore = .greatestFiniteMagnitude
            meshMap = [:]
            meshFailure = nil
            calibration = nil
            calibrationTries = 0
            visionHits = 0
        }
        count = 0
        finished = nil
        failure = nil
        blocked = nil
        guard Self.isSupported else {
            blocked = .unsupported
            return
        }
        let config = ARFaceTrackingConfiguration()
        config.maximumNumberOfTrackedFaces = ARFaceTrackingConfiguration.supportedNumberOfTrackedFaces
        view.automaticallyUpdatesLighting = false
        view.session.delegate = self
        view.session.delegateQueue = queue
        view.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    func stop() {
        view.session.pause()
        queue.async { self.collecting = false }
    }

    // MARK: ARSessionDelegate

    func session(_ session: ARSession, didFailWithError error: Error) {
        let denied = (error as? ARError)?.code == .cameraUnauthorized
        let message = denied ? "相機沒有打開。請到「設定 → 瓜相」把相機打開再回來。" : "相機啟動失敗：\(error.localizedDescription)"
        DispatchQueue.main.async {
            if denied { self.blocked = .denied } else { self.failure = message }
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard frame.timestamp - lastTime > 0.09 else { return }
        lastTime = frame.timestamp
        process(frame)
    }

    // MARK: 一張畫面

    private func process(_ frame: ARFrame) {
        let faces = frame.anchors.compactMap { $0 as? ARFaceAnchor }.filter { $0.isTracked }
        var input = ScanGate.Input()
        input.faceCount = faces.count
        guard faces.count == 1, let face = faces.first else {
            publish(ScanGate.judge(input), debug: "")
            return
        }

        let camera = frame.camera
        let cameraFromFace = simd_mul(simd_inverse(camera.transform), face.transform)
        let offset = cameraFromFace.columns.3
        input.distance = Double(simd_length(SIMD3(offset.x, offset.y, offset.z)))
        let pose = HeadPose.angles(cameraFromFace: cameraFromFace)
        input.yaw = pose.yaw
        input.pitch = pose.pitch
        input.roll = pose.roll
        let shape: (ARFaceAnchor.BlendShapeLocation) -> Double = { face.blendShapes[$0]?.doubleValue ?? 0 }
        input.smile = max(shape(.mouthSmileLeft), shape(.mouthSmileRight))
        input.frown = max(shape(.browDownLeft), shape(.browDownRight))
        input.jawOpen = shape(.jawOpen)
        input.blink = max(shape(.eyeBlinkLeft), shape(.eyeBlinkRight))

        // 每個網格頂點：在原始畫面上的位置（0–1），和攤平後在臉平面上的位置
        let resolution = camera.imageResolution
        let project: (SIMD3<Float>) -> UV = { local in
            let world = simd_mul(face.transform, SIMD4(local.x, local.y, local.z, 1))
            let p = camera.projectPoint(
                SIMD3(world.x, world.y, world.z), orientation: .landscapeRight, viewportSize: resolution)
            return UV(x: Double(p.x / resolution.width), y: Double(p.y / resolution.height))
        }
        let flat: (SIMD3<Float>) -> Pt = { Pt(x: Double($0.x), y: Double(-$0.y), z: Double(-$0.z)) }
        let vertices = face.geometry.vertices
        let pixels = vertices.map(project)
        let facePoints = vertices.map(flat)

        let luma = Self.sampleLuma(frame.capturedImage, pixels: pixels, face: facePoints)
        input.lumaMean = luma.mean
        input.lumaSideDiff = luma.sideDiff

        let verdict = ScanGate.judge(input)
        let debug = String(
            format: "y%.0f p%.0f r%.0f L%.0f d%.0fcm", pose.yaw, pose.pitch, pose.roll, luma.mean,
            input.distance * 100)

        let eyeR = SIMD3(
            face.rightEyeTransform.columns.3.x, face.rightEyeTransform.columns.3.y,
            face.rightEyeTransform.columns.3.z)
        let eyeL = SIMD3(
            face.leftEyeTransform.columns.3.x, face.leftEyeTransform.columns.3.y, face.leftEyeTransform.columns.3.z)

        // 照片的方向每一張都由臉的位置決定，跟 Vision 有沒有對上無關
        let eyes = [project(eyeR), project(eyeL)]
        let mouth = project((eyeR + eyeL) / 2 + SIMD3<Float>(0, -0.065, 0.02))
        let display = VisionLandmarks.upright(eyes: eyes, mouth: mouth, size: resolution)
        if verdict == .ok {
            // 掃到一半換了拿手機的方向：換成新的方向重新對
            if let old = calibration, old.orientation != display.orientation {
                calibration = nil
                calibrationTries = 0
            }
            if calibration == nil, calibrationTries < 6 {
                calibrationTries += 1
                calibration = VisionLandmarks.calibrate(
                    frame.capturedImage, upright: display, eyes: eyes, mouth: mouth)
            }
        }

        guard collecting, verdict == .ok else {
            publish(verdict, debug: debug)
            return
        }

        if meshMap.isEmpty, meshFailure == nil {
            switch Self.locate(face: face, eyeY: Double(eyeR.y + eyeL.y) / 2) {
            case .success(let map): meshMap = map
            case .failure(let reason): meshFailure = reason
            }
        }

        // 叫得出名字的點：網格的照形狀找，瞳孔用眼球位置，眉毛、眼睛、嘴唇用 Vision 從照片上找
        var named: FaceFrame = [:]
        var marks = PhotoMarks()
        let solid = vertices.map { MeshVertex(x: Double($0.x), y: Double($0.y), z: Double($0.z)) }
        for (lm, point) in meshMap {
            guard let v = point.place(solid) else { continue }
            let local = SIMD3<Float>(Float(v.x), Float(v.y), Float(v.z))
            named[lm] = flat(local)
            marks[lm] = display.displayPoint(project(local))
        }
        named[.pupilR] = flat(eyeR)
        named[.pupilL] = flat(eyeL)
        if let calibration,
            let vision = VisionLandmarks.detect(frame.capturedImage, orientation: calibration.orientation)
        {
            let mapper = PlaneMapper(pixels: pixels, face: facePoints)
            let toFace: ([UV]) -> [Pt] = { $0.compactMap { mapper.map(calibration.toBuffer.apply($0)) } }
            let midX = (named[.pupilR]!.x + named[.pupilL]!.x) / 2
            var hit = false
            for brow in [toFace(vision.browA), toFace(vision.browB)] {
                guard let ends = Outline.brow(brow, midX: midX) else { continue }
                let centre = brow.map(\.x).reduce(0, +) / Double(brow.count)
                if centre < midX {
                    named[.browHeadR] = ends.head
                    named[.browTailR] = ends.tail
                } else {
                    named[.browHeadL] = ends.head
                    named[.browTailL] = ends.tail
                }
                hit = true
            }
            for points in [toFace(vision.eyeA), toFace(vision.eyeB)] {
                guard let eye = Outline.eye(points, midX: midX) else { continue }
                if eye.inner.x < midX {
                    named[.eyeOuterR] = eye.outer
                    named[.eyeInnerR] = eye.inner
                    named[.eyeTopR] = eye.top
                    named[.eyeBottomR] = eye.bottom
                } else {
                    named[.eyeOuterL] = eye.outer
                    named[.eyeInnerL] = eye.inner
                    named[.eyeTopL] = eye.top
                    named[.eyeBottomL] = eye.bottom
                }
            }
            let onPhoto: ([UV]) -> [UV] = { $0.map { calibration.displayPoint(calibration.toBuffer.apply($0)) } }
            marks.brows = [onPhoto(vision.browA), onPhoto(vision.browB)]
            marks.eyes = [onPhoto(vision.eyeA), onPhoto(vision.eyeB)]
            marks.lips = onPhoto(vision.outerLips)
            if let lips = Outline.lips(outer: toFace(vision.outerLips), inner: toFace(vision.innerLips)) {
                named[.mouthR] = lips.cornerR
                named[.mouthL] = lips.cornerL
                named[.lipTop] = lips.top
                named[.lipBottom] = lips.bottom
                named[.lipInnerTop] = lips.innerTop
                named[.lipInnerBottom] = lips.innerBottom
                hit = true
            }
            if hit { visionHits += 1 }
        }

        frames.append(named)
        lights.append(luma.mean)
        let score = abs(pose.yaw) + abs(pose.pitch) + abs(pose.roll)
        if score < bestScore {
            bestScore = score
            best = BestShot(
                image: makeImage(frame.capturedImage, orientation: display.orientation), frame: named, marks: marks)
        }

        let n = frames.count
        if n >= ScanGate.needFrames, var shot = best {
            collecting = false
            // 保險：照片跟標註對不上方向就轉正，免得拿躺著的照片拉髮際線
            if let image = shot.image {
                let photo = FacePhoto(image: image, marks: shot.marks).upright()
                shot.image = photo.image
                shot.marks = photo.marks
            }
            var gaps: [String] = []
            if meshMap.isEmpty {
                let code = meshFailure.map { "\($0)" } ?? "none"
                gaps.append("這次在臉上找不到量測點（代號 \(code)），臉形、臉的三段、鼻子都沒看。")
            }
            if visionHits * 2 < n {
                gaps.append("照片上的眉毛、眼睛、嘴唇輪廓沒有對上，眉毛、眼睛、兩眉中間、嘴巴這次沒看。")
            }
            let capture = ScanCapture(frames: frames, lights: lights, best: shot, gaps: gaps)
            DispatchQueue.main.async {
                self.view.session.pause()
                self.count = n
                self.hint = "掃描完成"
                self.finished = capture
            }
        } else {
            DispatchQueue.main.async {
                self.count = n
                self.isGood = true
                self.hint = "很好，保持不動"
                self.debugLine = debug
            }
        }
    }

    /// 找量測點：優先用 ARKit 的標準臉（沒有表情、左右對稱、每次都一樣），拿不到才用這張臉自己的網格
    private static func locate(face: ARFaceAnchor, eyeY: Double) -> Result<[LM: MeshPoint], MeshLocator.Failure> {
        if let standardMap { return .success(standardMap) }
        let standard: ARFaceGeometry? = ARFaceGeometry(blendShapes: [:])
        if let standard, standard.vertices.count == face.geometry.vertices.count,
            case .success(let map) = locate(standard, eyeY: eyeY)
        {
            standardMap = map
            return .success(map)
        }
        return locate(face.geometry, eyeY: eyeY)
    }

    private static func locate(
        _ geometry: ARFaceGeometry, eyeY: Double
    ) -> Result<[LM: MeshPoint], MeshLocator.Failure> {
        MeshLocator.locate(
            vertices: geometry.vertices.map { MeshVertex(x: Double($0.x), y: Double($0.y), z: Double($0.z)) },
            triangles: geometry.triangleIndices.map { Int($0) }, eyeY: eyeY)
    }

    private func publish(_ verdict: ScanGate.Verdict, debug: String) {
        DispatchQueue.main.async {
            self.debugLine = debug
            switch verdict {
            case .hint(let text):
                self.isGood = false
                self.hint = text
            case .skip:
                self.isGood = false
            case .ok:
                self.isGood = true
                self.hint = "很好，保持不動"
            }
        }
    }

    private func makeImage(_ buffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> UIImage? {
        let image = CIImage(cvPixelBuffer: buffer).oriented(orientation)
        guard let cg = ciContext.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// 臉上的亮度：在每個網格頂點的位置取一個亮度值，算整張臉的平均，和左右半邊差多少。
    /// 相機畫面的第一層就是亮度（Y），不用轉色彩。
    static func sampleLuma(_ buffer: CVPixelBuffer, pixels: [UV], face: [Pt]) -> (mean: Double, sideDiff: Double) {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard CVPixelBufferGetPlaneCount(buffer) >= 1, let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)
        else { return (0, 1) }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let videoRange = CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        var sum = 0.0, n = 0.0, sumR = 0.0, nR = 0.0, sumL = 0.0, nL = 0.0
        for (i, uv) in pixels.enumerated() where i < face.count {
            let x = Int(uv.x * Double(width)), y = Int(uv.y * Double(height))
            guard x >= 0, x < width, y >= 0, y < height else { continue }
            var value = Double(bytes[y * stride + x])
            if videoRange { value = max(0, min(255, (value - 16) * 255 / 219)) }
            sum += value
            n += 1
            if face[i].x < 0 {
                sumR += value
                nR += 1
            } else {
                sumL += value
                nL += 1
            }
        }
        guard n > 0, nR > 0, nL > 0 else { return (0, 1) }
        let a = sumR / nR, b = sumL / nL
        return (sum / n, abs(a - b) / max(a, b, 1))
    }
}

/// 相機預覽
struct CameraPreview: UIViewRepresentable {
    let session: FaceScanSession

    func makeUIView(context: Context) -> ARSCNView {
        session.view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}
