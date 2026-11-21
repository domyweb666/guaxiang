import XCTest
import simd

@testable import Guaxiang

final class EngineUnitTests: XCTestCase {
    // MARK: 掃描把關

    private var good: ScanGate.Input {
        ScanGate.Input(
            faceCount: 1, distance: 0.35, lumaMean: 140, lumaSideDiff: 0.05, yaw: 1, pitch: -2, roll: 0.5,
            smile: 0.1, frown: 0.1, jawOpen: 0.05, blink: 0.1)
    }

    func testGateAcceptsGoodFrame() {
        XCTAssertEqual(ScanGate.judge(good), .ok)
    }

    func testGateHints() {
        var i = good
        i.faceCount = 0
        XCTAssertEqual(ScanGate.judge(i), .hint("拿下眼鏡，把臉放進框裡"))
        i = good
        i.faceCount = 2
        XCTAssertEqual(ScanGate.judge(i), .hint("請確定畫面裡只有你"))
        i = good
        i.distance = 0.6
        XCTAssertEqual(ScanGate.judge(i), .hint("靠近一點"))
        i = good
        i.distance = 0.15
        XCTAssertEqual(ScanGate.judge(i), .hint("遠一點"))
        i = good
        i.lumaMean = 60
        XCTAssertEqual(ScanGate.judge(i), .hint("到光線充足的地方"))
        i = good
        i.lumaMean = 230
        XCTAssertEqual(ScanGate.judge(i), .hint("太亮了，避開直射光"))
        i = good
        i.lumaSideDiff = 0.4
        XCTAssertEqual(ScanGate.judge(i), .hint("一邊臉太暗，請面向光源"))
        i = good
        i.yaw = -9
        XCTAssertEqual(ScanGate.judge(i), .hint("請正對鏡頭"))
        i = good
        i.pitch = 9
        XCTAssertEqual(ScanGate.judge(i), .hint("不要抬頭或低頭，手機拿到眼睛高度"))
        i = good
        i.roll = 6
        XCTAssertEqual(ScanGate.judge(i), .hint("頭不要歪"))
        i = good
        i.smile = 0.5
        XCTAssertEqual(ScanGate.judge(i), .hint("放鬆表情，不用笑"))
    }

    func testGateSkipsBlinkSilently() {
        var i = good
        i.blink = 0.7
        XCTAssertEqual(ScanGate.judge(i), .skip)
    }

    // MARK: 頭的角度

    private func rotation(z: Float = 0, y: Float = 0, x: Float = 0) -> simd_float4x4 {
        let rz = simd_float4x4(simd_quatf(angle: z, axis: SIMD3(0, 0, 1)))
        let ry = simd_float4x4(simd_quatf(angle: y, axis: SIMD3(0, 1, 0)))
        let rx = simd_float4x4(simd_quatf(angle: x, axis: SIMD3(1, 0, 0)))
        return rz * ry * rx
    }

    func testPoseStraightIsZero() {
        let p = HeadPose.angles(cameraFromFace: matrix_identity_float4x4)
        XCTAssertEqual(p.yaw, 0, accuracy: 0.01)
        XCTAssertEqual(p.pitch, 0, accuracy: 0.01)
        XCTAssertEqual(p.roll, 0, accuracy: 0.01)
    }

    func testPoseIgnoresQuarterTurnOfPortraitPhone() {
        // 直拿手機：臉在相機座標裡歪 90 度，另外真的轉頭 6 度、歪頭 3 度
        let deg = Float.pi / 180
        for quarter in [Float.pi / 2, -Float.pi / 2] {
            let p = HeadPose.angles(cameraFromFace: rotation(z: quarter + 3 * deg, y: 6 * deg))
            XCTAssertEqual(abs(p.yaw), 6, accuracy: 0.05)
            XCTAssertEqual(abs(p.pitch), 0, accuracy: 0.05)
            XCTAssertEqual(abs(p.roll), 3, accuracy: 0.05)
        }
    }

    func testPoseSeparatesNodFromTurn() {
        let deg = Float.pi / 180
        let p = HeadPose.angles(cameraFromFace: rotation(z: .pi / 2, x: 7 * deg))
        XCTAssertEqual(abs(p.pitch), 7, accuracy: 0.05)
        XCTAssertEqual(abs(p.yaw), 0, accuracy: 0.05)
    }

    // MARK: 畫面轉法

    func testDihedralInverseRoundTrips() {
        let p = UV(x: 0.2, y: 0.7)
        for d in Dihedral.allCases {
            let back = d.inverse.apply(d.apply(p))
            XCTAssertEqual(back.x, p.x, accuracy: 1e-12, "\(d)")
            XCTAssertEqual(back.y, p.y, accuracy: 1e-12, "\(d)")
        }
        XCTAssertEqual(Set(Dihedral.allCases.map { "\($0.apply(p))" }).count, 8, "八種轉法結果都要不一樣")
    }

    // MARK: 畫面 → 臉平面

    func testPlaneMapperRecoversAffineMap() {
        // 臉平面 = 像素經過一個線性轉換；內插出來應該一模一樣
        var pixels: [UV] = []
        var face: [Pt] = []
        for i in 0..<10 {
            for j in 0..<10 {
                let u = Double(i) / 10 + Double(j % 3) * 0.003, v = Double(j) / 10 + Double(i % 2) * 0.004
                pixels.append(UV(x: u, y: v))
                face.append(Pt(x: 0.2 * u - 0.05 * v + 0.01, y: 0.03 * u + 0.25 * v - 0.02, z: 0.1 * u))
            }
        }
        let mapper = PlaneMapper(pixels: pixels, face: face)
        for q in [UV(x: 0.33, y: 0.41), UV(x: 0.71, y: 0.18), UV(x: 0.5, y: -0.1)] {
            let got = try? XCTUnwrap(mapper.map(q))
            XCTAssertEqual(got?.x ?? .nan, 0.2 * q.x - 0.05 * q.y + 0.01, accuracy: 1e-9)
            XCTAssertEqual(got?.y ?? .nan, 0.03 * q.x + 0.25 * q.y - 0.02, accuracy: 1e-9)
            XCTAssertEqual(got?.z ?? .nan, 0.1 * q.x, accuracy: 1e-9)
        }
        XCTAssertNil(PlaneMapper(pixels: [], face: []).map(UV(x: 0, y: 0)))
    }

