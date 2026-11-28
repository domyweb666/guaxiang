import XCTest

@testable import Guaxiang

/// 確認標註頁拖點的換算（Engine/ManualMarks.swift）
final class ManualMarksTests: XCTestCase {
    // MARK: 假臉

    /// 一張每個點都有的臉，臉平面上的公尺。眼長 3 公分、臉寬 14 公分
    private func face(_ jitter: Double = 0) -> FaceFrame {
        let j = jitter
        return [
            .cheekR: Pt(x: -0.07, y: 0), .cheekL: Pt(x: 0.07, y: 0),
            .glabella: Pt(x: 0, y: -0.03 + j), .subnasale: Pt(x: 0, y: 0.03), .chin: Pt(x: j, y: 0.09),
            .top: Pt(x: 0, y: -0.09),
            .templeR: Pt(x: -0.055, y: -0.06), .templeL: Pt(x: 0.055, y: -0.06),
            .jawR: Pt(x: -0.055, y: 0.06), .jawL: Pt(x: 0.055, y: 0.06 + j),
            .eyeOuterR: Pt(x: -0.045, y: -0.01), .eyeInnerR: Pt(x: -0.015, y: -0.01),
            .eyeOuterL: Pt(x: 0.045, y: -0.01), .eyeInnerL: Pt(x: 0.015, y: -0.01 + j),
            .eyeTopR: Pt(x: -0.03, y: -0.015), .eyeBottomR: Pt(x: -0.03, y: -0.005),
            .eyeTopL: Pt(x: 0.03, y: -0.015), .eyeBottomL: Pt(x: 0.03, y: -0.005),
            .browTailR: Pt(x: -0.05, y: -0.025), .browHeadR: Pt(x: -0.012, y: -0.03 + j),
            .browTailL: Pt(x: 0.05, y: -0.026), .browHeadL: Pt(x: 0.012, y: -0.03),
            .noseRoot: Pt(x: 0, y: -0.02), .noseBridge1: Pt(x: 0.0005, y: -0.01), .noseBridge2: Pt(x: 0, y: 0),
            .noseBridge3: Pt(x: 0.0003, y: 0.01), .noseBridge4: Pt(x: 0, y: 0.018),
            .noseTip: Pt(x: 0, y: 0.022, z: -0.03),
            .mouthR: Pt(x: -0.025, y: 0.05 + j), .mouthL: Pt(x: 0.025, y: 0.05),
            .lipTop: Pt(x: 0, y: 0.042), .lipInnerTop: Pt(x: 0, y: 0.049), .lipInnerBottom: Pt(x: 0, y: 0.051),
            .lipBottom: Pt(x: 0, y: 0.058),
            .pupilR: Pt(x: -0.03, y: -0.01), .pupilL: Pt(x: 0.03, y: -0.01 + j),
            .cheekFrontR: Pt(x: -0.04, y: 0.01, z: -0.01), .cheekFrontL: Pt(x: 0.04, y: 0.01, z: -0.01)
        ]
    }

    /// 30 張，每張抖一點點（跟真的掃描一樣不完全一樣）
    private var frames: [FaceFrame] { (0..<30).map { face(Double($0 % 7) * 0.00005) } }

