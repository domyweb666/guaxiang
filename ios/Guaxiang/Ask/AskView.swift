import SwiftUI
import UIKit

/// 問古書：單純的對話。回答只准引用這份報告，每一句都有依據；跑題和健康的問題顯示寫死的句子。
/// 兩種用法：報告視窗裡（embedded，導覽列是視窗的）、首頁的 sheet
struct AskView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let report: Report
    private let embedded: Bool
    /// 報告視窗裡現在是不是停在這一格。別的格子疊在上面時，導覽列的按鈕要收起來
    private let active: Bool

    @StateObject private var chat: AskChat
    @AppStorage(Storage.Keys.aiConsent) private var consent = false
    @State private var profile = Profile()
    @State private var question = ""
    @State private var sheet: AskSheet?
    /// 等使用者同意之後才要送的那一題
    @State private var pending: Pending?
    @State private var confirmClear = false
    @State private var atBottom = true
    /// 鍵盤出來之前是不是在看最新的一則
    @State private var pinned = true
    @FocusState private var typing: Bool
    /// 開通了沒。要讀鑰匙圈，打開這一頁時讀一次，不要每次重畫都讀
    @State private var ready = true

    private enum Pending {
        case ask(String)
        case retry(UUID)
    }

    private static let space = "ask.scroll"
    private static let content = "ask.content"

    init(report: Report, embedded: Bool = false, active: Bool = true) {
        self.report = report
        self.embedded = embedded
        self.active = active
        _chat = StateObject(wrappedValue: AskChat(report: report))
    }

    var body: some View {
        if embedded {
            page
        } else {
            NavigationStack {
                page
                    .navigationTitle("問古書")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) { Button("關閉") { dismiss() } }
                    }
            }
        }
    }

    private var page: some View {
        conversation
            .background(Theme.canvas.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) { inputBar }
            .toolbar {
                if active, !chat.entries.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            confirmClear = true
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .accessibilityLabel("開新對話")
                    }
                }
            }
            .alert("要開新對話嗎？", isPresented: $confirmClear) {
                Button("清掉，開新的", role: .destructive) { chat.clear() }
                Button("先不用", role: .cancel) {}
            } message: {
                Text("這一串問答會清掉，救不回來。")
            }
            // 掛在自己身上：在報告視窗裡，掛到外層會被視窗擋住、跳不出來
            .sheet(item: $sheet, onDismiss: sheetClosed) { which in
                switch which {
                case .consent:
                    AskConsentSheet {
                        consent = true
                        sheet = nil
                    }
                case .evidence(let evidence):
                    EvidenceSheet(evidence: evidence)
                case .profile:
                    NavigationStack {
                        ProfileView()
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button("完成") { sheet = nil }.fontWeight(.semibold)
                                }
                            }
                    }
                }
            }
            .onAppear(perform: reloadProfile)
    }

    // MARK: 對話

    private var conversation: some View {
        GeometryReader { outer in
            ScrollViewReader { proxy in
                ScrollView {
                    Group {
                        if chat.entries.isEmpty {
                            greeting.frame(maxWidth: .infinity, minHeight: outer.size.height)
                        } else {
                            VStack(alignment: .leading, spacing: Theme.section) {
                                ForEach(chat.entries) { row($0) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, Theme.group)
                        }
                    }
                    .padding(.horizontal, Theme.screenMargin)
                    .background(
                        GeometryReader { inner in
                            let bottom = inner.frame(in: .named(Self.space)).maxY
                            Color.clear.onChange(of: bottom <= outer.size.height + Theme.chatSlack, initial: true) {
                                _, near in atBottom = near
                            }
                        }
                    )
                    .id(Self.content)
                }
                .coordinateSpace(.named(Self.space))
                .scrollDismissesKeyboard(.interactively)
                .onAppear { toBottom(proxy, animated: false) }
                // 自己剛送出：一定捲到最新
                .onChange(of: chat.entries.count) { toBottom(proxy) }
                // 回答來了：還在看最新的才跟著捲，往上翻舊的不拉回來
                .onChange(of: chat.busy) { _, busy in
                    guard !busy else { return }
                    if atBottom { toBottom(proxy) }
                    if active, chat.entries.last?.reply != nil {
                        AccessibilityNotification.Announcement("回答好了").post()
                    }
                }
                .onChange(of: typing) { _, on in
                    if on { pinned = atBottom }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                    if typing, pinned { toBottom(proxy) }
                }
            }
        }
    }

    private func toBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        guard !chat.entries.isEmpty else { return }
        // 等新的一則排好版再捲
        DispatchQueue.main.async {
            withAnimation(animated && !reduceMotion ? Theme.change : nil) {
                proxy.scrollTo(Self.content, anchor: .bottom)
            }
        }
    }

    private var greeting: some View {
        VStack(spacing: Theme.section) {
            VStack(spacing: Theme.item) {
                Text("想問哪裡？").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Text("古書怎麼說你的臉，直接打就好。")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
            }
            .multilineTextAlignment(.center)
            if !ready { notReady }
            suggestions(4)
        }
        .padding(.vertical, Theme.group)
    }

    private var notReady: some View {
        VStack(spacing: Theme.tight) {
            Note("問古書還沒開通，現在還不能問。", warn: true)
            #if DEVTOOLS
                Note("開發測試：到設定 → 開發工具，連電腦的 Claude CLI 或貼金鑰。")
            #endif
        }
        .multilineTextAlignment(.center)
    }

    /// 建議問題：固定清單，點了直接送出
    private func suggestions(_ count: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.item) {
            ForEach(AskSuggestions.list(report: report, profile: profile).prefix(count), id: \.self) { text in
                SuggestionButton(text: text, disabled: chat.busy) { submit(text) }
            }
        }
    }

    /// 每一則抽成自己的畫面、內容沒變就不重算：拖視窗、鍵盤升降、打字時，舊的回答不再重新解析
    private func row(_ entry: ChatEntry) -> some View {
        let last = entry.id == chat.entries.last?.id
        let extra = last && entry.kind == .offtopic
            ? Array(AskSuggestions.list(report: report, profile: profile).prefix(3)) : []
        return ChatRow(
            entry: entry,
            busy: chat.busy,
            hasAge: profile.currentAge() != nil,
            extra: extra,
            showEvidence: { found in
                typing = false
                sheet = .evidence(found)
            },
            fillBirthday: {
                typing = false
                sheet = .profile
            },
            retry: { retry(entry.id) },
            ask: { submit($0) }
        )
        .equatable()
    }

    // MARK: 輸入列

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: Theme.tight) {
            HStack(alignment: .bottom, spacing: Theme.item) {
                // 位置窄，提示字要短：最大字級配最窄的手機也放得下
                TextField("想問什麼", text: $question, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($typing)
                    .padding(.horizontal, Theme.cardPad)
                    .padding(.vertical, Theme.rowPadV)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous))
                    .onChange(of: question) { _, text in
                        let clipped = Prompt.clip(text, Prompt.Limits.question)
                        if clipped != text { question = clipped }
                    }
                Button {
                    if chat.busy { chat.stop() } else { submit(question) }
                } label: {
                    Image(systemName: chat.busy ? "stop.fill" : "arrow.up")
                        .font(.system(size: Theme.touchIcon, weight: .semibold))
                        .foregroundStyle(canPress ? Theme.onAccent : Theme.secondary)
                        .frame(width: Theme.touch, height: Theme.touch)
                        .background(canPress ? Theme.accent : Theme.separator)
                        .clipShape(Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(PressStyle())
                .disabled(!canPress)
                .accessibilityLabel(chat.busy ? "停止" : "送出")
            }
            if (question as NSString).length >= Prompt.Limits.question { Note("最多 300 字。") }
            if let left = Paywall.questionsLeft { Note("還可以問 \(left) 題") }
            if !typing { Note("古書的說法沒有經過科學驗證。").frame(maxWidth: .infinity) }
        }
        .padding(.horizontal, Theme.screenMargin)
        .padding(.vertical, Theme.item)
        .background(Theme.canvas)
    }

    private var canPress: Bool {
        chat.busy || !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: 送出

    private func submit(_ raw: String) {
        let text = Prompt.clip(raw.trimmingCharacters(in: .whitespacesAndNewlines), Prompt.Limits.question)
        guard !text.isEmpty, !chat.busy else { return }
        question = ""
        typing = false
        start(.ask(text))
    }

    private func retry(_ id: UUID) {
        guard !chat.busy else { return }
        start(.retry(id))
    }

    /// 第一次要先同意。還沒開通的直接送，會在原地寫原因，不用先問同意
    private func start(_ next: Pending) {
        if AskClient.isReady, !consent {
            pending = next
            sheet = .consent
            return
        }
        switch next {
        case .ask(let text): chat.send(text)
        case .retry(let id): chat.retry(id)
        }
    }

    private func sheetClosed() {
        reloadProfile()
        guard let next = pending else { return }
        pending = nil
        if consent {
            start(next)
        } else if case .ask(let text) = next {
            // 沒同意：題目放回輸入框，不會不見
            question = text
        }
    }

    private func reloadProfile() {
        profile = Storage.shared.load(Profile.self, from: .profile) ?? Profile()
        ready = AskClient.isReady
    }
}

