import SwiftUI
import VeggieKit

@main
struct GuaxiangApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .tint(Theme.accent)
                .onAppear { Appearance.stored.apply() }
        }
    }
}

/// 推入的每一頁。用系統的推入和返回，左緣滑回能用（附錄 E 第 2 項）
enum Route: Hashable {
    case consent, scan, hairline, report
}

/// 整個 app 的狀態：現在推到哪幾頁、手上的報告
@MainActor
final class AppModel: ObservableObject {
    @Published var path: [Route] = []
    /// 現在打開的報告（自己的或範例）
    @Published var report: Report?
    /// 現在打開的是範例報告：不存檔、不能問古書
    @Published var isSample = false
    /// 手機裡存的上一次報告，首頁拿來顯示摘要
    @Published var saved: Report?
    @Published var answers = Answers()
    /// 上一次報告的照片和標註。只存在這支手機
    @Published var photo: FacePhoto?
    /// 這次掃描收到的東西。只留在記憶體裡，關掉 app 就沒了
    @Published var capture: ScanCapture?
    /// 從首頁「今日一句」點進報告：打開後跳到「面相」的這一區，用完就清掉
    var openAt: ReportSection?

    let rules: Rules?
    let storage: Storage

    var hasSaved: Bool { saved != nil }

    init(storage: Storage = .shared) {
        self.storage = storage
        rules = try? Rules.load()
        if let rules, let m = storage.load(Measurement.self, from: .measurement) {
            saved = Report(measurement: m, rules: rules)
            photo = storage.loadPhoto(when: m.when)
        }
    }

    /// 從首頁或報告按「開始掃描」「再掃一次」：回到最上層，推入掃描前
    func startOver() {
        capture = nil
        answers = Answers()
        path = [.consent]
    }

    func openCamera() {
        path.append(.scan)
    }

    func cancelScan() {
        if path.last == .scan { path.removeLast() }
    }

    func openSaved(at section: ReportSection? = nil) {
        guard let saved else { return }
        openAt = section
        report = saved
        isSample = false
        path = [.report]
    }

    func openSample() {
        guard let rules else { return }
        openAt = nil
        report = Report(measurement: Sample.measurement(rulesVersion: rules.version), rules: rules)
        isSample = true
        path = [.report]
    }

    /// 從報告回上一頁（旁白的返回手勢用）
    func closeReport() {
        if path.last == .report { path.removeLast() }
    }

    func scanFinished(_ result: ScanCapture) {
        capture = result
        // 照片上找得到眉心和下巴才拉得了髮際線；找不到就直接出報告（三段寫沒看）
        if result.best.image != nil, result.best.glabella != nil, result.best.chin != nil {
            path.append(.hairline)
        } else {
            finish(hairRatio: nil)
        }
    }

    /// 掃完、髮際線也拉完（或跳過）：算特徵、取中位數、比對規則、存檔
    func finish(hairRatio: Double?, hairY: Double? = nil) {
        guard let rules, let capture else {
            path = []
            return
        }
        // 公尺制：眼高的下限給 0.1 公釐
        let perFrame = capture.frames.map { FeatureEngine.features($0, hairRatio: hairRatio, eps: 0.0001) }
        let F = Stats.summarize(perFrame, rules: rules)
        let measurement = Measurement(
            when: Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)),
            frames: capture.frames.count, light: Stats.median(capture.lights),
            hasHair: hairRatio != nil && F["santing_U"] != nil, answers: answers, F: F,
            rulesVersion: rules.version, gaps: capture.gaps)
        show(measurement, photo: makePhoto(capture.best, measurement, hairY: hairY))
    }

    private func makePhoto(_ best: BestShot, _ measurement: Measurement, hairY: Double?) -> FacePhoto? {
        guard let image = best.image else { return nil }
        var marks = best.marks
        marks.when = measurement.when
        marks.hairY = measurement.hasHair ? hairY : nil
        return FacePhoto(image: image, marks: marks)
    }

    func show(_ measurement: Measurement, photo newPhoto: FacePhoto?) {
        guard let rules else { return }
        storage.save(measurement, to: .measurement)
        if let newPhoto {
            storage.savePhotoLater(newPhoto)
        } else {
            storage.finishPhotoWrites()
            storage.removePhoto()
        }
        photo = newPhoto
        storage.remove(.chat)
        let r = Report(measurement: measurement, rules: rules)
        saved = r
        report = r
        isSample = false
        // 掃描那幾頁拿掉，返回直接回首頁
        path = [.report]
    }

    func eraseAll() {
        storage.eraseAll()
        saved = nil
        photo = nil
        capture = nil
        isSample = false
        guard path.contains(.report) else {
            report = nil
            path = []
            return
        }
        // 報告裡的設定頁也會清：先離開報告，那一頁滑出去的時候不能突然變空的
        path = []
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            if self?.path.isEmpty == true { self?.report = nil }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack(path: $model.path) {
            Group {
                if model.rules == nil {
                    Page {
                        PageTitle(title: "瓜相", lead: "規則庫讀不到，請重新安裝 app。")
                    }
                } else {
                    HomeView()
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .consent: ConsentView()
                case .scan: ScanView()
                case .hairline: HairlineView()
                case .report:
                    if let report = model.report { ReportView(report: report, openAt: model.openAt) }
                }
            }
        }
    }
}

