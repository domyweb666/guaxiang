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

/// 整個 app 的狀態：現在在哪一步、手上的報告
@MainActor
final class AppModel: ObservableObject {
    enum Stage {
        case home, consent, scan, hairline, report
    }

    @Published var stage: Stage = .home
    @Published var report: Report?
    @Published var answers = Answers()
    @Published var hasSaved = false
    /// 這次掃描最正的那一張。只留在記憶體裡，關掉 app 就沒了
    @Published var capture: ScanCapture?

    let rules: Rules?
    let storage: Storage

    init(storage: Storage = .shared) {
        self.storage = storage
        rules = try? Rules.load()
        hasSaved = storage.load(Measurement.self, from: .measurement) != nil
    }

    func startOver() {
        capture = nil
        stage = .consent
    }

    func openSaved() {
        guard let rules, let saved = storage.load(Measurement.self, from: .measurement) else { return }
        report = Report(measurement: saved, rules: rules)
        stage = .report
    }

    func scanFinished(_ result: ScanCapture) {
        capture = result
        // 照片上找得到眉心和下巴才拉得了髮際線；找不到就直接出報告（三停寫沒判）
        if result.best.image != nil, result.best.glabella != nil, result.best.chin != nil {
            stage = .hairline
        } else {
            finish(hairRatio: nil)
        }
    }

    /// 掃完、髮際線也拉完（或跳過）：算特徵、取中位數、比對規則、存檔
    func finish(hairRatio: Double?) {
        guard let rules, let capture else {
            stage = .home
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
        show(measurement)
    }

    func show(_ measurement: Measurement, save: Bool = true) {
        guard let rules else { return }
        if save {
            storage.save(measurement, to: .measurement)
            storage.remove(.chat)
            hasSaved = true
        }
        report = Report(measurement: measurement, rules: rules)
        stage = .report
    }

    func eraseAll() {
        storage.eraseAll()
        report = nil
        capture = nil
        hasSaved = false
        stage = .home
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.rules == nil {
                Page {
                    PageTitle(title: "瓜相", lead: "規則庫讀不到，請重新安裝 app。")
                }
            } else {
                switch model.stage {
                case .home: HomeView()
                case .consent: ConsentView()
                case .scan: ScanView()
                case .hairline: HairlineView()
                case .report:
                    if let report = model.report {
                        ReportView(report: report)
                    } else {
                        HomeView()
                    }
                }
            }
        }
        .animation(.default, value: model.stage)
    }
}

/// 主畫面：只放「開始掃描」，上一次的報告放在次要位置（HANDOFF 4-5）
struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showSettings = false

    var body: some View {
        Page {
            HStack(alignment: .top) {
                PageTitle(title: "瓜相", lead: "掃一次臉，看懂古書怎麼說你。")
                Spacer()
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape").font(.title3).frame(width: 44, height: 44)
                }
                .padding(.top, 28)
                .accessibilityLabel("設定")
            }
            Card {
                CardBlock(divider: false) { Label("照片不離開你的手機", systemImage: "checkmark") }
                CardBlock { Label("每一句都附古籍出處", systemImage: "checkmark") }
                CardBlock { Label("看不到的地方，直接告訴你", systemImage: "checkmark") }
            }
            Note("這是傳統文化解讀，不是科學測量，也不能替你做任何重大決定。")
            Button("開始掃描") { model.startOver() }
                .buttonStyle(.primary)
            if model.hasSaved {
                Button("看上一次的結果") { model.openSaved() }
                    .buttonStyle(.ghost)
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }
}

/// 掃描前：兩項必勾（滿 18 歲而且掃自己、拿下眼鏡），兩題決定哪些項目不判
struct ConsentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var adult = false
    @State private var noGlasses = false

    var body: some View {
        Page {
            PageTitle(title: "掃描前", lead: "前兩項要打勾才能開始，後兩題決定哪些項目不看。")
            Card {
                CardBlock(divider: false) {
                    CheckRow(title: "我已滿 18 歲，而且要掃的是我自己的臉", isOn: $adult)
                }
                CardBlock {
                    CheckRow(
                        title: "我已經拿下眼鏡",
                        detail: "眼鏡框會擋住眉尾和眼角，鏡片會讓眼睛看起來變大或變小，量出來會不準。隱形眼鏡可以戴。",
                        isOn: $noGlasses)
                }
            }
            Card {
                CardBlock(divider: false) {
                    CheckRow(title: "我有紋眉、霧眉，或眉毛修過很多", isOn: $model.answers.browTattoo)
                }
                CardBlock {
                    CheckRow(title: "我的鼻子動過手術或打過填充", isOn: $model.answers.noseSurgery)
                }
            }
            Card {
                CardBlock(divider: false) { Note("建議：白天、面向窗戶，不要背光。不用笑，自然放鬆。") }
            }
            Button("打開相機") {
                model.answers.noGlasses = noGlasses
                model.stage = .scan
            }
            .buttonStyle(.primary)
            .disabled(!(adult && noGlasses))
            Note("按下後手機會詢問相機權限。畫面只在手機上處理。")
            Button("回上一頁") { model.stage = .home }
                .buttonStyle(.ghost)
        }
    }
}
