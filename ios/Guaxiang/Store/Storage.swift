import Foundation
import Security

/// 手機裡存的東西：上一次的量測數字、照片、簡介、問答紀錄。都在 App 自己的資料夾裡，不上傳。
final class Storage {
    static let shared = Storage()

    enum File: String, CaseIterable {
        case measurement = "measurement.json"
        case profile = "profile.json"
        case chat = "chat.json"
        case photo = "photo.jpg"
        case photoMarks = "photo.json"
    }

    private let directory: URL

    init(directory: URL? = nil) {
        let base =
            directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Guaxiang", isDirectory: true)
        self.directory = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    private func url(_ file: File) -> URL {
        directory.appendingPathComponent(file.rawValue)
    }

    func load<T: Decodable>(_ type: T.Type, from file: File) -> T? {
        guard let data = try? Data(contentsOf: url(file)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    func save<T: Encodable>(_ value: T, to file: File) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url(file), options: [.atomic, .completeFileProtection])
    }

    func data(_ file: File) -> Data? {
        try? Data(contentsOf: url(file))
    }

    /// 存檔，而且不跟著 iCloud／電腦備份離開這支手機
    func saveLocalOnly(_ data: Data, to file: File) {
        try? data.write(to: url(file), options: [.atomic, .completeFileProtection])
        excludeFromBackup(file)
    }

    func excludeFromBackup(_ file: File) {
        var target = url(file)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? target.setResourceValues(values)
    }

    func remove(_ file: File) {
        try? FileManager.default.removeItem(at: url(file))
    }

    /// 「清除所有資料」：報告、照片、簡介、問答紀錄、同意紀錄、開發用的金鑰和電腦連線，全部刪掉
    func eraseAll() {
        finishPhotoWrites()
        File.allCases.forEach(remove)
        UserDefaults.standard.removeObject(forKey: Keys.aiConsent)
        UserDefaults.standard.removeObject(forKey: Keys.questionsAsked)
        Keychain.delete(Keys.devAPIKey)
        Keychain.delete(Keys.devBridge)
    }

    enum Keys {
        static let aiConsent = "ai.consent"
        static let questionsAsked = "ask.count"
        static let devAPIKey = "dev.anthropic.key"
        static let devBridge = "dev.claude.bridge"
    }
}

/// 問答紀錄跟著某一次報告走；重新掃描後舊的問答就不再顯示
struct ChatLog: Codable {
    var reportWhen: Date
    var entries: [ChatEntry]
}

struct ChatEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var q: String
    var a: String
    var pack: [Evidence]
    var t: Date
    /// 回答的種類。舊版存的沒有這一格
    var kind: AskReply.Kind?
    /// 沒問成的原因。問題留著，可以重試
    var error: String?

    /// 整理過、可以顯示的回答。還在等、沒問成的是 nil
    var reply: AskReply? {
        if let kind { return AskReply(kind: kind, answer: a) }
        return a.isEmpty ? nil : AskReply(kind: .answer, answer: a)
    }

    /// 送出去了、還沒回來
    var waiting: Bool { reply == nil && error == nil }

    /// 給下一題當前情提要的。沒問成的不算
    var exchange: Prompt.Exchange? {
        reply.map { Prompt.Exchange(q: q, a: $0.answer, kind: $0.kind) }
    }
}

/// 鑰匙圈：只給開發工具存自己貼的金鑰和電腦連線用。正式版走中繼站，app 裡沒有金鑰。
enum Keychain {
    private static let service = "org.domyweb.guaxiang"

    static func set(_ value: String, for key: String) {
        delete(key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// 收費骨架（HANDOFF 第八節，2026-11-21 多米選「照建議先放骨架」）：
/// 買斷解鎖完整報告、含 10 題問古書，之後題包加購。
/// 沒付費的人只能問 5 題（多米 2026-11-26 定）。這 5 題是總數，不是每天；買了再加 10 題。
/// 價格還沒定、StoreKit 還沒接，所以現在 enforced 是 false，全部功能開著；第 8 步接 StoreKit 時從這裡接。
enum Paywall {
    static let fullReportProductID = "org.domyweb.guaxiang.full"
    static let questionPackProductID = "org.domyweb.guaxiang.questions10"
    static let freeQuestions = 5
    static let includedQuestions = 10
    static let enforced = false

    /// 買了完整版沒有。第 8 步接 StoreKit 時改成讀購買紀錄
    static var purchased: Bool { false }

    static var questionsAsked: Int {
        UserDefaults.standard.integer(forKey: Storage.Keys.questionsAsked)
    }

    /// 總共能問幾題：免費 5 題，買了完整版再加 10 題
    static func allowance(purchased: Bool) -> Int {
        freeQuestions + (purchased ? includedQuestions : 0)
    }

    /// 還剩幾題，不會小於 0
    static func left(asked: Int, purchased: Bool) -> Int {
        max(0, allowance(purchased: purchased) - asked)
    }

    /// 還能問幾題。nil 表示現在不限
    static var questionsLeft: Int? {
        enforced ? left(asked: questionsAsked, purchased: purchased) : nil
    }

    /// 題數用完時聊天裡顯示的那句。沒買的指向完整版，不寫價格
    static var outOfQuestions: String {
        purchased
            ? "這份報告附的題數用完了。"
            : "免費的 \(freeQuestions) 題問完了。買完整版可以再問 \(includedQuestions) 題。"
    }

    static var canSeeFullReport: Bool { true }

    static func noteAsked() {
        UserDefaults.standard.set(questionsAsked + 1, forKey: Storage.Keys.questionsAsked)
    }
}
