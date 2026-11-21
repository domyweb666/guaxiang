import Foundation

/// ARKit 臉部網格的頂點對照表：哪一個頂點編號，對應網頁版用的哪一個點（眉心、外眼角、鼻尖…）。
/// ARKit 的網格有一千兩百多個頂點，編號是固定的，但官方沒有公布哪一號在哪裡，所以要在真機上對（HANDOFF 4-2）。
/// 對好的表放在 Resources/arkit-vertex-map.json 一起打包；開發工具裡對到一半的存在手機上，會優先用。
struct VertexMap: Codable, Equatable {
    var note: String?
    var indices: [String: Int] = [:]

    /// 從網格拿的點。眉毛和嘴唇不在這裡：網格是皮膚表面，量不到眉毛，嘴唇輪廓也被抹平，那幾點由 Vision 從照片上找。
    /// 瞳孔也不在這裡：ARKit 直接給兩顆眼球的位置。
    static let meshLandmarks: [LM] = [
        .cheekR, .cheekL, .glabella, .subnasale, .chin, .top, .templeR, .templeL, .jawR, .jawL,
        .eyeOuterR, .eyeInnerR, .eyeOuterL, .eyeInnerL, .eyeTopR, .eyeBottomR, .eyeTopL, .eyeBottomL,
        .noseRoot, .noseBridge1, .noseBridge2, .noseBridge3, .noseBridge4, .noseTip,
        .cheekFrontR, .cheekFrontL
    ]

    static let overrideKey = "dev.vertexMap"

    static func bundled(_ bundle: Bundle = .main) -> VertexMap {
        guard let url = bundle.url(forResource: "arkit-vertex-map", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let map = try? JSONDecoder().decode(VertexMap.self, from: data)
        else { return VertexMap() }
        return map
    }

    /// 現在要用的那一份：手機上有對到一半的就用它，沒有就用打包進來的
    static func current() -> VertexMap {
        if let data = UserDefaults.standard.data(forKey: overrideKey),
            let map = try? JSONDecoder().decode(VertexMap.self, from: data), !map.indices.isEmpty
        {
            return map
        }
        return bundled()
    }

    func saveAsOverride() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.overrideKey)
        }
    }

    static func clearOverride() {
        UserDefaults.standard.removeObject(forKey: overrideKey)
    }

    subscript(_ lm: LM) -> Int? {
        get { indices[lm.rawValue] }
        set { indices[lm.rawValue] = newValue }
    }

    var missing: [LM] {
        Self.meshLandmarks.filter { indices[$0.rawValue] == nil }
    }

    var isComplete: Bool { missing.isEmpty }

    /// 貼回 repo 用的 JSON（排好序，方便比對）
    var exportJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var copy = self
        copy.note = "ARKit 臉部網格頂點對照表。用 app 裡的開發工具在真機上對出來的，不要憑記憶改編號。"
        guard let data = try? encoder.encode(copy) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

extension LM {
    /// 給人看的名字。「你的右邊」是本人的右邊，不是畫面的右邊
    var plainName: String {
        switch self {
        case .cheekR: return "臉最寬的地方（你的右邊）"
        case .cheekL: return "臉最寬的地方（你的左邊）"
        case .glabella: return "眉心（兩眉中間）"
        case .subnasale: return "鼻底（鼻子和人中交界）"
        case .chin: return "下巴最下面"
        case .top: return "額頭最上面正中間（網格頂端）"
        case .templeR: return "額頭側邊、眉尾上方（你的右邊）"
        case .templeL: return "額頭側邊、眉尾上方（你的左邊）"
        case .jawR: return "下顎轉角（你的右邊）"
        case .jawL: return "下顎轉角（你的左邊）"
        case .eyeOuterR: return "右眼外眼角"
        case .eyeInnerR: return "右眼內眼角"
        case .eyeOuterL: return "左眼外眼角"
        case .eyeInnerL: return "左眼內眼角"
        case .eyeTopR: return "右眼上眼瞼中間"
        case .eyeBottomR: return "右眼下眼瞼中間"
        case .eyeTopL: return "左眼上眼瞼中間"
        case .eyeBottomL: return "左眼下眼瞼中間"
        case .browTailR: return "右眉眉尾"
        case .browHeadR: return "右眉眉頭"
        case .browTailL: return "左眉眉尾"
        case .browHeadL: return "左眉眉頭"
        case .noseRoot: return "山根（鼻樑最上面、兩眼中間）"
        case .noseBridge1: return "鼻樑第 1 點（山根下面）"
        case .noseBridge2: return "鼻樑第 2 點"
        case .noseBridge3: return "鼻樑第 3 點"
        case .noseBridge4: return "鼻樑第 4 點（鼻尖上面）"
        case .noseTip: return "鼻尖"
        case .mouthR: return "右嘴角"
        case .mouthL: return "左嘴角"
        case .lipTop: return "上唇最上面中間"
        case .lipInnerTop: return "唇縫上緣"
        case .lipInnerBottom: return "唇縫下緣"
        case .lipBottom: return "下唇最下面中間"
        case .pupilR: return "右眼瞳孔"
        case .pupilL: return "左眼瞳孔"
        case .cheekFrontR: return "顴骨前面最高的地方（你的右邊）"
        case .cheekFrontL: return "顴骨前面最高的地方（你的左邊）"
        }
    }

    /// 網頁版 MediaPipe 的點位編號，對照 index.html 用
    var mediapipeIndex: Int {
        switch self {
        case .cheekR: return 234
        case .cheekL: return 454
        case .glabella: return 9
        case .subnasale: return 2
        case .chin: return 152
        case .top: return 10
        case .templeR: return 54
        case .templeL: return 284
        case .jawR: return 172
        case .jawL: return 397
        case .eyeOuterR: return 33
        case .eyeInnerR: return 133
        case .eyeOuterL: return 263
        case .eyeInnerL: return 362
        case .eyeTopR: return 159
        case .eyeBottomR: return 145
        case .eyeTopL: return 386
        case .eyeBottomL: return 374
        case .browTailR: return 70
        case .browHeadR: return 107
        case .browTailL: return 300
        case .browHeadL: return 336
        case .noseRoot: return 168
        case .noseBridge1: return 6
        case .noseBridge2: return 197
        case .noseBridge3: return 195
        case .noseBridge4: return 5
        case .noseTip: return 1
        case .mouthR: return 61
        case .mouthL: return 291
        case .lipTop: return 0
        case .lipInnerTop: return 13
        case .lipInnerBottom: return 14
        case .lipBottom: return 17
        case .pupilR: return 468
        case .pupilL: return 473
        case .cheekFrontR: return 50
        case .cheekFrontL: return 280
        }
    }

    /// 這個點應該在本人的哪一邊：-1 右邊、+1 左邊、0 中線
    var side: Int {
        switch self {
        case .cheekR, .templeR, .jawR, .eyeOuterR, .eyeInnerR, .eyeTopR, .eyeBottomR, .browTailR, .browHeadR,
            .mouthR, .pupilR, .cheekFrontR:
            return -1
        case .cheekL, .templeL, .jawL, .eyeOuterL, .eyeInnerL, .eyeTopL, .eyeBottomL, .browTailL, .browHeadL,
            .mouthL, .pupilL, .cheekFrontL:
            return 1
        default:
            return 0
        }
    }
}
