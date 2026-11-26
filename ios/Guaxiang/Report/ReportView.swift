import SwiftUI

/// 報告的每一區。運勢、五官、三段在「面相」那一頁，其他從總覽往右推入
enum ReportSection: String, Hashable, CaseIterable {
    case wuxing, officials, santing, palaces, others, cannotSee, diagram

    /// 「面相」那一頁由上到下
    static let onFacePage: [ReportSection] = [.palaces, .officials, .santing]

    var title: String {
        switch self {
        case .wuxing: return "臉形"
        case .officials: return "五官"
        case .santing: return "三段"
        case .palaces: return "運勢"
        case .others: return "其他古書說法"
        case .cannotSee: return "這次沒看的"
        case .diagram: return "標註圖"
        }
    }

    /// 沒買完整版也看得到的區。暫定「臉形和五官免費」（HANDOFF 8-1 的最低限），多米還沒定案（.vibe/代決清單.md）
    var isFree: Bool {
        switch self {
        case .santing, .palaces, .others: return false
        default: return true
        }
    }

    var locked: Bool { !isFree && !Paywall.canSeeFullReport }

    /// 照片上要亮哪一區。鎖住的區不亮
    var mode: AnnotatedPhoto.Mode {
        guard !locked else { return .overview }
        switch self {
        case .officials: return .officials
        case .santing: return .santing
        case .palaces: return .palaces
        default: return .overview
        }
    }
}

/// 報告：上半部照片滿版、不捲動，下半部是一直在的懸浮視窗（QC-0006 第 3 筆，多米 2026-11-24 選 A）。
struct ReportView: View {
    @EnvironmentObject private var model: AppModel
    let report: Report
    @State private var tab = ReportTab.overview
    /// 「面相」那一頁捲到哪一區
    @State private var section = ReportSection.palaces
    @State private var detent = Theme.windowHalf
    /// 這一頁在不在畫面上（推入完成到開始返回之間）
    @State private var pageOn = false
    @State private var windowUp = false
    /// 視窗裡有推入的頁
    @State private var pushed = false

    var body: some View {
        GeometryReader { geo in
            let stage = Stage(size: geo.size, top: geo.safeAreaInsets.top, bottom: geo.safeAreaInsets.bottom)
            ZStack(alignment: .top) {
                Theme.canvas
                top(stage)
                    .frame(width: stage.fill.size.width, height: stage.fill.size.height)
            }
            .ignoresSafeArea()
        }
        // 鍵盤是視窗裡的事，照片不跟著縮
        .ignoresSafeArea(.keyboard)
        .background(
            PageLifecycle(
                // 視窗左邊露出的那一條滑下去是外層的返回。視窗裡還有上一頁可以回時先停掉，不然整份報告會被關掉
                blocksBack: pushed && windowUp,
                onShow: {
                    pageOn = true
                    windowUp = true
                },
                onLeave: {
                    pageOn = false
                    windowUp = false
                    pushed = false
                }
            )
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: $windowUp, onDismiss: reopen) {
            ReportWindow(report: report, tab: $tab, section: $section, detent: $detent, pushed: $pushed)
                .presentationDetents([Theme.windowHalf, .large], selection: $detent)
                .presentationBackgroundInteraction(.enabled(upThrough: Theme.windowHalf))
                // 捲內容就是捲內容，要拉高拉低拖上面的橫條和標題列
                .presentationContentInteraction(.scrolls)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(Theme.windowRadius)
                .presentationBackground { WindowBackground() }
                .interactiveDismissDisabled()
        }
    }

    /// 還在這一頁，視窗卻被系統收掉：再升起來，不然這一頁就沒東西可看
    private func reopen() {
        // 重升的視窗從頭來，裡面沒有推入的頁
        pushed = false
        if pageOn { windowUp = true }
    }

    /// 上半部：這次掃的照片。範例放示意圖，舊報告沒有照片就說明
    @ViewBuilder private func top(_ stage: Stage) -> some View {
        if model.isSample {
            VStack(spacing: Theme.item) {
                FaceSketch().frame(maxWidth: Theme.sketchWidth)
                Note("範例沒有照片，這張是示意圖。")
            }
            .modifier(Clear(stage: stage))
        } else if let photo = model.photo {
            AnnotatedPhoto(
                photo: photo, mode: tab == .face ? section.mode : .overview, palaces: report.fortunes, fill: stage.fill
            )
                .overlay(alignment: .top) {
                    LinearGradient(
                        colors: [Theme.canvas.opacity(Theme.scrimOpacity), Theme.canvas.opacity(0)], startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: stage.fill.top)
                    .allowsHitTesting(false)
                }
        } else {
            Note("這份報告是之前的版本掃的，沒有留照片。再掃一次，照片和標註會放在這裡。")
                .multilineTextAlignment(.center)
                .modifier(Clear(stage: stage))
        }
    }

    /// 放在返回列以下、視窗以上的那一段中間
    private struct Clear: ViewModifier {
        let stage: Stage

        func body(content: Content) -> some View {
            content
                .padding(.horizontal, Theme.screenMargin)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, stage.fill.top)
                .padding(.bottom, stage.fill.bottom)
        }
    }

    /// 照片鋪滿整個螢幕，臉放在視窗上面那一段。視窗半高是「螢幕扣掉狀態列和底部之後的一半，再加底部」，照這個估視窗的上緣
    private struct Stage {
        let fill: AnnotatedPhoto.Fill

        init(size: CGSize, top: CGFloat, bottom: CGFloat) {
            let full = size.height + top + bottom
            let statusBar = max(0, top - Theme.touch)
            let windowTop = full - (max(0, full - statusBar - bottom) * Theme.windowFraction + bottom)
            fill = AnnotatedPhoto.Fill(
                size: CGSize(width: size.width, height: max(1, full)), top: top, bottom: full - windowTop + Theme.group,
                cover: windowTop + Theme.windowOverlap)
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += s.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, s.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}

/// 視窗底色。深色時視窗和後面都是黑的，沿著視窗邊描一圈淡線，才看得出視窗在哪（模擬器 2026-11-26）
private struct WindowBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Theme.canvas
            .overlay {
                if scheme == .dark {
                    RoundedRectangle(cornerRadius: Theme.windowRadius, style: .continuous)
                        .strokeBorder(Theme.separator, lineWidth: Theme.hairline)
                        .ignoresSafeArea()
                }
            }
    }
}
