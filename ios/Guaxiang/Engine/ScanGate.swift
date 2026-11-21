import Foundation
import simd

/// 一張畫面合不合格。條件和提示句照網頁版 processFrame()，
/// 差別：網頁版用「臉佔畫面多寬」判遠近，iOS 直接用臉離鏡頭幾公尺（暫定 25–45 公分，見 .vibe/代決清單.md）。
enum ScanGate {
    struct Input {
        var faceCount = 0
        /// 臉離鏡頭的距離（公尺）
        var distance = 0.0
        /// 臉上的平均亮度 0–255
        var lumaMean = 0.0
        /// 左右臉亮度差 ÷ 比較亮的那一邊
        var lumaSideDiff = 0.0
        var yaw = 0.0
        var pitch = 0.0
        var roll = 0.0
        var smile = 0.0
        var frown = 0.0
        var jawOpen = 0.0
        var blink = 0.0
    }

    enum Verdict: Equatable {
        /// 不合格，畫面上要提示這句話
        case hint(String)
        /// 閉眼：這張不收，但不用吵使用者
        case skip
        case ok
    }

    static let needFrames = 30
    static let nearLimit = 0.25
    static let farLimit = 0.45

    static func judge(_ i: Input) -> Verdict {
        if i.faceCount == 0 { return .hint("拿下眼鏡，把臉放進框裡") }
        if i.faceCount > 1 { return .hint("請確定畫面裡只有你") }
        if i.distance > farLimit { return .hint("靠近一點") }
        if i.distance < nearLimit { return .hint("遠一點") }
        if i.lumaMean < 90 { return .hint("到光線充足的地方") }
        if i.lumaMean > 200 { return .hint("太亮了，避開直射光") }
        if i.lumaSideDiff > 0.25 { return .hint("一邊臉太暗，請面向光源") }
        if abs(i.yaw) > 8 { return .hint("請正對鏡頭") }
        if abs(i.pitch) > 8 { return .hint("不要抬頭或低頭，手機拿到眼睛高度") }
        if abs(i.roll) > 5 { return .hint("頭不要歪") }
        if i.smile > 0.3 || i.frown > 0.3 || i.jawOpen > 0.3 { return .hint("放鬆表情，不用笑") }
        if i.blink > 0.4 { return .skip }
        return .ok
    }
}

/// 頭轉了幾度。輸入是「臉 → 相機」的轉換矩陣。
/// ARKit 的相機座標是橫拿手機的方向，直拿時臉在裡面會剛好歪 90 度，所以先把最接近的 90 度倍數轉掉再算。
enum HeadPose {
    static func angles(cameraFromFace m: simd_float4x4) -> (yaw: Double, pitch: Double, roll: Double) {
        var r = simd_float3x3(
            SIMD3(m.columns.0.x, m.columns.0.y, m.columns.0.z),
            SIMD3(m.columns.1.x, m.columns.1.y, m.columns.1.z),
            SIMD3(m.columns.2.x, m.columns.2.y, m.columns.2.z))
        let rawRoll = atan2(r.columns.0.y, r.columns.0.x)
        let quarter = (rawRoll / (.pi / 2)).rounded()
        let undo = -quarter * (.pi / 2)
        let c = cos(undo), s = sin(undo)
        let rz = simd_float3x3(SIMD3(c, s, 0), SIMD3(-s, c, 0), SIMD3(0, 0, 1))
        r = rz * r
        // 跟網頁版 poseFromMatrix() 同一組公式；R(i,j) 是第 i 列第 j 行
        let R: (Int, Int) -> Float = { i, j in r[j][i] }
        let pitch = atan2(R(2, 1), R(2, 2))
        let yaw = asin(max(-1, min(1, -R(2, 0))))
        let roll = atan2(R(1, 0), R(0, 0))
        let deg = 180 / Double.pi
        return (Double(yaw) * deg, Double(pitch) * deg, Double(roll) * deg)
    }
}
