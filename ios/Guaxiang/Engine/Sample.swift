import Foundation

/// 範例報告：首頁「先看一份範例報告」和開發工具共用。
/// 數字是假的，只用來讓還沒掃過的人看報告長什麼樣（HANDOFF 第十節「範例報告」）。
/// 不存檔、不能問古書，畫面上一律標「範例」。
enum Sample {
    static func measurement(rulesVersion: String) -> Measurement {
        let values: [String: Double] = [
            "santing_U": 1.06, "santing_M": 0.95, "santing_L": 0.99, "santing_dev": 0.06,
            "face_aspect": 1.35, "fore_jaw": 0.94, "jaw_angle": 135.7, "brow_eye": 0.18, "brow_tail": 3.2,
            "yintang": 1.18, "eye_lw": 3.04, "nose_dev": 0.004, "mouth_ipd": 0.875, "mouth_corner": -0.014,
            "lip_thick": 0.30, "renzhong": 0.27, "nose_prom": 0.10, "cheek_prom": 0.146
        ]
        return Measurement(
            when: Date(timeIntervalSince1970: 1_795_000_000), frames: 30, light: 140, hasHair: true,
            answers: Answers(),
            F: values.mapValues { FeatureStat(v: $0, iqr: abs($0) * 0.01, unstable: false) },
            rulesVersion: rulesVersion, gaps: [])
    }
}
