import Foundation

/// 一張畫面 → 18 個特徵。算法逐行照網頁版 index.html 的 features()，
/// 差別只有一個：缺哪個點，用到它的特徵就不算（之後報告會寫「沒判」），不拿別的點硬湊。
enum FeatureEngine {
    /// 數字明細表的排列順序
    static let order = [
        "santing_U", "santing_M", "santing_L", "santing_dev", "face_aspect", "fore_jaw", "jaw_angle",
        "brow_eye", "brow_tail", "yintang", "eye_lw", "nose_dev", "mouth_ipd", "mouth_corner",
        "lip_thick", "renzhong", "nose_prom", "cheek_prom"
    ]

    /// 用「度」當單位的特徵：不穩和邊緣的判法跟比例類不一樣
    static let degreeFeatures: Set<String> = ["jaw_angle", "brow_tail"]

    /// - Parameters:
    ///   - hairRatio: 髮際到眉心的距離 ÷ 臉寬。沒拉髮際線就是 nil
    ///   - eps: 眼高的下限，避免除以零。網頁版是 1 個像素；公尺制給很小的數
    static func features(_ raw: FaceFrame, hairRatio: Double?, eps: Double) -> [String: Double] {
        guard let aligned = Geometry.align(raw) else { return [:] }
        let A = aligned.points
        var f: [String: Double] = [:]
        let dist = Geometry.dist

        // 臉寬、三停、臉長寬比
        if let cheekR = A[.cheekR], let cheekL = A[.cheekL], let glabella = A[.glabella],
            let subnasale = A[.subnasale], let chin = A[.chin]
        {
            let width = dist(cheekR, cheekL)
            let middle = subnasale.y - glabella.y
            let lower = chin.y - subnasale.y
            if let hairRatio {
                let upper = hairRatio * width
                let mean = (upper + middle + lower) / 3
                let u = upper / mean, m = middle / mean, l = lower / mean
                f["santing_U"] = u
                f["santing_M"] = m
                f["santing_L"] = l
                f["santing_dev"] = max(abs(u - 1), abs(m - 1), abs(l - 1))
                f["face_aspect"] = (chin.y - (glabella.y - upper)) / width
            } else {
                if let top = A[.top] {
                    f["face_aspect"] = (chin.y - top.y) * 1.12 / width
                }
                f["santing_L_ml"] = lower / ((middle + lower) / 2) // 只有中下停可比
            }
            if let lipTop = A[.lipTop] {
                f["renzhong"] = dist(subnasale, lipTop) / lower
            }
            if let root = A[.noseRoot], let tip = A[.noseTip], let b1 = A[.noseBridge1],
                let b2 = A[.noseBridge2], let b3 = A[.noseBridge3], let b4 = A[.noseBridge4]
            {
                let worst = [b1, b2, b3, b4].map { Geometry.distToLine($0, root, tip) }.max() ?? 0
                f["nose_dev"] = worst / width
            }
            if let frontR = A[.cheekFrontR], let frontL = A[.cheekFrontL] {
                let front = (frontR.z + frontL.z) / 2
                if let tip = A[.noseTip] {
                    f["nose_prom"] = (front - tip.z) / width
                }
                f["cheek_prom"] = ((cheekR.z + cheekL.z) / 2 - front) / width
            }
        }

        // 額寬 ÷ 下顎寬、下顎角
        if let templeR = A[.templeR], let templeL = A[.templeL], let jawR = A[.jawR], let jawL = A[.jawL] {
            f["fore_jaw"] = dist(templeR, templeL) / dist(jawR, jawL)
        }
        if let cheekR = A[.cheekR], let cheekL = A[.cheekL], let jawR = A[.jawR], let jawL = A[.jawL],
            let chin = A[.chin]
        {
            f["jaw_angle"] = (Geometry.angleAt(cheekR, jawR, chin) + Geometry.angleAt(cheekL, jawL, chin)) / 2
        }

        // 眼、眉
        if let outerR = A[.eyeOuterR], let innerR = A[.eyeInnerR], let outerL = A[.eyeOuterL],
            let innerL = A[.eyeInnerL]
        {
            let eyeR = dist(outerR, innerR), eyeL = dist(outerL, innerL)
            let eye = (eyeR + eyeL) / 2
            if let tailR = A[.browTailR], let tailL = A[.browTailL] {
                // 眉尾超出外眼角多少（以眼長為單位）：右側往 x 小的方向、左側往 x 大的方向
                f["brow_eye"] = ((outerR.x - tailR.x) / eyeR + (tailL.x - outerL.x) / eyeL) / 2
            }
            if let headR = A[.browHeadR], let headL = A[.browHeadL] {
                f["yintang"] = dist(headR, headL) / eye
            }
            if let topR = A[.eyeTopR], let bottomR = A[.eyeBottomR], let topL = A[.eyeTopL],
                let bottomL = A[.eyeBottomL]
            {
                f["eye_lw"] = (eyeR / max(eps, dist(topR, bottomR)) + eyeL / max(eps, dist(topL, bottomL))) / 2
            }
        }
        if let headR = A[.browHeadR], let tailR = A[.browTailR], let headL = A[.browHeadL],
            let tailL = A[.browTailL]
        {
            let tail: (Pt, Pt) -> Double = { head, end in
                atan2(head.y - end.y, abs(end.x - head.x)) * 180 / .pi
            }
            f["brow_tail"] = (tail(headR, tailR) + tail(headL, tailL)) / 2
        }

        // 嘴
        if let mouthR = A[.mouthR], let mouthL = A[.mouthL] {
            let mouthWidth = dist(mouthR, mouthL)
            if let a = A[.pupilR] ?? A[.eyeOuterR], let b = A[.pupilL] ?? A[.eyeOuterL] {
                f["mouth_ipd"] = mouthWidth / dist(a, b)
            }
            if let innerTop = A[.lipInnerTop], let innerBottom = A[.lipInnerBottom] {
                let lipMid = (innerTop.y + innerBottom.y) / 2
                let corners = (mouthR.y + mouthL.y) / 2
                f["mouth_corner"] = (lipMid - corners) / mouthWidth
                if let lipTop = A[.lipTop], let lipBottom = A[.lipBottom] {
                    f["lip_thick"] = (dist(lipTop, innerTop) + dist(innerBottom, lipBottom)) / mouthWidth
                }
            }
        }

        return f.filter { $0.value.isFinite }
    }

