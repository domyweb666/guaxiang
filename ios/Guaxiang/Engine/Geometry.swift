import Foundation

/// 臉上的一個點。x 往畫面右邊（本人的左邊）變大，y 往下變大，z 越小越靠近鏡頭。
/// 網頁版用的是畫面像素；iOS 用的是把 ARKit 的臉攤平後的公尺。特徵全部是比例，所以單位不影響結果。
struct Pt: Equatable {
    var x: Double
    var y: Double
    var z: Double = 0
}

/// 臉上叫得出名字的點。括號裡是網頁版 MediaPipe 的點位編號，公式跟 index.html 的 features() 對得上。
/// R 是本人的右邊（畫面上 x 比較小的那一邊），L 是本人的左邊。
enum LM: String, CaseIterable, Codable {
    case cheekR, cheekL // 臉最寬處 234、454
    case glabella // 眉心 9
    case subnasale // 鼻底 2
    case chin // 下巴 152
    case top // 網格最上面 10
    case templeR, templeL // 額寬 54、284
    case jawR, jawL // 下顎角 172、397
    case eyeOuterR, eyeInnerR, eyeOuterL, eyeInnerL // 外眼角、內眼角 33、133、263、362
    case eyeTopR, eyeBottomR, eyeTopL, eyeBottomL // 上下眼瞼 159、145、386、374
    case browTailR, browHeadR, browTailL, browHeadL // 眉尾、眉頭 70、107、300、336
    case noseRoot // 山根 168
    case noseBridge1, noseBridge2, noseBridge3, noseBridge4 // 鼻樑 6、197、195、5
    case noseTip // 鼻尖 1
    case mouthR, mouthL // 嘴角 61、291
    case lipTop, lipInnerTop, lipInnerBottom, lipBottom // 上唇峰、唇縫上下、下唇底 0、13、14、17
    case pupilR, pupilL // 瞳孔 468、473
    case cheekFrontR, cheekFrontL // 顴前點 50、280
}

typealias FaceFrame = [LM: Pt]

enum Geometry {
    static func dist(_ a: Pt, _ b: Pt) -> Double {
        hypot(a.x - b.x, a.y - b.y)
    }

    /// 以 b 為頂點，a-b-c 的夾角（度）
    static func angleAt(_ a: Pt, _ b: Pt, _ c: Pt) -> Double {
        let v1x = a.x - b.x, v1y = a.y - b.y
        let v2x = c.x - b.x, v2y = c.y - b.y
        let cosine = (v1x * v2x + v1y * v2y) / (hypot(v1x, v1y) * hypot(v2x, v2y))
        return acos(max(-1, min(1, cosine))) * 180 / .pi
    }

    /// 點 p 到直線 a-b 的距離
    static func distToLine(_ p: Pt, _ a: Pt, _ b: Pt) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        return abs(dy * p.x - dx * p.y + b.x * a.y - b.y * a.x) / hypot(dx, dy)
    }

    /// 用兩眼瞳孔的連線把臉轉正（沒有瞳孔就用兩個外眼角）。回傳轉正後的點，和同一個轉法。
    static func align(_ frame: FaceFrame) -> (points: FaceFrame, rotate: (Pt) -> Pt)? {
        let left: Pt, right: Pt
        if let a = frame[.pupilR], let b = frame[.pupilL] {
            left = a
            right = b
        } else if let a = frame[.eyeOuterR], let b = frame[.eyeOuterL] {
            left = a
            right = b
        } else {
            return nil
        }
        let angle = atan2(right.y - left.y, right.x - left.x)
        let c = cos(-angle), s = sin(-angle)
        let ox = (left.x + right.x) / 2, oy = (left.y + right.y) / 2
        let rotate: (Pt) -> Pt = { p in
            Pt(x: ox + (p.x - ox) * c - (p.y - oy) * s, y: oy + (p.x - ox) * s + (p.y - oy) * c, z: p.z)
        }
        return (frame.mapValues(rotate), rotate)
    }
}