    // MARK: 輪廓認點

    func testBrowHeadAndTail() {
        let brow = [Pt(x: -0.05, y: -0.03), Pt(x: -0.03, y: -0.035), Pt(x: -0.012, y: -0.03)]
        let got = Outline.brow(brow, midX: 0)
        XCTAssertEqual(got?.head.x, -0.012)
        XCTAssertEqual(got?.tail.x, -0.05)
    }

    func testLipsFromOutline() {
        let outer = [
            Pt(x: -0.025, y: 0.04), Pt(x: -0.01, y: 0.034), Pt(x: 0, y: 0.035), Pt(x: 0.01, y: 0.034),
            Pt(x: 0.025, y: 0.04), Pt(x: 0.01, y: 0.049), Pt(x: 0, y: 0.05), Pt(x: -0.01, y: 0.049)
        ]
        let inner = [Pt(x: -0.01, y: 0.0405), Pt(x: 0, y: 0.04), Pt(x: 0.01, y: 0.0405), Pt(x: 0, y: 0.041)]
        let lips = Outline.lips(outer: outer, inner: inner)
        XCTAssertEqual(lips?.cornerR.x, -0.025)
        XCTAssertEqual(lips?.cornerL.x, 0.025)
        XCTAssertEqual(lips?.top.y, 0.035)
        XCTAssertEqual(lips?.bottom.y, 0.05)
        XCTAssertEqual(lips?.innerTop.y, 0.04)
        XCTAssertEqual(lips?.innerBottom.y, 0.041)
        XCTAssertNil(Outline.lips(outer: [], inner: []))
    }

    // MARK: 缺點位就不判

    func testMissingBrowsLeaveBrowFeaturesOut() {
        let frame: FaceFrame = [
            .pupilR: Pt(x: 400, y: 561), .pupilL: Pt(x: 560, y: 561),
            .eyeOuterR: Pt(x: 360, y: 560), .eyeInnerR: Pt(x: 440, y: 562),
            .eyeOuterL: Pt(x: 600, y: 560), .eyeInnerL: Pt(x: 520, y: 562),
            .eyeTopR: Pt(x: 400, y: 548), .eyeBottomR: Pt(x: 400, y: 574),
            .eyeTopL: Pt(x: 560, y: 548), .eyeBottomL: Pt(x: 560, y: 574)
        ]
        let f = FeatureEngine.features(frame, hairRatio: nil, eps: 1)
        XCTAssertNotNil(f["eye_lw"])
        XCTAssertNil(f["brow_eye"])
        XCTAssertNil(f["brow_tail"])
        XCTAssertNil(f["yintang"])
        XCTAssertNil(f["mouth_ipd"])
        XCTAssertTrue(FeatureEngine.features([:], hairRatio: nil, eps: 1).isEmpty)
    }

    func testSummarizeDropsFeatureSeenInTooFewFrames() throws {
        let bundle = Bundle(for: EngineUnitTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: "rules", withExtension: "json"))
        let rules = try Rules.decode(Data(contentsOf: url))
        let frames: [[String: Double]] = [["a": 1, "b": 2], ["a": 1.1], ["a": 0.9], ["a": 1], ["a": 1]]
        let F = Stats.summarize(frames, rules: rules)
        XCTAssertNotNil(F["a"])
        XCTAssertNil(F["b"], "只有五分之一的畫面量得到，不能算數")

        // 缺眉毛的量測：保壽官要寫沒判，不能算合格也不能算不合格
        let m = Measurement(
            when: Date(), frames: 5, light: 140, hasHair: false, answers: Answers(),
            F: ["eye_lw": FeatureStat(v: 3.5, iqr: 0.01, unstable: false)], rulesVersion: rules.version)
        let report = Report(measurement: m, rules: rules)
        XCTAssertEqual(report.officials.first { $0.official.id == "guan-brow" }?.status, .unjudged)
        XCTAssertEqual(report.officials.first { $0.official.id == "guan-eye" }?.status, .pass)
        XCTAssertNil(report.wuxing, "臉形的三個量測都沒有，不能硬判")
        XCTAssertEqual(report.palaces.filter { $0.status != .unjudged }.count, 0)
        XCTAssertFalse(Pack.build(report, profile: nil).isEmpty)
    }

    // MARK: 依據標籤

    func testCitationsKeepValidAndDropUnknown() {
        let parsed = Citations.parse("古書說**鼻樑直**［E3］，另外[E9]也提到［E2］。", validIDs: ["E2", "E3"])
        XCTAssertEqual(parsed.used, 2)
        XCTAssertTrue(parsed.bad)
        XCTAssertEqual(
            parsed.pieces, [.text("古書說鼻樑直"), .cite("E3"), .text("，另外也提到"), .cite("E2"), .text("。")])
    }

    func testCitationsFlagAnswerWithoutEvidence() {
        let parsed = Citations.parse("你的財運很好。", validIDs: ["E1"])
        XCTAssertEqual(parsed.used, 0)
        XCTAssertFalse(parsed.bad)
    }
}
