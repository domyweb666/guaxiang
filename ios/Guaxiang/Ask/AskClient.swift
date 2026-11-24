import Foundation

/// 問古書往哪裡送。
/// 正式版一律走中繼站（repo 的 worker/），金鑰在中繼站上，app 裡沒有金鑰（HANDOFF 4-4）。
/// 中繼站還沒部署，所以 endpoint 先留空；部署好把網址填在這裡。
enum AskConfig {
    static let endpoint = ""
    static let model = "claude-sonnet-5-5"
    static let maxTokens = 1500
    /// 中繼站、直連最多等這麼久
    static let timeout: TimeInterval = 60
    /// 電腦轉接一題最多 170 秒，格式不對會再問一次，前面可能還有人排隊
    static let bridgeTimeout: TimeInterval = 360

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
        case .notReady: return "問古書還沒開通，現在還不能問。"
        case .server(let message): return message
        }
    }
}

/// 送出去的只有文字：依據清單、簡介（只有年紀，沒有生日）、問題、前幾輪問答。
/// 照片、臉部座標、深度資料都不在裡面（鐵則 1）。
struct AskClient {
    struct Payload: Encodable {
        struct Item: Encodable {
            let id: String
            let title: String
            let text: String
        }

        let pack: [Item]
        let profile: ProfileWire
        let question: String
        let history: [Prompt.Exchange]
    }

    var session: URLSession = .shared

    static var isReady: Bool {
        ClaudeBridge.current != nil || !AskConfig.endpoint.isEmpty || devKey != nil
    }

    /// 開發工具裡自己貼的金鑰。正式版沒有這條路
    static var devKey: String? {
        #if DEVTOOLS
            return Keychain.get(Storage.Keys.devAPIKey)
        #else
            return nil
        #endif
    }

    /// 有連電腦就走電腦，再來是中繼站，最後是自己貼的金鑰。
    /// 回來的一律再檢查一次：跑題、健康那幾種不帶模型寫的字，不存在的編號拿掉
    func ask(pack: [Evidence], profile: Profile, question: String, history: [Prompt.Exchange]) async throws -> AskReply {
        let sendable = Prompt.usable(history)
        let reply: AskReply
        if let bridge = ClaudeBridge.current {
            reply = try await viaBridge(bridge, pack: pack, profile: profile, question: question, history: sendable)
        } else if !AskConfig.endpoint.isEmpty, let url = URL(string: AskConfig.endpoint) {
            reply = try await viaRelay(url, pack: pack, profile: profile, question: question, history: sendable)
        } else if let key = Self.devKey {
            reply = try await direct(key, pack: pack, profile: profile, question: question, history: sendable)
        } else {
            throw AskError.notReady
        }
        return reply.sanitized(validIDs: Set(pack.map(\.id)))
    }

    // MARK: 中繼站和電腦：同一個協定

    private func post(
        _ url: URL, timeout: TimeInterval, pack: [Evidence], profile: Profile, question: String,
        history: [Prompt.Exchange]
    ) async throws -> (status: Int, data: Data) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(AskConfig.clientHeader, forHTTPHeaderField: "x-guaxiang-client")
        request.httpBody = try JSONEncoder().encode(
            Payload(
                pack: pack.map { .init(id: $0.id, title: $0.title, text: $0.text) }, profile: ProfileWire(profile),
                question: question, history: history))
        let (data, response) = try await session.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }

    private func read(_ status: Int, _ data: Data, otherwise: String) throws -> AskReply {
        if status == 200, let reply = try? JSONDecoder().decode(AskReply.self, from: data) { return reply }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        throw AskError.server((json?["error"] as? String) ?? otherwise)
    }

    private func viaBridge(
        _ bridge: ClaudeBridge, pack: [Evidence], profile: Profile, question: String, history: [Prompt.Exchange]
    ) async throws -> AskReply {
        #if DEVTOOLS
            // 問一題最多等好幾分鐘，電腦關著的話不能也等那麼久：先敲門，8 秒沒應就說連不到
            _ = try await bridge.ping(session: session)
        #endif
        let result: (status: Int, data: Data)
        do {
            result = try await post(
                bridge.askURL, timeout: AskConfig.bridgeTimeout, pack: pack, profile: profile, question: question,
                history: history)
        } catch {
            // 按了停止的不算連不到
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            // 送出去了才斷的，跟一開始就連不到不一樣
            if (error as? URLError)?.code == .networkConnectionLost { throw AskError.server(ClaudeBridge.dropped) }
            throw AskError.server(ClaudeBridge.notFound)
        }
        if result.status == 401 { throw AskError.server(ClaudeBridge.wrongPassword) }
        return try read(result.status, result.data, otherwise: "電腦上的轉接程式回得怪怪的，看一下它有沒有在跑。")
    }

    private func viaRelay(
        _ url: URL, pack: [Evidence], profile: Profile, question: String, history: [Prompt.Exchange]
    ) async throws -> AskReply {
        let result = try await post(
            url, timeout: AskConfig.timeout, pack: pack, profile: profile, question: question, history: history)
        return try read(result.status, result.data, otherwise: "中繼站沒有回應，請晚點再試。")
    }

    // MARK: 自己的金鑰直連（開發用）

    private func direct(
        _ key: String, pack: [Evidence], profile: Profile, question: String, history: [Prompt.Exchange]
    ) async throws -> AskReply {
        let built = Prompt.buildRequest(pack: pack, profile: profile, question: question, history: history)
        // 格式不對自動再問一次
        for _ in 0..<2 {
            let raw = try await complete(key, system: built.system, messages: built.messages)
            if let reply = AskReply.parse(raw) { return reply }
        }
        throw AskError.server(AskReply.badFormat)
    }

    private func complete(_ key: String, system: String, messages: [Prompt.Message]) async throws -> String {
        struct Body: Encodable {
            let model: String
            let max_tokens: Int
            let system: String
            let messages: [Prompt.Message]
        }
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { throw AskError.notReady }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = AskConfig.timeout
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONEncoder().encode(
            Body(model: AskConfig.model, max_tokens: AskConfig.maxTokens, system: system, messages: messages))
        let (data, response) = try await session.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let detail = (json?["error"] as? [String: Any])?["message"] as? String
            throw AskError.server(detail ?? "AI 服務暫時無法回答。")
        }
        let blocks = json?["content"] as? [[String: Any]] ?? []
        return blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }
            .joined(separator: "\n")
    }
}
