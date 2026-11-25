import Foundation

/// rules.json 的樣子。規則庫跟網頁版共用同一個檔（repo 根目錄），這裡只負責讀，不另外抄一份數值。
struct Rules: Decodable {
    let version: String
    let features: [String: FeatureDef]
    let thresholds: [String: Threshold]
    let officials: [Official]
    let rules: [Rule]
    let wuxing: Wuxing
    let cannotSee: [CannotSee]
    let palacesNote: String
    let palacesTerms: String
    let palaces: [Palace]
    let liunian: Liunian

    static func decode(_ data: Data) throws -> Rules {
        try JSONDecoder().decode(Rules.self, from: data)
    }

    static func load(from bundle: Bundle = .main) throws -> Rules {
        guard let url = bundle.url(forResource: "rules", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try decode(Data(contentsOf: url))
    }

    func threshold(_ key: String) -> Double? {
        thresholds[key]?.value
    }
}

/// name、formula 給開發核對用（有點位編號），畫面上只用 plainName、plainFormula
struct FeatureDef: Decodable {
    let name: String
    let formula: String
    let unit: String
    let plainName: String
    let plainFormula: String
    let scale: RulerScale?
}

/// 刻度尺的兩端：最左和最右各是多少、寫什麼字。暫定值，只管畫面
struct RulerScale: Decodable {
    let from: Double
    let to: Double
    let left: String
    let right: String
}

struct Threshold: Decodable {
    let value: Double
    let note: String
    /// 這條線為什麼畫在這裡，白話
    let plain: String
}

/// 一個條件：哪個特徵、怎麼比、門檻是哪一個（或直接給數字）。十二宮的 measure 也是這個形狀
struct Condition: Decodable {
    let feature: String?
    let op: String?
    let th: String?
    let value: Double?
    let label: String?
    /// 這一條在看什麼，白話（例如「鼻樑直不直」）
    let plain: String?
    let yes: String?
    let no: String?
    let type: String?
    /// 不畫刻度尺：原文沒有寫這個樣子，畫了會像古書說的
    let noRuler: Bool?
}

struct Official: Decodable, Identifiable {
    let id: String
    let name: String
    let organ: String
    let conditions: [Condition]
    let unjudged: String?
    let notMeasured: [String]?
    let blockedBy: String?
    let baihua: String
    let source: String
    let lit: String
    let litPlain: String
    /// 古書裡這個部位叫什麼
    let terms: String
    let plain: String
    let governs: String
}

struct Rule: Decodable, Identifiable {
    let id: String
    let part: String
    let when: When
    let needHairline: Bool?
    let experimental: Bool?
    let yuanwen: String?
    /// 原文逐句的白話
    let yuanwenPlain: String?
    let source: String
    let baihua: String
    let lit: String
    let litPlain: String
    /// 這一條用到的古書叫法
    let terms: String
    let headline: String?
    let note: String?
}

/// rules.json 裡 when 有兩種寫法：單一條件，或 { "all": [條件…] }
struct When: Decodable {
    let conditions: [Condition]

    private enum Keys: String, CodingKey {
        case all
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: Keys.self)
        if let all = try box.decodeIfPresent([Condition].self, forKey: .all) {
            conditions = all
        } else {
            conditions = [try Condition(from: decoder)]
        }
    }
}

struct Wuxing: Decodable {
    let note: String
    let types: [String: WuxingType]
    let summary: String
    let notFault: String
    let source: String
    let terms: String
    let sheng: [String: String]
    let ke: [String: String]
    let keRule: [String: String]
    /// 兩種形放在一起的說法，白話
    let keRulePlain: [String: String]
    let notFaultPlain: String
    let guan: String
    let guanTerms: String
}

struct WuxingType: Decodable {
    let shape: String
    let yuanwen: String
    let plainShape: String
    let plainLine: String
}

struct CannotSee: Decodable {
    let name: String
    let why: String
    let plain: String
    let yuanwen: String?
    let baihua: String?
}

struct Palace: Decodable, Identifiable {
    let id: String
    let topic: String
    let name: String
    let modern: String?
    let place: String
    /// 這個位置古書叫什麼
    let whereTerm: String?
    let terms: String?
    let yuanwen: String?
    let baihua: String?
    let measure: Condition?
    let blockedBy: String?
    let notMeasured: String?
    let why: String?
    let note: String?
    let noQuoteWhy: String?
    let source: String?

    private enum CodingKeys: String, CodingKey {
        case id, topic, name, modern, whereTerm, terms, yuanwen, baihua, measure, blockedBy, notMeasured, why, note
        case noQuoteWhy, source
        case place = "where"
    }
}

struct Liunian: Decodable {
    let note: String
    let source: String
    let table: [LiunianRow]
}

struct LiunianRow: Decodable {
    let from: Int
    let to: Int
    let name: String
    let place: String
    let layer: String
    let link: String?

    private enum CodingKeys: String, CodingKey {
        case from, to, name, layer, link
        case place = "where"
    }

    /// layer 的白話：「兄弟宮（兄弟朋友）、保壽官（眉毛）」→「兄弟朋友、眉毛」
    var plainLayer: String {
        layer.components(separatedBy: "、").compactMap { item -> String? in
            guard let open = item.firstIndex(of: "（"), let close = item.lastIndex(of: "）"), open < close else {
                return nil
            }
            return String(item[item.index(after: open)..<close])
        }.joined(separator: "、")
    }
}
