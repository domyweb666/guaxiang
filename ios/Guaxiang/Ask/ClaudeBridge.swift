import Foundation

/// 電腦上的 Claude CLI 轉接（ios/tools/claude-bridge）。開發測試用，上架前拿掉。
/// 網址長 http://192.168.0.173:8790/ask?t=32 個英數字，含密碼，所以存鑰匙圈，不進匯出
struct ClaudeBridge: Equatable {
    let askURL: URL

    /// 只收自己網路裡的位址：文字是用沒加密的 http 送的，不能送到外面去
    init?(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parts = URLComponents(string: text), parts.scheme?.lowercased() == "http", parts.path == "/ask",
            parts.user == nil, parts.password == nil,
            let host = parts.host, Self.isLocal(host), let url = parts.url,
            let token = parts.queryItems?.first(where: { $0.name == "t" })?.value,
            token.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil
        else { return nil }
        askURL = url
    }

    static func isLocal(_ host: String) -> Bool {
        if host == "localhost" || host == "127.0.0.1" { return true }
        if host.hasSuffix(".local") { return true }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) ?? -1 }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
        switch (parts[0], parts[1]) {
        case (10, _), (192, 168): return true
        case (172, 16...31): return true
        default: return false
        }
    }

    var pingURL: URL? {
        var parts = URLComponents(url: askURL, resolvingAgainstBaseURL: false)
        parts?.path = "/ping"
        return parts?.url
    }

    /// 畫面上只露位址，不露密碼
    var masked: String {
        let host = askURL.host ?? ""
        guard let port = askURL.port else { return host }
        return "\(host):\(port)"
    }

    static let notFound = "連不到電腦。看三件事：手機和電腦連同一個 Wi-Fi；電腦上的轉接程式開著；iPhone 的設定 → 隱私權與安全性 → 區域網路，瓜相有打開。"
    static let dropped = "等到一半斷線了。等回答的時候切到別的 app、鎖螢幕或換 Wi-Fi 都會斷，按重試再問一次。"
    static let wrongPassword = "密碼對不上。電腦上的轉接程式重開過，密碼就會換，到設定 → 開發工具重新掃一次。"

    #if DEVTOOLS
        /// 現在連的那一台。沒連就是 nil
        static var current: ClaudeBridge? {
            Keychain.get(Storage.Keys.devBridge).flatMap { ClaudeBridge($0) }
        }

        func save() {
            Keychain.set(askURL.absoluteString, for: Storage.Keys.devBridge)
        }

        static func disconnect() {
            Keychain.delete(Storage.Keys.devBridge)
        }

        /// 看電腦那頭在不在，回電腦的名字
        func ping(session: URLSession = .shared) async throws -> String {
            guard let url = pingURL else { throw AskError.server(Self.notFound) }
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            let result: (Data, URLResponse)
            do {
                result = try await session.data(for: request)
            } catch {
                throw AskError.server(Self.notFound)
            }
            let status = (result.1 as? HTTPURLResponse)?.statusCode
            if status == 401 { throw AskError.server(Self.wrongPassword) }
            let json = (try? JSONSerialization.jsonObject(with: result.0)) as? [String: Any]
            guard status == 200, let name = json?["name"] as? String else {
                throw AskError.server("連上了，但對方不是瓜相的轉接程式。看一下電腦上開的是不是 ios/tools/claude-bridge。")
            }
            return name
        }
    #else
        static var current: ClaudeBridge? { nil }
    #endif
}