    private func rulesFile() throws -> Rules {
        let bundle = Bundle(for: ManualMarksTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: "rules", withExtension: "json"))
        return try Rules.decode(Data(contentsOf: url))
    }

    /// 照片 ↔ 臉平面是線性的假網格：照片上 0–1 的格點，臉平面 = (0.2u − 0.1, 0.3v − 0.15)
    private var linear: PlaneMapper {
        var pixels: [UV] = []
        for i in 0...10 {
            for k in 0...10 { pixels.append(UV(x: Double(i) / 10, y: Double(k) / 10)) }
        }
        return PlaneMapper(pixels: pixels, face: pixels.map { Pt(x: 0.2 * $0.x - 0.1, y: 0.3 * $0.y - 0.15) })
    }

    // MARK: 沒拖點：跟原本一模一樣

    func testNoEditsKeepsOldResultExactly() throws {
        let rules = try rulesFile()
        let frames = self.frames
        let old = Stats.summarize(frames.map { FeatureEngine.features($0, hairRatio: 0.5, eps: 0.0001) }, rules: rules)
        XCTAssertFalse(old.isEmpty)
        XCTAssertEqual(ManualMarks.measure(frames, edits: nil, hairRatio: 0.5, eps: 0.0001, rules: rules), old)
        var edits = MarkEdits(reach: 0.0075)
        XCTAssertEqual(edits.frames(frames), frames)
        XCTAssertEqual(ManualMarks.measure(frames, edits: edits, hairRatio: 0.5, eps: 0.0001, rules: rules), old)
        // 拖了又拖回原位（位移是 0），也當沒調
        edits.set(.browTailR, from: UV(x: 0.3, y: 0.3), to: UV(x: 0.3, y: 0.3), delta: Pt(x: 0, y: 0))
        XCTAssertTrue(edits.adjusted.isEmpty)
        XCTAssertEqual(edits.frames(frames), frames)
        // 沒有髮際線的算法也一樣
        let noHair = Stats.summarize(frames.map { FeatureEngine.features($0, hairRatio: nil, eps: 0.0001) }, rules: rules)
        XCTAssertEqual(ManualMarks.measure(frames, edits: edits, hairRatio: nil, eps: 0.0001, rules: rules), noHair)
    }

    // MARK: 拖一個點，只改到用到那個點的特徵

    /// 每個可拖的點，Features.swift 裡用到它的特徵（有瞳孔，所以轉正和嘴寬不看眼角）
    private let uses: [LM: Set<String>] = [
        .glabella: ["santing_U", "santing_M", "santing_L", "santing_dev", "face_aspect", "santing_L_ml"],
        .subnasale: ["santing_U", "santing_M", "santing_L", "santing_dev", "santing_L_ml", "renzhong"],
        .chin: ["santing_U", "santing_M", "santing_L", "santing_dev", "face_aspect", "santing_L_ml", "renzhong", "jaw_angle"],
        .browHeadR: ["yintang", "brow_tail"], .browHeadL: ["yintang", "brow_tail"],
        .browTailR: ["brow_eye", "brow_tail"], .browTailL: ["brow_eye", "brow_tail"],
        .eyeOuterR: ["brow_eye", "yintang", "eye_lw"], .eyeOuterL: ["brow_eye", "yintang", "eye_lw"],
        .eyeInnerR: ["brow_eye", "yintang", "eye_lw"], .eyeInnerL: ["brow_eye", "yintang", "eye_lw"],
        .mouthR: ["mouth_ipd", "mouth_corner", "lip_thick"], .mouthL: ["mouth_ipd", "mouth_corner", "lip_thick"]
    ]

    /// 一定要變的那一個（不然修正就沒有作用）
    private let mustChange: [LM: String] = [
        .glabella: "santing_M", .subnasale: "renzhong", .chin: "jaw_angle", .browHeadR: "yintang",
        .browHeadL: "yintang", .browTailR: "brow_eye", .browTailL: "brow_eye", .eyeOuterR: "eye_lw",
        .eyeOuterL: "eye_lw", .eyeInnerR: "yintang", .eyeInnerL: "yintang", .mouthR: "mouth_ipd", .mouthL: "mouth_ipd"
    ]

    func testEveryDraggablePointHasAKnownFootprint() {
        XCTAssertEqual(Set(ManualMarks.draggable), Set(uses.keys))
        XCTAssertEqual(Set(ManualMarks.draggable), Set(mustChange.keys))
    }

    func testMovingOnePointOnlyChangesFeaturesThatUseIt() {
        for lm in ManualMarks.draggable {
            for hair in [0.5, nil] as [Double?] {
                var edits = MarkEdits(reach: 0.0075)
                edits.set(lm, from: UV(x: 0.5, y: 0.5), to: UV(x: 0.52, y: 0.51), delta: Pt(x: 0.002, y: 0.0015))
                XCTAssertEqual(edits.adjusted, [lm])
                for (before, after) in zip(frames, edits.frames(frames)) {
                    let a = FeatureEngine.features(before, hairRatio: hair, eps: 0.0001)
                    let b = FeatureEngine.features(after, hairRatio: hair, eps: 0.0001)
                    XCTAssertEqual(Set(a.keys), Set(b.keys), "\(lm)：量得到的項目不能變")
                    let changed = Set(a.keys.filter { a[$0] != b[$0] })
                    XCTAssertTrue(changed.isSubset(of: uses[lm] ?? []), "\(lm) 改到不該改的：\(changed)")
                    // 沒有髮際線時三段只剩下停可比，眉心、鼻子底、下巴要變的那一項不一定量得到
                    if let must = mustChange[lm], a[must] != nil {
                        XCTAssertTrue(changed.contains(must), "\(lm) 拖了，\(must) 卻沒變")
                    }
                    // 別的點一個位元都不動
                    for other in LM.allCases where other != lm { XCTAssertEqual(before[other], after[other]) }
                    XCTAssertEqual(after[lm]?.z, before[lm]?.z)
                }
            }
        }
    }

    func testPointMissingInAFrameStaysMissing() {
        var frame = face()
        frame[.browTailR] = nil
        let moved = ManualMarks.apply([.browTailR: Pt(x: 0.001, y: 0)], to: frame)
        XCTAssertNil(moved[.browTailR])
        XCTAssertEqual(moved, frame)
    }

    // MARK: 可移範圍

    func testReachIsAQuarterEyeLength() throws {
        XCTAssertEqual(try XCTUnwrap(ManualMarks.reach(face())), 0.03 * ManualMarks.reachInEyes, accuracy: 1e-12)
        var noEyes = face()
        for lm in [LM.eyeOuterR, .eyeInnerR, .eyeOuterL, .eyeInnerL] { noEyes[lm] = nil }
        XCTAssertEqual(try XCTUnwrap(ManualMarks.reach(noEyes)), 0.14 * ManualMarks.reachInFaceWidth, accuracy: 1e-12)
        XCTAssertNil(ManualMarks.reach([:]))
    }

    func testBeyondReachIsClampedAlongTheSameDirection() {
        let reach = 0.0075
        var edits = MarkEdits(reach: reach)
        edits.set(.browTailR, from: UV(x: 0.3, y: 0.3), to: UV(x: 0.9, y: 0.9), delta: Pt(x: 0.03, y: 0.04, z: 0.01))
        let d = edits.moves[.browTailR]?.delta
        XCTAssertEqual(hypot(d?.x ?? 0, d?.y ?? 0), reach, accuracy: 1e-12)
        XCTAssertEqual(d?.x ?? 0, reach * 0.6, accuracy: 1e-12)
        XCTAssertEqual(d?.y ?? 0, reach * 0.8, accuracy: 1e-12)
        XCTAssertEqual(d?.z, 0, "深度不跟著動")
        // 夾住以後套到每一張，位移也不會超過範圍
        for (before, after) in zip(frames, edits.frames(frames)) {
            let a = before[.browTailR]!, b = after[.browTailR]!
            XCTAssertLessThanOrEqual(hypot(b.x - a.x, b.y - a.y), reach + 1e-12)
        }
        // 範圍內的照原樣
        XCTAssertEqual(ManualMarks.clamp(Pt(x: 0.001, y: -0.002), reach: reach), Pt(x: 0.001, y: -0.002))
        // 沒有範圍就不能動；算壞的數字當沒動
        XCTAssertEqual(ManualMarks.clamp(Pt(x: 0.01, y: 0), reach: 0), Pt(x: 0, y: 0))
        XCTAssertEqual(ManualMarks.clamp(Pt(x: .nan, y: 0), reach: reach), Pt(x: 0, y: 0))
    }

    func testOnlyDraggablePointsAndRealMovesCount() {
        var edits = MarkEdits(reach: 0.0075)
        edits.set(.noseTip, from: UV(x: 0, y: 0), to: UV(x: 0.1, y: 0), delta: Pt(x: 0.001, y: 0))
        edits.set(.cheekR, from: UV(x: 0, y: 0), to: UV(x: 0.1, y: 0), delta: Pt(x: 0.001, y: 0))
        XCTAssertTrue(edits.moves.isEmpty, "不在可拖清單裡的點不收")
        // 手指點一下抖的那一點點（不到範圍的 2%）不算調過
        edits.set(.mouthL, from: UV(x: 0, y: 0), to: UV(x: 0.001, y: 0), delta: Pt(x: 0.0075 * 0.01, y: 0))
        XCTAssertTrue(edits.adjusted.isEmpty)
        edits.set(.mouthL, from: UV(x: 0, y: 0), to: UV(x: 0.01, y: 0), delta: Pt(x: 0.001, y: 0))
        edits.set(.chin, from: UV(x: 0, y: 0), to: UV(x: 0.01, y: 0), delta: Pt(x: 0, y: 0.001))
        XCTAssertEqual(edits.adjusted, [.mouthL, .chin], "照由上到下的順序")
        edits.reset(.mouthL)
        XCTAssertEqual(edits.adjusted, [.chin])
    }

    // MARK: 照片上的拖 → 臉平面

    func testPlaceConvertsPhotoDragAndStopsAtReach() throws {
        let mapper = linear
        let reach = 0.02
        let from = UV(x: 0.5, y: 0.5)
        // 範圍內：照片往右 0.05 → 臉上 0.01
        let inside = try XCTUnwrap(ManualMarks.place(mapper, from: from, to: UV(x: 0.55, y: 0.5), reach: reach))
        XCTAssertFalse(inside.limited)
        XCTAssertEqual(inside.uv, UV(x: 0.55, y: 0.5))
        XCTAssertEqual(inside.delta.x, 0.01, accuracy: 1e-9)
        XCTAssertEqual(inside.delta.y, 0, accuracy: 1e-9)
        // 超過：拖到 0.9 → 停在臉上 0.02，也就是照片上 0.6
        let outside = try XCTUnwrap(ManualMarks.place(mapper, from: from, to: UV(x: 0.9, y: 0.5), reach: reach))
        XCTAssertTrue(outside.limited)
        XCTAssertEqual(outside.uv.x, 0.6, accuracy: 1e-6)
        XCTAssertEqual(outside.uv.y, 0.5, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(hypot(outside.delta.x, outside.delta.y), reach)
        XCTAssertEqual(hypot(outside.delta.x, outside.delta.y), reach, accuracy: 1e-6)
        // 斜的：照片上 y 那一軸臉上比較長，退回的位置要照臉上的長度算
        let slant = try XCTUnwrap(ManualMarks.place(mapper, from: from, to: UV(x: 0.5, y: 0.9), reach: reach))
        XCTAssertEqual(slant.uv.y, 0.5 + 0.02 / 0.3, accuracy: 1e-6)
    }

    func testOriginSnapsToTheOutlinePointTheFeatureUses() throws {
        let mapper = linear
        let outline = [UV(x: 0.2, y: 0.3), UV(x: 0.25, y: 0.28), UV(x: 0.3, y: 0.31)]
        var frame = face()
        // Vision 那一點換到臉平面上就是第二個輪廓點
        frame[.browHeadR] = mapper.map(outline[1])
        let got = ManualMarks.origin(
            .browHeadR, frame: frame, marked: nil, outline: outline, mapper: mapper, reach: 0.0075)
        XCTAssertEqual(got, outline[1])
        // 輪廓上沒有對得上的點：不給拖
        frame[.browHeadR] = Pt(x: 0.09, y: 0.14)
        XCTAssertNil(
            ManualMarks.origin(.browHeadR, frame: frame, marked: nil, outline: outline, mapper: mapper, reach: 0.0075))
        // 網格的點用照片上記著的位置；這一張沒量到就不給拖
        XCTAssertEqual(
            ManualMarks.origin(.chin, frame: frame, marked: UV(x: 0.5, y: 0.9), outline: [], mapper: mapper, reach: 0.0075),
            UV(x: 0.5, y: 0.9))
        frame[.chin] = nil
        XCTAssertNil(
            ManualMarks.origin(.chin, frame: frame, marked: UV(x: 0.5, y: 0.9), outline: [], mapper: mapper, reach: 0.0075))
    }

    func testTurnedMapperGivesTheSameFacePoint() throws {
        let mapper = linear
        let q = UV(x: 0.37, y: 0.62)
        for d in Dihedral.allCases {
            let a = try XCTUnwrap(mapper.map(q)), b = try XCTUnwrap(mapper.turned(d).map(d.apply(q)))
            XCTAssertEqual(a.x, b.x, accuracy: 1e-9, "\(d)")
            XCTAssertEqual(a.y, b.y, accuracy: 1e-9, "\(d)")
        }
    }

    // MARK: 照片上的標註畫在調過的位置

    func testPhotoMarksFollowTheEdits() {
        var marks = PhotoMarks()
        marks[.glabella] = UV(x: 0.5, y: 0.3)
        marks.brows = [[UV(x: 0.2, y: 0.3), UV(x: 0.3, y: 0.28)], [UV(x: 0.7, y: 0.28), UV(x: 0.8, y: 0.3)]]
        marks.lips = [UV(x: 0.4, y: 0.7), UV(x: 0.6, y: 0.7)]
        var edits = MarkEdits(reach: 0.0075)
        edits.set(.glabella, from: UV(x: 0.5, y: 0.3), to: UV(x: 0.5, y: 0.32), delta: Pt(x: 0, y: 0.002))
        edits.set(.browHeadL, from: UV(x: 0.7, y: 0.28), to: UV(x: 0.71, y: 0.29), delta: Pt(x: 0.001, y: 0.001))
        edits.set(.mouthR, from: UV(x: 0.4, y: 0.7), to: UV(x: 0.39, y: 0.7), delta: Pt(x: -0.001, y: 0))
        let out = marks.applying(edits)
        XCTAssertEqual(out[.glabella], UV(x: 0.5, y: 0.32))
        XCTAssertEqual(out.brows[1][0], UV(x: 0.71, y: 0.29))
        XCTAssertEqual(out.brows[0], marks.brows[0])
        XCTAssertEqual(out.brows[1][1], marks.brows[1][1])
        XCTAssertEqual(out.lips, [UV(x: 0.39, y: 0.7), UV(x: 0.6, y: 0.7)])
        XCTAssertEqual(marks.applying(MarkEdits(reach: 0.0075)), marks, "沒調就原樣")
    }

    // MARK: 舊檔讀得進來

    func testOldMeasurementWithoutAdjustedDecodes() throws {
        let rules = try rulesFile()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // 2026-11-28 以前寫的檔案就是這個樣子：沒有 adjusted 這一欄
        let old = Sample.measurement(rulesVersion: rules.version)
        let data = try encoder.encode(old)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["adjusted"], "沒調過不寫這一欄，檔案跟以前一樣")
        let back = try decoder.decode(Measurement.self, from: data)
        XCTAssertEqual(back, old)
        XCTAssertNil(back.adjusted)
        XCTAssertEqual(back.adjustedCount, 0)
        // 有調過的存了再讀，還在
        var adjusted = old
        adjusted.adjusted = ["browTailR", "chin"]
        let again = try decoder.decode(Measurement.self, from: encoder.encode(adjusted))
        XCTAssertEqual(again.adjustedCount, 2)

        let marks = try decoder.decode(
            PhotoMarks.self, from: Data(#"{"points":{"chin":{"x":0.5,"y":0.9}},"brows":[],"eyes":[],"lips":[]}"#.utf8))
        XCTAssertNil(marks.adjusted)
        XCTAssertEqual(marks.adjustedCount, 0)
        XCTAssertEqual(marks[.chin], UV(x: 0.5, y: 0.9))
    }
}
