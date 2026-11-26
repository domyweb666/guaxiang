import Foundation

/// 一份報告的問答：問題、回答、沒問成的原因，跟送出和取消。
/// 畫面收掉時這個物件跟著沒了，還在等的那一題就取消；下次打開會看到問題還在，可以重試
@MainActor
final class AskChat: ObservableObject {
    @Published private(set) var entries: [ChatEntry] = []
    @Published private(set) var busy = false

    /// 前情提要帶幾輪
    nonisolated private static let remember = 3
    nonisolated static let stopped = "你按了停止。"
    nonisolated static let interrupted = "上次還沒等到回答就離開了。"

    private let report: Report
    private let storage: Storage
    private let client: AskClient
    private var task: Task<Void, Never>?

    init(report: Report, storage: Storage = .shared, client: AskClient = AskClient()) {
        self.report = report
        self.storage = storage
        self.client = client
        if let log = storage.load(ChatLog.self, from: .chat), log.reportWhen == report.measurement.when {
            entries = Self.settled(log.entries)
        }
    }

    deinit {
        task?.cancel()
    }

    /// 存檔裡還在等的，代表上次等到一半就離開了
    nonisolated static func settled(_ saved: [ChatEntry]) -> [ChatEntry] {
        saved.map { entry in
            var out = entry
            if out.waiting { out.error = interrupted }
            return out
        }
    }

    /// 這一題之前、問成了的那幾輪。跑題的不帶
    nonisolated static func history(before id: UUID, in entries: [ChatEntry]) -> [Prompt.Exchange] {
        let past = entries.prefix(while: { $0.id != id }).compactMap(\.exchange)
        return Array(Prompt.usable(past).suffix(remember))
    }

    func send(_ text: String) {
        guard !busy else { return }
        let entry = ChatEntry(q: text, a: "", pack: [], t: Date())
        entries.append(entry)
        run(entry.id)
    }

    func retry(_ id: UUID) {
        guard !busy, let i = index(id) else { return }
        entries[i].error = nil
        run(id)
    }

    func stop() {
        task?.cancel()
    }

    func clear() {
        task?.cancel()
        task = nil
        busy = false
        entries = []
        storage.remove(.chat)
    }

    private func index(_ id: UUID) -> Int? {
        entries.firstIndex { $0.id == id }
    }

    private func run(_ id: UUID) {
        guard let i = index(id) else { return }
        if let left = Paywall.questionsLeft, left <= 0 {
            entries[i].error = Paywall.outOfQuestions
            save()
            return
        }
        // 每一題都重讀簡介：可能剛在設定裡改過
        let profile = (storage.load(Profile.self, from: .profile) ?? Profile()).forAsk()
        let pack = Pack.build(report, profile: profile)
        entries[i].pack = pack
        save()
        let question = entries[i].q
        let history = Self.history(before: id, in: entries)
        let client = client
        busy = true
        task = Task { [weak self] in
            do {
                let reply = try await client.ask(pack: pack, profile: profile, question: question, history: history)
                guard !Task.isCancelled else { throw CancellationError() }
                self?.finish(id, reply: reply)
            } catch {
                let cancelled =
                    Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled
                self?.finish(id, error: cancelled ? Self.stopped : error.localizedDescription)
            }
        }
    }

    private func finish(_ id: UUID, reply: AskReply? = nil, error: String? = nil) {
        // 開新對話時已經清掉的那一則，回來了也不理
        guard let i = index(id) else { return }
        busy = false
        task = nil
        if let reply {
            entries[i].kind = reply.kind
            entries[i].a = reply.answer
            Paywall.noteAsked()
        } else {
            entries[i].error = error
        }
        save()
    }

    private func save() {
        storage.save(ChatLog(reportWhen: report.measurement.when, entries: entries), to: .chat)
    }
}
