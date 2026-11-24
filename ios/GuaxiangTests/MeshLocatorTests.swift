import XCTest

@testable import Guaxiang

/// 用一張算出來的假臉測：鼻尖、鼻底、下巴、眼睛的位置是已知的，找出來要對得上。
/// 真的 ARKit 網格在模擬器上拿不到（2026-11-24 試過，模擬器給的是空網格），所以真臉要在手機上看照片的標註。
final class MeshLocatorTests: XCTestCase {
    private struct Face {
        var vertices: [MeshVertex] = []
        var triangles: [Int] = []
    }

    private let eyeY = 0.027, tipY = -0.011, subnasaleY = -0.020, chinY = -0.094

    /// 中線的起伏：山根、鼻尖、鼻底、嘴唇
    private func bump(_ y: Double) -> Double {
        let knots: [(Double, Double)] = [
            (0.09, 0), (0.035, 0), (0.033, 0.002), (-0.011, 0.024), (-0.020, 0.008), (-0.034, 0.011), (-0.045, 0.008),
            (-0.1, 0.006)
        ]
        for (a, b) in zip(knots, knots.dropFirst()) where y <= a.0 && y >= b.0 {
            return a.1 + (b.1 - a.1) * (a.0 - y) / (a.0 - b.0)
        }
        return 0
    }

    private func face(eyeHoles: Bool = true, shift: Double = 0) -> Face {
        var out = Face()
        let columns = 61, rows = 181
        for j in 0..<rows {
            let y = 0.086 - Double(j) * 0.001
            for i in 0..<columns {
                let x = Double(i - 30) * 0.0025
                let nose = bump(y) * exp(-pow(x / 0.012, 2))
                out.vertices.append(MeshVertex(x: x + shift, y: y, z: 0.03 - 4 * x * x - y * y + nose))
            }
        }
        let inside: (Int, Int) -> Bool = { i, j in
            let x = abs(Double(i - 30) * 0.0025), y = abs(0.086 - Double(j) * 0.001 + 0.004)
            return pow(x / 0.07, 3) + pow(y / 0.09, 3) <= 1.000001
        }
        for j in 0..<(rows - 1) {
            for i in 0..<(columns - 1) {
                guard inside(i, j), inside(i + 1, j), inside(i, j + 1), inside(i + 1, j + 1) else { continue }
                let x = (Double(i - 30) + 0.5) * 0.0025, y = 0.086 - (Double(j) + 0.5) * 0.001
                let eye = pow((abs(x) - 0.032) / 0.013, 2) + pow((y - 0.027) / 0.005, 2)
                if eyeHoles, eye < 1 { continue }
                let a = j * columns + i, b = a + 1, c = a + columns, d = c + 1
                out.triangles += [a, c, b, b, c, d]
            }
        }
        return out
    }

    private func located(_ f: Face, eyeY: Double? = nil) throws -> [LM: MeshVertex] {
        let map = try MeshLocator.locate(vertices: f.vertices, triangles: f.triangles, eyeY: eyeY).get()
        return map.compactMapValues { $0.place(f.vertices) }
    }

    func testFindsEveryLandmarkWhereItIs() throws {
        let p = try located(face())
        XCTAssertEqual(Set(p.keys), Set(MeshLocator.landmarks))
        XCTAssertEqual(p[.noseTip]!.y, tipY, accuracy: 0.001)
        XCTAssertEqual(p[.subnasale]!.y, subnasaleY, accuracy: 0.0015)
        XCTAssertEqual(p[.chin]!.y, chinY, accuracy: 0.002)
        for lm in [LM.glabella, .noseRoot, .noseTip, .subnasale, .chin, .top] {
            XCTAssertEqual(p[lm]!.x, 0, accuracy: 1e-5, lm.rawValue)
        }
        // 眉心在眼睛上面，大約半個「眼睛到鼻底」
        XCTAssertEqual(p[.glabella]!.y, eyeY + 0.478 * (eyeY - subnasaleY), accuracy: 0.0015)
        // 臉的兩側取到輪廓上，左右對稱
        XCTAssertGreaterThan(p[.cheekL]!.x, 0.064)
        XCTAssertEqual(p[.cheekL]!.x, -p[.cheekR]!.x, accuracy: 1e-6)
        XCTAssertEqual(p[.jawL]!.x, -p[.jawR]!.x, accuracy: 1e-6)
        XCTAssertLessThan(p[.jawL]!.x, p[.cheekL]!.x)
        XCTAssertLessThan(p[.templeL]!.x, p[.cheekL]!.x)
    }

