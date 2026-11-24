import ImageIO
import UIKit
import XCTest

@testable import Guaxiang

final class PhotoOrientationTests: XCTestCase {
    /// ARKit 前鏡頭的原始畫面是橫的
    private let buffer = CGSize(width: 1440, height: 1080)

    // MARK: 四個方向的座標換法

    /// 照 EXIF 的定義：原始畫面的左上角，轉正後在哪一個角
    func testCandidatesMatchExif() {
        let corner: [CGImagePropertyOrientation: UV] = [
            .up: UV(x: 0, y: 0), .down: UV(x: 1, y: 1), .right: UV(x: 1, y: 0), .left: UV(x: 0, y: 1)
        ]
        // 原始畫面的右上角，轉正後在哪一個角
        let next: [CGImagePropertyOrientation: UV] = [
            .up: UV(x: 1, y: 0), .down: UV(x: 0, y: 1), .right: UV(x: 1, y: 1), .left: UV(x: 0, y: 0)
        ]
        XCTAssertEqual(VisionLandmarks.candidates.count, 4)
        for (orientation, dihedral) in VisionLandmarks.candidates {
            let c = VisionCalibration(orientation: orientation, toBuffer: dihedral)
            XCTAssertEqual(c.displayPoint(UV(x: 0, y: 0)), corner[orientation], "\(orientation.rawValue)")
            XCTAssertEqual(c.displayPoint(UV(x: 1, y: 0)), next[orientation], "\(orientation.rawValue)")
        }
    }

    // MARK: 用臉的位置選方向

    /// 眼睛中點在嘴的 angle 方向（原始畫面的像素，0 度朝右、90 度朝下）
    private func pick(angle: Double, length: Double = 200) -> CGImagePropertyOrientation {
        let w = Double(buffer.width), h = Double(buffer.height)
        let a = angle * .pi / 180
        let upX = cos(a), upY = sin(a)
        let mouth = (x: 720.0, y: 540.0)
        let mid = (x: mouth.x + upX * length, y: mouth.y + upY * length)
        // 兩眼在中點兩側，跟臉的方向垂直
        let eyes = [-90.0, 90.0].map { UV(x: (mid.x - upY * $0) / w, y: (mid.y + upX * $0) / h) }
        return VisionLandmarks.upright(eyes: eyes, mouth: UV(x: mouth.x / w, y: mouth.y / h), size: buffer).orientation
    }

    func testPicksUprightForAllFour() {
        XCTAssertEqual(pick(angle: -90), .up)
        XCTAssertEqual(pick(angle: 90), .down)
        XCTAssertEqual(pick(angle: 180), .right)
        XCTAssertEqual(pick(angle: 0), .left)
    }

    func testPicksNearestWhenTilted() {
        // 畫面不是正方形，44 度沒換成像素會選錯
        for tilt in [-44.0, -30, -10, 10, 30, 44] {
            XCTAssertEqual(pick(angle: -90 + tilt), .up, "\(tilt)")
            XCTAssertEqual(pick(angle: 90 + tilt), .down, "\(tilt)")
            XCTAssertEqual(pick(angle: 180 + tilt), .right, "\(tilt)")
            XCTAssertEqual(pick(angle: tilt), .left, "\(tilt)")
        }
    }

    // MARK: 照片轉正

    private let upright: PhotoMarks = {
        var m = PhotoMarks()
        m[.glabella] = UV(x: 0.5, y: 0.35)
        m[.chin] = UV(x: 0.52, y: 0.75)
        m.brows = [[UV(x: 0.3, y: 0.33), UV(x: 0.4, y: 0.32)], [UV(x: 0.6, y: 0.32), UV(x: 0.7, y: 0.33)]]
        m.eyes = [[UV(x: 0.35, y: 0.4)], [UV(x: 0.65, y: 0.4)]]
        m.lips = [UV(x: 0.45, y: 0.62), UV(x: 0.55, y: 0.62)]
        m.hairY = 0.2
        return m
    }()

    private let portrait = CGSize(width: 1080, height: 1440)

    private func size(_ d: Dihedral) -> CGSize {
        d == .rotate180 || d == .identity ? portrait : CGSize(width: portrait.height, height: portrait.width)
    }