/// 問古書會跳出來的頁
enum AskSheet: Identifiable {
    case consent
    case evidence(Evidence)
    case profile

    var id: String {
        switch self {
        case .consent: return "consent"
        case .evidence(let e): return "evidence-" + e.id
        case .profile: return "profile"
        }
    }
}

/// 一則問答。只比資料不比閉包：資料沒變，SwiftUI 就跳過這一則的 body
private struct ChatRow: View, Equatable {
    let entry: ChatEntry
    let busy: Bool
    let hasAge: Bool
    /// 跑題時最後一則下面放的建議問題
    let extra: [String]
    let showEvidence: (Evidence) -> Void
    let fillBirthday: () -> Void
    let retry: () -> Void
    let ask: (String) -> Void

    static func == (a: ChatRow, b: ChatRow) -> Bool {
        a.entry == b.entry && a.busy == b.busy && a.hasAge == b.hasAge && a.extra == b.extra
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.group) {
            HStack(spacing: 0) {
                Spacer(minLength: Theme.bubbleInset)
                Text(entry.q)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.cardPad)
                    .padding(.vertical, Theme.rowPadV)
                    .background(Theme.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous))
                    .contentShape(
                        .contextMenuPreview, RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous)
                    )
                    .contextMenu { Self.copyButton(entry.q) }
                    .accessibilityLabel("你問：\(entry.q)")
            }
            if let reply = entry.reply {
                answer(reply)
            } else if let error = entry.error {
                failed(error)
            } else {
                Flipping()
            }
        }
    }

    private func answer(_ reply: AskReply) -> some View {
        let ids = Set(entry.pack.map(\.id))
        let pieces = reply.pieces(validIDs: ids)
        let plain = pieces.reduce(into: "") { out, piece in
            if case .text(let text) = piece { out += text }
        }
        return VStack(alignment: .leading, spacing: Theme.group) {
            Text(Self.attributed(AskReply.collapsed(pieces)))
                .lineSpacing(Theme.tight)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contextMenu { Self.copyButton(plain) }
                .environment(
                    \.openURL,
                    OpenURLAction { url in
                        if let found = entry.pack.first(where: { $0.id == url.lastPathComponent }) {
                            showEvidence(found)
                        }
                        return .handled
                    })
            if needsBirthday(reply) {
                Button("去填生日", action: fillBirthday).buttonStyle(.ghost)
                Note("流年要知道幾歲才對得上。生日只留在手機，傳出去的只有年紀。")
            }
            if !extra.isEmpty {
                VStack(alignment: .leading, spacing: Theme.item) {
                    ForEach(extra, id: \.self) { text in
                        SuggestionButton(text: text, disabled: busy) { ask(text) }
                    }
                }
            }
        }
    }

    /// 問到今年怎樣，又沒填生日
    private func needsBirthday(_ reply: AskReply) -> Bool {
        guard reply.kind == .answer || reply.kind == .nodata else { return false }
        return !hasAge && LiunianQuestion.matches(entry.q)
    }

    private func failed(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.tight) {
            Note(error, warn: true)
            Button(action: retry) {
                Label("重試", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(busy ? Theme.secondary : Theme.accent)
                    .frame(minHeight: Theme.touch)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .disabled(busy)
        }
    }

    static func copyButton(_ text: String) -> some View {
        Button {
            UIPasteboard.general.string = text
        } label: {
            Label("複製", systemImage: "doc.on.doc")
        }
    }

    static func attributed(_ pieces: [AnswerPiece]) -> AttributedString {
        var out = AttributedString()
        for piece in pieces {
            switch piece {
            case .text(let text):
                out += AttributedString(text)
            case .cite(let id):
                // 不斷行空格和字元連接符（U+2060），標籤不會被拆成兩行
                var tag = AttributedString("\u{00A0}依\u{2060}據\u{00A0}\(id.dropFirst())\u{00A0}")
                tag.link = URL(string: "guaxiang-cite:///\(id)")
                tag.foregroundColor = Theme.accent
                tag.font = .caption
                out += tag
            }
        }
        return out
    }
}