    func testSameMeshAlwaysGivesSamePoints() throws {
        let f = face()
        let a = try MeshLocator.locate(vertices: f.vertices, triangles: f.triangles).get()
        let b = try MeshLocator.locate(vertices: f.vertices, triangles: f.triangles).get()
        XCTAssertEqual(a, b)
    }

    func testUsesEyeHintOnlyWhenThereAreNoHoles() throws {
        let f = face(eyeHoles: false)
        XCTAssertEqual(
            MeshLocator.locate(vertices: f.vertices, triangles: f.triangles).failure, .eyes, "沒有洞也沒有提示，不能硬找")
        let p = try located(f, eyeY: eyeY)
        XCTAssertEqual(p[.subnasale]!.y, subnasaleY, accuracy: 0.0015)
        // 有洞就不理會提示
        let withHoles = try located(face(), eyeY: 0.05)
        XCTAssertEqual(withHoles[.glabella]!.y, p[.glabella]!.y, accuracy: 0.0015)
    }

    func testRejectsThingsThatAreNotAFace() {
        XCTAssertEqual(MeshLocator.locate(vertices: [], triangles: []).failure, .empty)
        // 整張臉偏到一邊：左右不對稱，整組不用
        let f = face(eyeHoles: false, shift: 0.02)
        XCTAssertNotNil(MeshLocator.locate(vertices: f.vertices, triangles: f.triangles, eyeY: eyeY).failure)
        // 上下顛倒
        var flipped = face()
        flipped.vertices = flipped.vertices.map { MeshVertex(x: $0.x, y: -$0.y, z: $0.z) }
        XCTAssertNotNil(MeshLocator.locate(vertices: flipped.vertices, triangles: flipped.triangles).failure)
    }

    func testEyeFromOutline() {
        let right = [
            Pt(x: -0.047, y: -0.030), Pt(x: -0.040, y: -0.036), Pt(x: -0.033, y: -0.037), Pt(x: -0.024, y: -0.034),
            Pt(x: -0.018, y: -0.029), Pt(x: -0.024, y: -0.026), Pt(x: -0.033, y: -0.025), Pt(x: -0.040, y: -0.026)
        ]
        let eye = Outline.eye(right, midX: 0)
        XCTAssertEqual(eye?.outer.x, -0.047)
        XCTAssertEqual(eye?.inner.x, -0.018)
        XCTAssertEqual(eye?.top.y ?? .nan, -0.037, accuracy: 0.0003)
        XCTAssertEqual(eye?.bottom.y ?? .nan, -0.025, accuracy: 0.0003)
        XCTAssertNil(Outline.eye([], midX: 0))
    }

    /// 照片跟著報告走：日期對不上就不拿，清除資料要一起刪
    func testPhotoIsKeptWithItsReportAndErased() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let storage = Storage(directory: folder)
        let when = Date(timeIntervalSince1970: 1_795_000_000)
        var marks = PhotoMarks()
        marks.when = when
        marks[.chin] = UV(x: 0.5, y: 0.8)
        marks.hairY = 0.2
        let image = UIGraphicsImageRenderer(size: CGSize(width: 30, height: 40)).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 30, height: 40))
        }
        storage.savePhoto(FacePhoto(image: image, marks: marks))
        XCTAssertEqual(storage.loadPhoto(when: when)?.marks, marks)
        XCTAssertNil(storage.loadPhoto(when: when.addingTimeInterval(60)))
        let file = folder.appendingPathComponent(Storage.File.photo.rawValue)
        XCTAssertEqual(try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        storage.removePhoto()
        XCTAssertNil(storage.loadPhoto(when: when))
    }
}

extension Result {
    fileprivate var failure: Failure? {
        if case .failure(let reason) = self { return reason }
        return nil
    }
}
