import SwiftUI

/// 問古書：先填簡介，再提問。回答只准引用這份報告，每一句都要標依據；標不出來的會加警告。
struct AskView: View {
    @Environment(\.dismiss) private var dismiss
    let report: Report

    @State private var profile = Profile()
    @State private var ageText = ""
    @State private var editing = true
    @State private var consent = UserDefaults.standard.bool(forKey: Storage.Keys.aiConsent)
    @State private var question = ""
    @State private var entries: [ChatEntry] = []
    @State private var busy = false
    @State private var alert: String?
    @State private var opened: [UUID: String] = [:]
    @FocusState private var typing: Bool

    private let storage = Storage.shared
    private var judge: Judge { Judge(rules: report.rules) }

    var body: some View {
        NavigationStack {
            Page {
                Text("先填簡介，再問問題。回答只會根據這次量到的結果和古書條文。")
                    .foregroundStyle(Theme.secondary)
                    .padding(.top, 8)
                liunianCard
                SectionTitle("簡介")
                if editing { profileForm } else { profileSummary }
                Card {
                    CardBlock(divider: false) {
                        CheckRow(
                            title: "我同意把簡介、問題和這次量測結果的文字整理，傳給 AI（Anthropic 的 Claude）產生回答",
                            detail: "照片和臉部座標不會傳出去。", isOn: $consent)
                    }
                }
                if !AskClient.isReady {
                    Card {
                        CardBlock(divider: false) {
                            Text("問古書還沒開通").font(.headline)
                            Note("回答要經過一台中繼站，那台還沒架好。架好之前這裡先不能問。")
                            #if DEVTOOLS
                                Note("開發測試：到「設定 → 開發工具」貼自己的金鑰就能先試。", warn: true)
                            #endif
                        }
                    }
                }
                SectionTitle("問題")
                examples
                ForEach(entries) { entry in answer(entry) }
                if !entries.isEmpty {
                    Button("清除問答紀錄") {
                        entries = []
                        storage.remove(.chat)
                    }
                    .buttonStyle(.ghost)
                }
            }
            .navigationTitle("問古書")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("回到報告") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) { askBar }
            .alert("提示", isPresented: Binding(get: { alert != nil }, set: { if !$0 { alert = nil } })) {
                Button("好") { alert = nil }
            } message: {
                Text(alert ?? "")
            }
        }
        .onAppear(perform: load)
        .onChange(of: consent) { _, value in UserDefaults.standard.set(value, forKey: Storage.Keys.aiConsent) }
    }

    // MARK: 流年

    @ViewBuilder private var liunianCard: some View {
        if !editing, let ln = judge.liunian(age: profile.age) {
            Card {
                CardBlock(divider: false) {
                    Note("今年的流年・虛歲 \(ln.xu) 歲")
                    Text(ln.hit?.name ?? "臉的外圈").font(.title3.bold())
                    if let row = ln.hit {
                        Text(row.place + (row.layer.isEmpty ? "" : "，屬於\(row.layer)"))
                    } else {
                        Text("76 歲以後走到臉的外圈，正面拍不到，這次不判。")
                    }
                    Note("古書說一歲對應臉上一個部位。今年就看這裡的形狀和氣色；這個工具只看得到形狀。")
                }
            }
        }
    }

    // MARK: 簡介

    private var profileForm: some View {
        Card {
            CardBlock(divider: false) {
                Note("年紀（實歲）")
                TextField("例如 34", text: $ageText)
                    .keyboardType(.numberPad)
                    .padding(10)
                    .background(Theme.fill)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.fieldRadius))
            }
            CardBlock {
                choice("性別（古書的流年分左右、婚姻那一宮用詞不同）", ["男", "女"], $profile.gender)
            }
            CardBlock { choice("感情狀態", ["單身", "交往中", "已婚", "其他"], $profile.relation) }
            CardBlock {
                choice("工作類型", ["上班族", "自己創業或接案", "學生", "家管", "退休", "其他"], $profile.work)
            }
            CardBlock {
                Note("想多說一點（選填，最多 400 字）")
                TextField("例如最近在煩惱什麼、想問哪方面", text: $profile.intro, axis: .vertical)
                    .lineLimit(3...8)
                    .padding(10)
                    .background(Theme.fill)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.fieldRadius))
                Note("這段只用來挑出跟你的問題有關的古書條文。回答不會把你自己說的事，講成是從臉上看出來的。")
            }
            CardBlock {
                Button("存好簡介", action: saveProfile).buttonStyle(.primary)
            }
        }
    }

    private func choice(_ title: String, _ options: [String], _ value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: Theme.item) {
            Note(title)
            Picker(title, selection: value) {
                Text("不想說").tag("")
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    private var profileSummary: some View {
        Card {
            CardBlock(divider: false) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(
                            ["\(profile.age ?? 0) 歲", profile.gender, profile.relation, profile.work]
                                .filter { !$0.isEmpty }.joined(separator: "・"))
                        if !profile.intro.isEmpty { Note(profile.intro) }
                    }
                    Spacer()
                    Button("修改") { editing = true }.font(.subheadline)
                }
            }
        }
    }

    private func saveProfile() {
        guard let age = Int(ageText.trimmingCharacters(in: .whitespaces)) else {
            alert = "請填年紀，流年要用。"
            return
        }
        if age < 18 {
            alert = "這個工具只給滿 18 歲的人使用。"
            return
        }
        if age > 120 {
            alert = "年紀好像打錯了。"
            return
        }
        profile.age = age
        profile.intro = Prompt.clip(profile.intro.trimmingCharacters(in: .whitespacesAndNewlines), Prompt.Limits.intro)
        storage.save(profile, to: .profile)
        editing = false
        typing = false
    }

    // MARK: 問答

    private var examples: some View {
        let host = report.wuxing?.host
        var list = ["古書怎麼看我的財運？", "感情方面古書怎麼說？", "我的五官哪裡最好？"]
        if profile.age != nil, !editing { list.insert("我今年運勢怎樣？", at: 0) }
        if let host { list.append("我是\(host)形人是什麼意思？") }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(list, id: \.self) { text in
                    Button(text) {
                        question = text
                        typing = true
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.card)
                    .foregroundStyle(Color.primary)
                    .clipShape(Capsule())
                }
            }
        }
    }

    private func answer(_ entry: ChatEntry) -> some View {
        let parsed = Citations.parse(entry.a, validIDs: Set(entry.pack.map(\.id)))
        let shown = opened[entry.id].flatMap { id in entry.pack.first { $0.id == id } }
        return VStack(alignment: .trailing, spacing: 8) {
            Text(entry.q)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.accent)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 48)
            Card {
                CardBlock(divider: false) {
                    Text(attributed(parsed))
                        .fixedSize(horizontal: false, vertical: true)
                        .environment(
                            \.openURL,
                            OpenURLAction { url in
                                let id = url.path.replacingOccurrences(of: "/", with: "")
                                opened[entry.id] = opened[entry.id] == id ? nil : id
                                return .handled
                            })
                    if parsed.used == 0 { Note("這個回答沒有標出依據，請小心看待。", warn: true) }
                    if parsed.bad { Note("回答裡有引用不存在的依據，已經拿掉。", warn: true) }
                    if let shown {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(shown.title).font(.subheadline.weight(.semibold))
                            Text(shown.text).font(.subheadline)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.fill)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.fieldRadius))
                    }
                    Note("點橘色標籤，看這句話根據哪一條。古書的說法沒有經過科學驗證。")
                }
            }
        }
    }

    private func attributed(_ parsed: ParsedAnswer) -> AttributedString {
        var out = AttributedString()
        for piece in parsed.pieces {
            switch piece {
            case .text(let text):
                out += AttributedString(text)
            case .cite(let id):
                var tag = AttributedString(" 依據\(id.dropFirst()) ")
                tag.link = URL(string: "guaxiang-cite:///\(id)")
                tag.foregroundColor = Theme.accent
                tag.font = .footnote.weight(.semibold)
                out += tag
            }
        }
        return out
    }

    private var askBar: some View {
        VStack(spacing: 8) {
            TextField("想問什麼？例如：我今年運勢怎樣？", text: $question, axis: .vertical)
                .lineLimit(1...4)
                .focused($typing)
                .padding(12)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            Button(busy ? "古書翻閱中…" : "問", action: send)
                .buttonStyle(.primary)
                .disabled(busy || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if let left = Paywall.questionsLeft { Note("還可以問 \(left) 題") }
        }
        .padding(.horizontal, Theme.screenMargin)
        .padding(.vertical, 10)
        .background(Theme.canvas)
    }

    private func send() {
        let text = Prompt.clip(question.trimmingCharacters(in: .whitespacesAndNewlines), Prompt.Limits.question)
        guard !text.isEmpty else { return }
        guard !editing, profile.age != nil else {
            alert = "先填簡介並按「存好簡介」。"
            return
        }
        guard consent else {
            alert = "要先勾選同意，才能把文字傳給 AI。"
            return
        }
        guard AskClient.isReady else {
            alert = "問古書還沒開通。"
            return
        }
        if let left = Paywall.questionsLeft, left <= 0 {
            alert = "這份報告附的題數用完了。"
            return
        }
        let pack = Pack.build(report, profile: profile)
        let history = entries.suffix(3).map { Prompt.Exchange(q: $0.q, a: $0.a) }
        busy = true
        typing = false
        Task {
            defer { busy = false }
            do {
                let reply = try await AskClient().ask(pack: pack, profile: profile, question: text, history: history)
                entries.append(ChatEntry(q: text, a: reply, pack: pack, t: Date()))
                storage.save(ChatLog(reportWhen: report.measurement.when, entries: entries), to: .chat)
                Paywall.noteAsked()
                question = ""
            } catch {
                alert = "問不到：\(error.localizedDescription)"
            }
        }
    }

    private func load() {
        if let saved = storage.load(Profile.self, from: .profile) {
            profile = saved
            ageText = saved.age.map { String($0) } ?? ""
            editing = saved.age == nil
        }
        if let log = storage.load(ChatLog.self, from: .chat), log.reportWhen == report.measurement.when {
            entries = log.entries
        }
    }
}
