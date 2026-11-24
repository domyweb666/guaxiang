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
    case section(ReportSection)
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

    func openSaved() {
        guard let saved else { return }
        report = saved
        isSample = false
        path = [.report]
    }

    func openSample() {
        guard let rules else { return }
        report = Report(measurement: Sample.measurement(rulesVersion: rules.version), rules: rules)
        isSample = true
        path = [.report]
    }

    func open(_ section: ReportSection) {
        path.append(.section(section))
    }

    func scanFinished(_ result: ScanCapture) {
        capture = result
        // 照片上找得到眉心和下巴才拉得了髮際線；找不到就直接出報告（三停寫沒判）
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
        if let newPhoto { storage.savePhoto(newPhoto) } else { storage.removePhoto() }
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
        report = nil
        saved = nil
        photo = nil
        capture = nil
        isSample = false
        path = []
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
                    if let report = model.report { ReportView(report: report) }
                case .section(let s):
                    if let report = model.report { ReportSectionView(section: s, report: report) }
                }
            }
        }
    }
}

/// 主畫面。沒掃過：示意圖＋三個承諾＋「開始掃描」。掃過：上一次報告的摘要放最上面（HANDOFF 4-5）
struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showSettings = false
    @State private var showAsk = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.group) {
                    if let saved = model.saved {
                        PageTitle(title: "瓜相", lead: "你的報告在這裡，隨時可以再看。", pushed: true)
                        savedCard(saved)
                        askRow
                    } else {
                        PageTitle(title: "瓜相", lead: "掃一次臉，看古書怎麼說你。", pushed: true)
                        hero
                        promises
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
                    Note("這是傳統文化解讀，不是科學測量，也不能替你做任何重大決定。")
                        .multilineTextAlignment(.center)
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
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showAsk) {
            if let saved = model.saved { AskView(report: saved) }
        }
    }

    /// 示意圖和一句真的古書原文（rules.json 三停那一條的第一句）
    private var hero: some View {
        Card {
            VStack(spacing: Theme.group) {
                FaceSketch().frame(maxWidth: 180)
                if let line = heroQuote {
                    Text("「\(line.text)」").font(Theme.quote).multilineTextAlignment(.center)
                    Note("\(line.book)　報告裡每一句都附這樣的出處").multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(Theme.cardPad)
            .padding(.vertical, Theme.tight)
        }
    }

    private var heroQuote: (text: String, book: String)? {
        guard let rule = model.rules?.rules.first(where: { $0.id == "santing-equal" }), let yuanwen = rule.yuanwen,
            let first = yuanwen.split(separator: "。").first
        else { return nil }
        let book = rule.source.components(separatedBy: "（").first ?? rule.source
        return (String(first) + "。", book)
    }

    private var promises: some View {
        Card {
            promise("lock", "照片不離開你的手機", divider: false)
            promise("book.closed", "每一句都附古書出處")
            promise("minus.circle", "量不到的地方，直接告訴你")
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

    private func savedCard(_ r: Report) -> some View {
        Button { model.openSaved() } label: {
            VStack(alignment: .leading, spacing: Theme.cardPad) {
                HStack(alignment: .firstTextBaseline) {
                    Note(r.measurement.when.formatted(date: .long, time: .omitted) + "掃的")
                    Spacer()
                    Text("看報告 ›").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                }
                HStack(spacing: Theme.cardPad) {
                    Text(r.wuxing?.host ?? "？")
                        .font(Theme.mark)
                        .foregroundStyle(Theme.accent)
                        .frame(width: Theme.markSize, height: Theme.markSize)
                        .background(Theme.accentSoft)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Theme.tight) {
                        Text(r.wuxing.map { "臉形推估：\($0.host)形人" } ?? "臉形這次沒判").font(.title3.weight(.semibold))
                        if let wx = r.wuxing, let type = r.rules.wuxing.types[wx.host] {
                            Text(type.plainShape).font(.subheadline).foregroundStyle(Theme.secondary)
                        }
                    }
                }
                HStack(spacing: Theme.item) {
                    stat("五官", "\(r.count(.pass)) 合格", "\(r.count(.fail)) 不合格・\(r.count(.unjudged)) 沒判")
                    stat("三停", r.santingShort, r.santingLife)
                    stat("十二宮", "判了 \(r.judgedPalaces) 宮", "\(r.palaces.count - r.judgedPalaces) 宮量不到")
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

    private func stat(_ title: String, _ value: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.tight / 2) {
            Text(title).font(.caption).foregroundStyle(Theme.secondary)
            Text(value).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            Text(sub).font(.caption).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.group)
        .padding(.vertical, Theme.item)
        .background(Theme.canvas)
        .clipShape(RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous))
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

/// 掃描前：兩項必勾（滿 18 歲而且掃自己、拿下眼鏡），兩項決定哪些部位不判。
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
                    Note("有的話打開，那個部位就不判").padding(.top, Theme.section - Theme.group).padding(.horizontal, Theme.tight)
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