    /// 網頁版的髮際線算法：把使用者拉的那個點跟著臉一起轉正，量它在眉心上方多遠，再除以臉寬。
    /// 拉得太離譜（不到 0.15 或超過 1.2 個臉寬）就當沒拉。
    static func hairRatio(best: FaceFrame, hairPoint: Pt) -> Double? {
        guard let aligned = Geometry.align(best), let glabella = aligned.points[.glabella],
            let cheekR = aligned.points[.cheekR], let cheekL = aligned.points[.cheekL]
        else { return nil }
        let hair = aligned.rotate(hairPoint)
        return validHairRatio((glabella.y - hair.y) / Geometry.dist(cheekR, cheekL))
    }

    /// iOS 版的髮際線算法。使用者在照片上拉一條橫線，照片上的眉心和下巴位置已知，
    /// 沿著「下巴 → 眉心」這條臉的中軸往上延伸到那條線，量出線在眉心上方多少，再換算成臉的尺寸。
    /// - Parameters:
    ///   - lineY: 髮際線在照片上的高度（像素，從上往下）
    ///   - glabella、chin: 眉心和下巴在照片上的位置（像素）
    ///   - faceGlabellaToChin: 眉心到下巴在臉平面上的距離
    ///   - faceWidth: 臉寬（跟上一個同單位）
    static func hairRatio(
        lineY: Double, glabella: Pt, chin: Pt, faceGlabellaToChin: Double, faceWidth: Double
    ) -> Double? {
        let length = Geometry.dist(glabella, chin)
        guard length > 1, faceWidth > 0 else { return nil }
        let upY = (glabella.y - chin.y) / length
        guard upY < -0.5 else { return nil } // 臉在照片裡要是正的（眉心在下巴上面）
        let pixelsAbove = (lineY - glabella.y) / upY
        return validHairRatio(pixelsAbove * faceGlabellaToChin / length / faceWidth)
    }

    static func validHairRatio(_ ratio: Double) -> Double? {
        ratio > 0.15 && ratio < 1.2 ? ratio : nil
    }
}