/// 建議問題的一顆鈕：開場和跑題時共用
private struct SuggestionButton: View {
    let text: String
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.primary)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, Theme.cardPad)
                .frame(minHeight: Theme.touch)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .disabled(disabled)
    }
}

/// 等回答的時候
private struct Flipping: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Theme.item) {
            Image(systemName: "book")
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
                .accessibilityHidden(true)
            Text("翻書中")
        }
        .font(.subheadline)
        .foregroundStyle(Theme.secondary)
    }
}

/// 第一次送出時問一次。設定的「你的資料去了哪裡」可以撤回
private struct AskConsentSheet: View {
    @Environment(\.dismiss) private var dismiss
    let agree: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.group) {
                    PageTitle(title: "要傳文字給 AI", lead: "回答由 Anthropic 的 Claude 產生，問之前要你同意。")
                    Card {
                        CardBlock(divider: false) {
                            Text("會傳").font(.headline)
                            Text("你問的問題、前幾題的問答、你填的簡介（生日只換算成年紀）、這次量測結果的文字整理。")
                        }
                        CardBlock {
                            Text("不會傳").font(.headline)
                            Text("照片、相機畫面、臉部座標。")
                        }
                    }
                    Note("同意一次就好。之後可以到設定的「你的資料去了哪裡」撤回。").padding(.horizontal, Theme.tight)
                }
                .padding(.horizontal, Theme.screenMargin)
                .padding(.bottom, Theme.section)
            }
            BottomBar {
                Button("同意，送出這一題", action: agree).buttonStyle(.primary)
                Button("先不要") { dismiss() }.buttonStyle(.textOnly)
            }
        }
        .background(Theme.canvas.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

/// 點了「依據 3」看那一條
private struct EvidenceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let evidence: Evidence

    var body: some View {
        NavigationStack {
            Page {
                Text(evidence.title)
                    .font(.headline)
                    .padding(.top, Theme.item)
                ForEach(Array(evidence.readable.plain.enumerated()), id: \.offset) { _, line in
                    Text(line).lineSpacing(Theme.tight).textSelection(.enabled)
                }
                if !evidence.readable.original.isEmpty {
                    SectionTitle("古書原文")
                    ForEach(Array(evidence.readable.original.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(line.hasPrefix("古書：") ? Theme.quote : .footnote)
                            .foregroundStyle(line.hasPrefix("古書：") ? Color.primary : Theme.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("依據 \(String(evidence.id.dropFirst()))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("關閉") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
