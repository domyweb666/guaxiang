import ARKit
import CoreImage
import SwiftUI
import UIKit
import Vision

/// 掃完之後交出去的東西。照片只留在記憶體裡給「拉髮際線」那一步用，不存檔。
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
    /// 眉心、鼻底、下巴在照片上的位置（0–1，左上角是原點）
    var glabella: UV?
    var subnasale: UV?
    var chin: UV?
}

/// 開發工具「頂點對照」用的定格：一張照片，加上每個網格頂點在照片上的位置
struct MeshSnapshot {
    var image: UIImage
    var points: [UV]
    /// 每個頂點在臉上的左右位置（公尺；負的是本人右邊），指定點位時用來提醒有沒有點錯邊
    var faceX: [Double]
    var info: String
}

/// ARKit 臉部追蹤。每 0.09 秒看一張畫面：合格就收下，收滿 30 張結束。
/// 相機畫面、網格、深度都只在這裡用，算完特徵點就丟掉，不存檔、不上傳（鐵則 1）。
final class FaceScanSession: NSObject, ObservableObject, ARSessionDelegate {
    @Published var hint = "拿下眼鏡，把臉放進框裡"
    @Published var isGood = false
    @Published var count = 0
    @Published var finished: ScanCapture?
    @Published var failure: String?
    @Published var snapshot: MeshSnapshot?
    @Published var debugLine = ""

    let view = ARSCNView(frame: .zero)

    static var isSupported: Bool { ARFaceTrackingConfiguration.isSupported }

    private let queue = DispatchQueue(label: "org.domyweb.guaxiang.scan")
    private let ciContext = CIContext()
    private var collecting = false
    private var wantSnapshot = false
    private var lastTime: TimeInterval = 0
    private var frames: [FaceFrame] = []
    private var lights: [Double] = []
    private var best: BestShot?
    private var bestScore = Double.greatestFiniteMagnitude
    private var vertexMap = VertexMap()
    private var calibration: VisionCalibration?
    private var calibrationTries = 0
    private var visionHits = 0

    /// - Parameter collect: true 是正式掃描（收 30 張）；false 只開相機，給頂點對照工具定格用
    func start(collect: Bool) {
        let map = VertexMap.current()
        queue.sync {
            collecting = collect
            wantSnapshot = false
            lastTime = 0
            frames = []
            lights = []
            best = nil
            bestScore = .greatestFiniteMagnitude
            vertexMap = map
            calibration = nil
            calibrationTries = 0
            visionHits = 0
        }
        count = 0
        finished = nil
        failure = nil
        snapshot = nil
        guard Self.isSupported else {
            failure = "這支手機不支援臉部追蹤，這一版還不能掃。"
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

    func requestSnapshot() {
        queue.async { self.wantSnapshot = true }
    }

    // MARK: ARSessionDelegate

    func session(_ session: ARSession, didFailWithError error: Error) {
        let denied = (error as? ARError)?.code == .cameraUnauthorized
        let message = denied ? "相機沒有打開。請到「設定 → 瓜相」把相機打開再回來。" : "相機啟動失敗：\(error.localizedDescription)"
        DispatchQueue.main.async { self.failure = message }
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

        if calibration == nil, calibrationTries < 6, verdict == .ok || wantSnapshot {
            calibrationTries += 1
            let mouthGuess = (eyeR + eyeL) / 2 + SIMD3<Float>(0, -0.065, 0.02)
            calibration = VisionLandmarks.calibrate(
                frame.capturedImage, eyes: [project(eyeR), project(eyeL)], mouth: project(mouthGuess))
        }
        let display = calibration ?? .fallback

        if wantSnapshot {
            wantSnapshot = false
            if let image = makeImage(frame.capturedImage, orientation: display.orientation) {
                let info =
                    "頂點 \(vertices.count) 個・畫面 \(Int(resolution.width))×\(Int(resolution.height))・"
                    + (calibration.map { String(format: "Vision 方向 %d，誤差 %.3f", Int($0.orientation.rawValue), $0.score) }
                        ?? "Vision 沒對上，照片方向用預設值")
                let shot = MeshSnapshot(
                    image: image, points: pixels.map(display.displayPoint), faceX: facePoints.map(\.x), info: info)
                DispatchQueue.main.async { self.snapshot = shot }
            }
        }

        guard collecting, verdict == .ok else {
            publish(verdict, debug: debug)
            return
        }

        // 叫得出名字的點：網格的照對照表拿，瞳孔用眼球位置，眉毛和嘴唇用 Vision 從照片上找
        var named: FaceFrame = [:]
        for lm in VertexMap.meshLandmarks {
            if let index = vertexMap[lm], facePoints.indices.contains(index) { named[lm] = facePoints[index] }
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
            let at: (LM) -> UV? = { lm in
                guard let index = self.vertexMap[lm], pixels.indices.contains(index) else { return nil }
                return display.displayPoint(pixels[index])
            }
            best = BestShot(
                image: makeImage(frame.capturedImage, orientation: display.orientation), frame: named,
                glabella: at(.glabella), subnasale: at(.subnasale), chin: at(.chin))
        }

        let n = frames.count
        if n >= ScanGate.needFrames, let best {
            collecting = false
            var gaps: [String] = []
            let missing = vertexMap.missing
            if !missing.isEmpty {
                gaps.append("ARKit 頂點對照表還缺 \(missing.count) 個點，用到這些點的項目這次都沒判。")
            }
            if visionHits * 2 < n {
                gaps.append("眉毛和嘴唇的輪廓（Vision）沒有對上，眉毛、印堂、嘴巴相關的項目這次沒判。")
            }
            let capture = ScanCapture(frames: frames, lights: lights, best: best, gaps: gaps)
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
