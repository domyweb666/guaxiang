import SwiftUI
import UIKit

/// 視窗底部的分頁列（QC-0009：五官、三段、十二件事合成「面相」一頁，多一頁設定）
enum ReportTab: String, Hashable, CaseIterable {
    case overview, face, ask, settings
}

/// 報告下方的懸浮視窗：系統的分頁列，一頁一個導覽。
/// 這裡面的提示和推入頁都掛在視窗自己身上；掛在報告頁會被視窗擋住、跳不出來
struct ReportWindow: View {
    @EnvironmentObject private var model: AppModel
    let report: Report
    @Binding var tab: ReportTab
    /// 「面相」那一頁現在捲到哪一區，照片跟著亮
    @Binding var section: ReportSection
    @Binding var detent: PresentationDetent
    /// 有沒有推入的頁，給外層決定要不要停掉左緣返回
    @Binding var pushed: Bool
    @State private var path: [ReportSection] = []

    var body: some View {
        TabView(selection: selection) {
            stack(model.isSample ? "範例報告" : "你的報告", path: $path) { overview }
                .tabItem { Label("總覽", systemImage: "doc.text") }
                .tag(ReportTab.overview)
            stack("面相") { FacePage(report: report, section: $section) }
                .tabItem { Label("面相", systemImage: "face.smiling") }
                .tag(ReportTab.face)
            stack("問古書") { ask }
                .tabItem { Label("問古書", systemImage: "book.closed") }
                .tag(ReportTab.ask)
            SettingsView(embedded: true)
                .tabItem { Label("設定", systemImage: "gearshape") }
                .tag(ReportTab.settings)
        }
        .tint(Theme.accent)
        .background(Theme.canvas.ignoresSafeArea())
        .background(
            WindowPull(expanded: expanded, onResize: resize)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        )
        .overlay(alignment: .top) { heightControl }
        .onChange(of: holdsBack) { _, on in pushed = on }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            // 半高放不下鍵盤
            detent = .large
        }
    }

    /// 視窗裡有上一頁可以回。設定裡面推了哪一頁這裡看不到，整頁都算
    private var holdsBack: Bool { tab == .settings || (tab == .overview && !path.isEmpty) }

    /// 再按一次總覽：推入的頁面退回來
    private var selection: Binding<ReportTab> {
        Binding(
            get: { tab },
            set: { next in
                if next == tab, next == .overview { path = [] }
                tab = next
            })
    }

    private func stack<Content: View>(
        _ title: String, path: Binding<[ReportSection]> = .constant([]), @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationStack(path: path) {
            content()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Theme.canvas, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .navigationDestination(for: ReportSection.self) { section in
                    ReportSectionView(section: section, report: report)
                }
                // 視窗不能關，旁白的返回手勢改成回上一頁
                .accessibilityAction(.escape) { model.closeReport() }
        }
    }

    private var expanded: Bool { detent == .large }

    private func resize(_ expand: Bool) {
        let target: PresentationDetent = expand ? .large : Theme.windowHalf
        if detent != target { detent = target }
    }

    /// 旁白用的橫條：點兩下切換，上下滑調整。手指碰不到它，拉和點由 WindowPull 管
    private var heightControl: some View {
        Color.clear
            .frame(width: Theme.windowTapWidth, height: Theme.group)
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel("報告視窗高度")
            .accessibilityValue(expanded ? "整頁" : "半頁")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { resize(!expanded) }
            .accessibilityAdjustableAction { direction in resize(direction == .increment) }
            .accessibilitySortPriority(1)
    }

    @ViewBuilder private var ask: some View {
        if model.isSample {
            Page {
                Card {
                    CardBlock(divider: false) {
                        Text("範例報告不能問古書").font(.headline)
                        Note("掃過自己的臉之後就能問。")
                    }
                }
                .padding(.top, Theme.item)
            }
        } else {
            AskView(report: report, embedded: true, active: tab == .ask)
        }
    }

    // MARK: 總覽：只放結論和好處，點了看細的

    private var overview: some View {
        Page {
            Text(
                model.isSample ? "數字是假的，不是你的臉。" : report.measurement.when.formatted(date: .long, time: .omitted)
            )
            .font(.subheadline)
            .foregroundStyle(Theme.secondary)
            .padding(.horizontal, Theme.tight)
            .padding(.top, Theme.item)
            if !report.measurement.gaps.isEmpty { gaps }
            NavigationLink(value: ReportSection.wuxing) {
                ShapeHead(report: report).padding(Theme.cardPad)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            }
            .buttonStyle(PressStyle())

            SectionTitle("古書怎麼說你")
            highlights

            Card {
                row(.others, report.others.isEmpty ? "沒有對上" : "\(report.others.count) 條")
                RowDivider()
                row(.cannotSee, nil)
                RowDivider()
                row(.diagram, nil)
            }
            .padding(.top, Theme.section - Theme.group)

            Note("古書的說法沒有人驗證過，報告也不評價人品。不要拿它替你或別人做重大決定。")
                .padding(.top, Theme.section - Theme.group)
                .padding(.horizontal, Theme.tight)
        }
    }

    private var highlights: some View {
        let list = report.highlights
        return Card {
            if list.isEmpty {
                CardBlock(divider: false) { Text("這次沒有對上古書寫的好處。") }
            }
            ForEach(Array(list.enumerated()), id: \.offset) { i, h in
                if i > 0 { RowDivider() }
                Button {
                    open(h.section)
                } label: {
                    HighlightRow(highlight: h)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func open(_ s: ReportSection) {
        guard ReportSection.onFacePage.contains(s) else {
            path.append(s)
            return
        }
        section = s
        tab = .face
    }

    /// 一列：在視窗裡往右推入那一頁
    private func row(_ s: ReportSection, _ value: String?) -> some View {
        NavigationLink(value: s) {
            ReportRow(title: s.title, value: value, locked: s.locked)
        }
        .buttonStyle(.plain)
    }

    private var gaps: some View {
        Card {
            CardBlock(divider: false) {
                Text("這次沒看到的").font(.headline)
                ForEach(report.measurement.gaps, id: \.self) { Note($0, warn: true) }
            }
        }
    }
}

/// 臉形的大字：印章、哪一形、好處。總覽和首頁共用
struct ShapeHead: View {
    let report: Report

    var body: some View {
        HStack(spacing: Theme.cardPad) {
            Text(report.wuxing?.host ?? "？")
                .font(Theme.mark)
                .foregroundStyle(Theme.accent)
                .frame(width: Theme.markSize, height: Theme.markSize)
                .background(Theme.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.tight) {
                Text(report.shapeName).font(.subheadline).foregroundStyle(Theme.secondary)
                Text(report.shapeGood)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// 一個好處：哪件事、好處
struct HighlightRow: View {
    let highlight: Highlight
    var chevron = true

    var body: some View {
        HStack(spacing: Theme.group) {
            VStack(alignment: .leading, spacing: Theme.tight / 2) {
                Text(highlight.topic).font(.footnote).foregroundStyle(Theme.secondary)
                Text(highlight.good).font(.body.weight(.semibold)).foregroundStyle(Color.primary)
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: Theme.item)
            if chevron {
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.tertiary)
            }
        }
        .padding(.horizontal, Theme.cardPad)
        .padding(.vertical, Theme.rowPadV)
        .frame(minHeight: Theme.rowHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