/// 主畫面。沒掃過：示意圖＋三個承諾＋「開始掃描」。掃過：上一次報告的摘要放最上面（HANDOFF 4-5）
struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showAsk = false
    @State private var daily: DailyLine?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.group) {
                    if let saved = model.saved {
                        PageTitle(title: "瓜相", lead: "你的報告在這裡，隨時可以再看。", pushed: true)
                        if let daily { dailyCard(daily) }
                        savedCard(saved)
                        askRow
                    } else {
                        PageTitle(title: "瓜相", lead: "掃一次臉，看古書怎麼說你。", pushed: true)
                        hero
                        promises
                        // 輔助字級時按鈕區太高，把卡片擠到剩一小截：這句改放進捲動區（模擬器 2026-11-26 最大字級）
                        if typeSize.isAccessibilitySize { disclaimer }
                    }
                }
                .padding(.horizontal, Theme.screenMargin)
                .padding(.bottom, Theme.section)
            }
            BottomBar {
                if model.hasSaved {
                    Button("再掃一次") { model.startOver() }.buttonStyle(.ghost)
                    Note("再掃會換成新的報告，舊的問答會清掉。")
                } else {
                    Button("開始掃描") { model.startOver() }.buttonStyle(.primary)
                    Button("先看一份範例報告") { model.openSample() }.buttonStyle(.textOnly)
                    if !typeSize.isAccessibilitySize { disclaimer.multilineTextAlignment(.center) }
                }
            }
        }
        .background(Theme.canvas.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("設定")
            }
        }
        .onAppear(perform: refreshDaily)
        // 過了半夜回到 app、改了生日（從設定回來）、再掃一次，都重挑
        .onChange(of: scenePhase) { _, phase in if phase == .active { refreshDaily() } }
        .onChange(of: showSettings) { _, open in if !open { refreshDaily() } }
        .onChange(of: model.saved?.measurement.when) { _, _ in refreshDaily() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showAsk) {
            if let saved = model.saved { AskView(report: saved) }
        }
    }

    private var disclaimer: some View {
        Note("這是傳統文化解讀，古書的說法沒有人驗證過，不能替你做任何重大決定。")
    }

    /// 示意圖和一句古書的白話（rules.json 三段那一條），原文在旁邊的小圓鈕裡
    private var hero: some View {
        Card {
            VStack(spacing: Theme.group) {
                FaceSketch().frame(maxWidth: Theme.sketchWidth)
                if let rule = model.rules?.rules.first(where: { $0.id == "santing-equal" }) {
                    HStack(spacing: Theme.item) {
                        Text(rule.baihua).fixedSize(horizontal: false, vertical: true)
                        InfoButton(subject: "臉的三段") { BookNote.rule(rule) }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(Theme.cardPad)
            .padding(.vertical, Theme.tight)
        }
    }

    private var promises: some View {
        Card {
            promise("lock", "照片不離開你的手機", divider: false)
            promise("book.closed", "每一句都附古書出處")
            promise("minus.circle", "看不到的地方，直接告訴你")
        }
    }

    private func promise(_ icon: String, _ text: String, divider: Bool = true) -> some View {
        VStack(spacing: 0) {
            if divider { RowDivider() }
            HStack(spacing: Theme.group) {
                Image(systemName: icon).foregroundStyle(Theme.accent).frame(width: Theme.touch / 2)
                Text(text)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.cardPad)
            .frame(minHeight: Theme.rowHeight)
        }
    }

    private func refreshDaily() {
        guard let saved = model.saved else {
            daily = nil
            return
        }
        let age = model.storage.load(Profile.self, from: .profile)?.currentAge()
        daily = Daily.today(saved, age: age)
    }

    /// 今日一句（多米 11/27 選 A：首頁最上面一張卡）。點了跳到報告那一區；流年沒有對應的區，打開問古書
    private func dailyCard(_ d: DailyLine) -> some View {
        Button {
            if let section = d.section {
                model.openSaved(at: section)
            } else {
                showAsk = true
            }
        } label: {
            VStack(alignment: .leading, spacing: Theme.item) {
                Text("今日一句・\(d.topic)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                Text(d.good)
                    .font(Theme.quoteLarge) // 宋體沒有粗體，加 weight 會退回別的字
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(d.line)
                    .font(.subheadline)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let quote = d.quote, !quote.isEmpty {
                    Text("「\(quote)」")
                        .font(Theme.quote)
                        .foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(Color.primary)
            .padding(Theme.cardPad)
            .padding(.vertical, Theme.tight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .accessibilityHint(d.section == nil ? "打開問古書" : "打開報告的\(d.section!.title)")
    }

    private func savedCard(_ r: Report) -> some View {
        Button { model.openSaved() } label: {
            VStack(alignment: .leading, spacing: Theme.cardPad) {
                HStack(alignment: .firstTextBaseline) {
                    Note(r.measurement.when.formatted(date: .long, time: .omitted) + "掃的")
                    Spacer()
                    Text("看報告 ›").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                }
                ShapeHead(report: r)
                ForEach(r.highlights.prefix(3)) { h in
                    VStack(alignment: .leading, spacing: Theme.tight / 2) {
                        Text(h.topic).font(.footnote).foregroundStyle(Theme.secondary)
                        Text(h.good).font(.body.weight(.semibold)).multilineTextAlignment(.leading)
                    }
                }
            }
            .foregroundStyle(Color.primary)
            .padding(Theme.cardPad)
            .padding(.vertical, Theme.tight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
        .buttonStyle(PressStyle())
    }

    private var askRow: some View {
        Button { showAsk = true } label: {
            HStack(spacing: Theme.group) {
                Image(systemName: "bubble.left").foregroundStyle(Theme.accent)
                Text("問古書").foregroundStyle(Color.primary)
                Spacer()
                Text(Paywall.questionsLeft.map { "還能問 \($0) 題" } ?? "")
                    .font(.subheadline).foregroundStyle(Theme.secondary)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.tertiary)
            }
            .padding(.horizontal, Theme.cardPad)
            .frame(minHeight: Theme.rowHeight)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
        .buttonStyle(PressStyle())
    }
}

/// 掃描前：兩項必勾（滿 18 歲而且掃自己、拿下眼鏡），兩項決定哪些部位不看。
/// 按鈕寫「繼續」，接著才跳系統的相機詢問（準則 3-31、12-19）
struct ConsentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var adult = false
    @State private var noGlasses = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.group) {
                    PageTitle(title: "掃描前", lead: "上面兩項打勾才能開始。下面兩項決定哪些部位不看。", pushed: true)
                    Card {
                        CardBlock(divider: false) {
                            CheckRow(title: "我已滿 18 歲，要掃的是我自己的臉", isOn: $adult)
                        }
                        CardBlock {
                            CheckRow(
                                title: "我已經拿下眼鏡",
                                detail: "鏡框會擋住眉尾和眼角，鏡片會讓眼睛看起來變大變小。隱形眼鏡可以戴。",
                                isOn: $noGlasses)
                        }
                    }
                    Note("有的話打開，那個部位就不看").padding(.top, Theme.section - Theme.group).padding(.horizontal, Theme.tight)
                    Card {
                        Toggle("紋眉、霧眉，或眉毛修過很多", isOn: $model.answers.browTattoo)
                            .padding(.horizontal, Theme.cardPad)
                            .frame(minHeight: Theme.rowHeight)
                        RowDivider()
                        Toggle("鼻子動過手術或打過填充", isOn: $model.answers.noseSurgery)
                            .padding(.horizontal, Theme.cardPad)
                            .frame(minHeight: Theme.rowHeight)
                    }
                    .tint(Theme.accent)
                    Note("白天面向窗戶最好，不要背光。不用笑，自然放鬆。").padding(.horizontal, Theme.tight)
                }
                .padding(.horizontal, Theme.screenMargin)
                .padding(.bottom, Theme.section)
            }
            BottomBar {
                Button("繼續") {
                    model.answers.noGlasses = noGlasses
                    model.openCamera()
                }
                .buttonStyle(.primary)
                .disabled(!(adult && noGlasses))
                Note("接著手機會問你能不能用相機。畫面只在手機上處理。").multilineTextAlignment(.center)
            }
        }
        .background(Theme.canvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
}
