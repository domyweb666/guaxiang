import Foundation

/// 問古書往哪裡送。
/// 正式版一律走中繼站（repo 的 worker/），金鑰在中繼站上，app 裡沒有金鑰（HANDOFF 4-4）。
/// 中繼站還沒部署，所以 endpoint 先留空；部署好把網址填在這裡。
enum AskConfig {
    static let endpoint = ""
    static let model = "claude-sonnet-5-5"
    static let maxTokens = 900

    static var clientHeader: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        return "ios/\(version)"
    }
}

enum AskError: LocalizedError {
    case notReady
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notReady: return "問古書還沒開通。"
        case .server(let message): return message
        }
    }
}

/// 送出去的只有文字：依據清單、簡介、問題、前幾輪問答。照片、臉部座標、深度資料都不在裡面（鐵則 1）。
struct AskClient {
    struct Payload: Encodable {
        struct Item: Encodable {
            let id: String
            let title: String
            let text: String
        }

        let pack: [Item]
        let profile: Profile
        let question: String
        let history: [Prompt.Exchange]
    }

    var session: URLSession = .shared

    static var isReady: Bool {
        !AskConfig.endpoint.isEmpty || devKey != nil
    }

    /// 開發工具裡自己貼的金鑰。正式版沒有這條路
    static var devKey: String? {
        #if DEVTOOLS
            return Keychain.get(Storage.Keys.devAPIKey)
        #else
            return nil
        #endif
    }

    func ask(pack: [Evidence], profile: Profile, question: String, history: [Prompt.Exchange]) async throws -> String {
        if let url = URL(string: AskConfig.endpoint), !AskConfig.endpoint.isEmpty {
            return try await viaRelay(url, pack: pack, profile: profile, question: question, history: history)
        }
        if let key = Self.devKey {
            return try await direct(key, pack: pack, profile: profile, question: question, history: history)
        }
        throw AskError.notReady
    }

    private func viaRelay(
        _ url: URL, pack: [Evidence], profile: Profile, question: String, history: [Prompt.Exchange]
    ) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(AskConfig.clientHeader, forHTTPHeaderField: "x-guaxiang-client")
        request.httpBody = try JSONEncoder().encode(
            Payload(
                pack: pack.map { .init(id: $0.id, title: $0.title, text: $0.text) }, profile: profile,
                question: question, history: history))
        let (data, response) = try await session.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, let text = json?["text"] as? String
        else {
            throw AskError.server((json?["error"] as? String) ?? "中繼站沒有回應，請晚點再試。")
        }
        return text
    }

    private func direct(
        _ key: String, pack: [Evidence], profile: Profile, question: String, history: [Prompt.Exchange]
    ) async throws -> String {
        struct Body: Encodable {
            let model: String
            let max_tokens: Int
            let system: String
            let messages: [Prompt.Message]
        }
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { throw AskError.notReady }
        let built = Prompt.buildRequest(pack: pack, profile: profile, question: question, history: history)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONEncoder().encode(
            Body(
                model: AskConfig.model, max_tokens: AskConfig.maxTokens, system: built.system,
                messages: built.messages))
        let (data, response) = try await session.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let detail = (json?["error"] as? [String: Any])?["message"] as? String
            throw AskError.server(detail ?? "AI 服務暫時無法回答。")
        }
        let blocks = json?["content"] as? [[String: Any]] ?? []
        return blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }
            .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