    func testUprightStaysAsIs() {
        XCTAssertEqual(upright.turn(size: portrait), .identity)
        XCTAssertEqual(upright.turned(.identity), upright)
        XCTAssertEqual(PhotoMarks().turn(size: portrait), .identity, "沒有點可以判斷就不動")
    }

    func testEveryLyingWayTurnsBack() {
        for lie in [Dihedral.quarterA, .quarterB, .rotate180] {
            let lying = upright.turned(lie)
            let turn = lying.turn(size: size(lie))
            XCTAssertEqual(turn, lie.inverse, "\(lie)")
            assertUpright(lying.turned(turn), "\(lie)")
        }
    }

    func testFallsBackToEyesAndLips() {
        var only = upright
        only.points = [:]
        for lie in [Dihedral.identity, .quarterA, .quarterB, .rotate180] {
            XCTAssertEqual(only.turned(lie).turn(size: size(lie)), lie.inverse, "\(lie)")
        }
    }

    private func assertUpright(_ m: PhotoMarks, _ note: String) {
        guard let g = m[.glabella], let c = m[.chin] else { return XCTFail(note) }
        XCTAssertLessThan(g.y, c.y, note)
        XCTAssertNil(m.hairY, note)
        for (a, b) in zip(m.all.sorted(by: order), upright.all.sorted(by: order)) {
            XCTAssertEqual(a.x, b.x, accuracy: 1e-9, note)
            XCTAssertEqual(a.y, b.y, accuracy: 1e-9, note)
        }
        XCTAssertEqual(m.all.count, upright.all.count, note)
    }

    /// 浮點數有一點誤差，取到小數第六位再排
    private func order(_ a: UV, _ b: UV) -> Bool {
        let key: (UV) -> (Double, Double) = { (($0.x * 1e6).rounded(), ($0.y * 1e6).rounded()) }
        return key(a) < key(b)
    }

    // MARK: 像素真的跟著轉

    func testPixelsTurnWithMarks() throws {
        // 8×4 的橫照片，左半紅（額頭那邊）、右半藍（下巴那邊）：臉朝左躺
        let image = halves(width: 8, height: 4, horizontal: true)
        var marks = PhotoMarks()
        marks[.glabella] = UV(x: 0.25, y: 0.5)
        marks[.chin] = UV(x: 0.75, y: 0.5)
        let photo = FacePhoto(image: image, marks: marks).upright()
        XCTAssertEqual(photo.image.size, CGSize(width: 4, height: 8))
        XCTAssertEqual(photo.image.scale, image.scale)
        XCTAssertEqual(photo.image.imageOrientation, .up)
        XCTAssertEqual(try XCTUnwrap(photo.image.cgImage).height, 8)
        let g = try XCTUnwrap(photo.marks[.glabella])
        XCTAssertEqual(g.y, 0.25, accuracy: 1e-9)
        XCTAssertTrue(try isRed(photo.image, x: 2, y: 1), "上半要是額頭")
        XCTAssertFalse(try isRed(photo.image, x: 2, y: 6), "下半要是下巴")
    }

    func testPixelsUpsideDown() throws {
        let image = halves(width: 4, height: 8, horizontal: false)
        var marks = PhotoMarks()
        // 上半紅是下巴、下半藍是額頭
        marks[.glabella] = UV(x: 0.5, y: 0.75)
        marks[.chin] = UV(x: 0.5, y: 0.25)
        let photo = FacePhoto(image: image, marks: marks).upright()
        XCTAssertEqual(photo.image.size, image.size)
        XCTAssertFalse(try isRed(photo.image, x: 2, y: 1))
        XCTAssertTrue(try isRed(photo.image, x: 2, y: 6))
    }

    /// 橫的：左紅右藍。直的：上紅下藍
    private func halves(width: Int, height: Int, horizontal: Bool) -> UIImage {
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.red.setFill()
            context.fill(
                CGRect(
                    x: 0, y: 0, width: horizontal ? size.width / 2 : size.width,
                    height: horizontal ? size.height : size.height / 2))
        }
    }

    /// (x, y) 那一點是不是紅的，左上角是原點
    private func isRed(_ image: UIImage, x: Int, y: Int) throws -> Bool {
        let cg = try XCTUnwrap(image.cgImage?.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)))
        var pixel = [UInt8](repeating: 0, count: 4)
        try pixel.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(
                CGContext(
                    data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return pixel[0] > 128 && pixel[2] < 128
    }
}
