import SwiftUI
import UIKit

/// 視窗底部的切換列
enum ReportTab: String, Hashable, CaseIterable {
    case overview, officials, santing, palaces, ask

    var title: String {
        switch self {
        case .overview: return "總覽"
        case .officials: return "五官"
        case .santing: return "三段"
        case .palaces: return "十二件事"
        case .ask: return "問古書"
        }
    }

    /// 這一格放的是報告的哪一區。總覽和問古書不是單一區
    var section: ReportSection? {
        switch self {
        case .officials: return .officials
        case .santing: return .santing
        case .palaces: return .palaces
        case .overview, .ask: return nil
        }
    }

    var locked: Bool { section?.locked ?? false }

    /// 照片上要亮哪一區。鎖住的區不亮
    var mode: AnnotatedPhoto.Mode {
        guard !locked else { return .overview }
        switch self {
        case .officials: return .officials
        case .santing: return .santing
        case .palaces: return .palaces
        case .overview, .ask: return .overview
        }
    }
}

/// 報告下方的懸浮視窗：內容可以往右推入，切換列釘在最下面，一直都在。
/// 這裡面的提示和推入頁都掛在視窗自己身上；掛在報告頁會被視窗擋住、跳不出來
struct ReportWindow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    let report: Report
    @Binding var tab: ReportTab
    @Binding var detent: PresentationDetent
    /// 有沒有推入的頁，給外層決定要不要停掉左緣返回
    @Binding var pushed: Bool
    @State private var path: [ReportSection] = []
    /// 看過的區留著，切回來捲到哪裡、打了什麼字都還在
    @State private var visited: Set<ReportTab> = []
    @State private var keyboardUp = false

    private var rules: Rules { report.rules }
    private var m: Measurement { report.measurement }

    var body: some View {
        VStack(spacing: 0) {
            NavigationStack(path: $path) {
                panes
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
                    // 幾個捲動區疊在一起，系統分不出該看哪一個，底色直接固定
                    .toolbarBackground(Theme.canvas, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
                    .navigationDestination(for: ReportSection.self) { section in
                        ReportSectionView(section: section, report: report)
                    }
                    // 視窗不能關，旁白的返回手勢改成回上一頁
                    .accessibilityAction(.escape) { model.closeReport() }
            }
            if !keyboardUp {
                ReportTabBar(selected: tab, select: select)
                    .transition(
                        reduceMotion
                            ? AnyTransition.opacity : AnyTransition.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Theme.canvas.ignoresSafeArea())
        .background(
            WindowPull(expanded: expanded, onResize: resize)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        )
        .overlay(alignment: .top) { heightControl }
        .onChange(of: path.isEmpty) { _, empty in pushed = !empty }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboard(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboard(false)
        }
    }

    private var title: String {
        guard tab == .overview else { return tab.title }
        return model.isSample ? "範例報告" : "你的報告"
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

    /// 鍵盤出來：切換列讓位，視窗拉到整頁，不然半高只剩一條縫
    private func keyboard(_ up: Bool) {
        guard up != keyboardUp else { return }
        withAnimation(reduceMotion ? nil : Theme.change) { keyboardUp = up }
        if up { detent = .large }
    }

    private func select(_ t: ReportTab) {
        // 再按一次同一格：推入的頁面退回來
        guard t != tab else {
            path = []
            return
        }
        if !path.isEmpty {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { path = [] }
        }
        visited.insert(tab)
        tab = t
    }

    private var panes: some View {
        ZStack {
            ForEach(ReportTab.allCases, id: \.self) { t in
                if t == tab || visited.contains(t) {
                    pane(t)
                        .opacity(t == tab ? 1 : 0)
                        .allowsHitTesting(t == tab)
                        .accessibilityHidden(t != tab)
                }
            }
        }
    }

    @ViewBuilder private func pane(_ t: ReportTab) -> some View {
        switch t {
        case .overview: overview
        case .officials: Page { ReportSectionContent(section: .officials, report: report) }
        case .santing: Page { ReportSectionContent(section: .santing, report: report) }
        case .palaces: Page { ReportSectionContent(section: .palaces, report: report) }
        case .ask:
            if model.isSample {
                Page {
                    Card {
                        CardBlock(divider: false) {
                            Text("範例報告不能問古書").font(.headline)
                            Note("範例的數字是假的，不是你的臉。掃過自己的臉之後就能問。")
                        }
                    }
                    .padding(.top, Theme.item)
                }
            } else {
                AskView(report: report, embedded: true, active: tab == .ask && path.isEmpty)
            }
        }
    }

    // MARK: 總覽

    private var overview: some View {
        Page {
            Text(
                model.isSample
                    ? "數字是假的，不是你的臉。用來看報告長什麼樣。"
                    : "\(m.when.formatted(date: .long, time: .omitted))・收了 \(m.frames) 張畫面"
            )
            .foregroundStyle(Theme.secondary)
            .padding(.horizontal, Theme.tight)
            .padding(.top, Theme.item)
            if !m.gaps.isEmpty { gaps }
            Card { row(.wuxing) }
            cells

            SectionTitle("古書怎麼說你")
            summary
            Card { row(.others) }

            SectionTitle("這次沒看的")
            Card {
                row(.cannotSee)
                RowDivider()
                FlowChips(items: rules.cannotSee.map(\.plain))
                    .padding(.horizontal, Theme.cardPad)
                    .padding(.vertical, Theme.rowPadV)
            }

            Card {
                row(.diagram)
                RowDivider()
                row(.numbers)
            }
            .padding(.top, Theme.section - Theme.group)

            Note("古書的說法沒有經過科學驗證。報告不判健康、壽命、災禍，也不評價人品，不能用來替你或別人做重大決定。")
                .padding(.top, Theme.section - Theme.group)
                .padding(.horizontal, Theme.tight)
        }
    }

    private func value(_ s: ReportSection) -> String? {
        switch s {
        case .wuxing: return report.wuxing.map { "\($0.host)形" } ?? "沒看"
        case .others: return report.others.isEmpty ? "沒有對上" : "\(report.others.count) 條"
        case .cannotSee: return "\(rules.cannotSee.count) 項"
        case .numbers: return "\(report.measuredCount) 項"
        case .officials, .santing, .palaces, .diagram: return nil
        }
    }

    /// 一列：在視窗裡往右推入那一頁
    private func row(_ s: ReportSection) -> some View {
        NavigationLink(value: s) {
            ReportRow(title: s.title, value: value(s), locked: s.locked)
        }
        .buttonStyle(.plain)
    }

    /// 五官、三段、十二件事的摘要格，點了切到那一區
    private var cells: some View {
        let layout =
            typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Theme.item))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.item))
        return layout {
            cell(
                .officials, VerdictShort.lead(report.officialTally, "項"),
                VerdictShort.rest(report.officialTally, "項"))
            cell(.santing, report.santingShort, [report.santingLife])
            cell(
                .palaces, VerdictShort.lead(report.palaceTally, "件"), VerdictShort.rest(report.palaceTally, "件"))
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// sub 有幾段就用「・」接成一行，放不下就在「・」後面斷
    private func cell(_ t: ReportTab, _ value: String, _ sub: [String]) -> some View {
        Button {
            select(t)
        } label: {
            VStack(alignment: .leading, spacing: Theme.tight / 2) {
                HStack(spacing: Theme.tight) {
                    Text(t.title).font(.caption).foregroundStyle(Theme.secondary)
                    if t.locked { Image(systemName: "lock").font(.caption).foregroundStyle(Theme.bad) }
                }
                Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                ViewThatFits(in: .horizontal) {
                    Text(sub.joined(separator: "・")).lineLimit(1)
                    Text(sub.joined(separator: "・\n"))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption)
                .foregroundStyle(Theme.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(Theme.group)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("切到\(t.title)")
    }

    private var summary: some View {
        Card {
            ForEach(Array(report.summaryPoints.enumerated()), id: \.offset) { i, p in
                CardBlock(divider: i > 0) {
                    PlainLine(subject: p.title, note: { p.note }) {
                        (Text(p.title).bold() + Text(p.body.isEmpty ? "" : "：" + p.body))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if !report.unstableNames.isEmpty {
                CardBlock {
                    Note(
                        "有幾項在 \(m.frames) 張畫面之間差很多，結果只當參考：\(report.unstableNames.joined(separator: "、"))。",
                        warn: true)
                }
            }
        }
    }

    private var gaps: some View {
        Card {
            CardBlock(divider: false) {
                Text("這次量不到的").font(.headline)
                ForEach(m.gaps, id: \.self) { Note($0, warn: true) }
                Note("量不到的項目一律寫「沒看」，沒有拿別的數字湊。")
            }
        }
    }
}

/// 切換列：五格等寬，選中的有朱紅淡底
struct ReportTabBar: View {
    let selected: ReportTab
    let select: (ReportTab) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ReportTab.allCases, id: \.self) { t in
                Button {
                    select(t)
                } label: {
                    Text(t.title)
                        .font(.subheadline.weight(t == selected ? .semibold : .regular))
                        .foregroundStyle(t == selected ? Theme.accent : Theme.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: Theme.touch)
                        .background(t == selected ? Theme.accentSoft : Color.clear)
                        .clipShape(Capsule())
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(t.locked ? "\(t.title)，完整版" : t.title)
                .accessibilityAddTraits(t == selected ? .isSelected : [])
            }
        }
        // 字放到最大時五格擠不下，到這一級為止
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.horizontal, Theme.group)
        .padding(.vertical, Theme.tight)
        .background(Theme.canvas.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.separator).frame(height: Theme.hairline).accessibilityHidden(true)
        }
        // 不包成一個有名字的群組：包了之後輔助功能樹只看得到群組，五顆按鈕抓不到
    }
}

/// 視窗的橫條和標題列：往上輕拉就到整頁、往下輕拉就回半高，點一下橫條也會換。
/// 系統自己要拉過一半才換，這裡只補「拉一點點也算」：手指跟著走還是系統的手勢在做，
/// 放手時系統打算留在原來的高度，才改成換過去。兩邊不會一個要升一個要降。
struct WindowPull: UIViewControllerRepresentable {
    let expanded: Bool
    let onResize: (Bool) -> Void

    func makeUIViewController(context: Context) -> Handle {
        Handle()
    }

    func updateUIViewController(_ handle: Handle, context: Context) {
        handle.expanded = expanded
        handle.onResize = onResize
    }

    static func dismantleUIViewController(_ handle: Handle, coordinator: ()) {
        handle.detach()
    }

    /// 放手時要不要換高度。travel、velocity 往下是正的；不用換就回 nil，交給系統
    static func target(expanded: Bool, travel: CGFloat, velocity: CGFloat) -> Bool? {
        // 往另一個高度的方向算正的
        let sign: CGFloat = expanded ? 1 : -1
        let pull = travel * sign, speed = velocity * sign
        if speed >= Theme.windowFlick { return !expanded }
        // 拉過去又甩回來的不算
        if pull >= Theme.windowPull, speed > -Theme.windowFlick { return !expanded }
        return nil
    }

    final class Handle: UIViewController, UIGestureRecognizerDelegate {
        var expanded = false
        var onResize: (Bool) -> Void = { _ in }
        private lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(panned))
        private lazy var tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        private weak var sheet: UISheetPresentationController?
        /// 手勢掛在整個呈現的容器上：它不會動，手指的位置才量得準；橫條也在裡面
        private weak var host: UIView?
        /// 視窗裡的導覽列，標題列到哪裡為止看它
        private weak var bar: UINavigationBar?
        /// 手指放下時的高度和位置
        private var panStart: (expanded: Bool, y: CGFloat)?
        private var tapStart = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
            pan.maximumNumberOfTouches = 1
            for gesture in [pan, tap] as [UIGestureRecognizer] {
                // 返回鈕照樣按得到
                gesture.cancelsTouchesInView = false
                gesture.delaysTouchesEnded = false
                gesture.delegate = self
            }
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            attach()
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            detach()
        }

        private func attach() {
            var top: UIViewController = self
            while let parent = top.parent { top = parent }
            guard host == nil, top.presentingViewController != nil,
                let sheet = top.presentationController as? UISheetPresentationController,
                let container = sheet.containerView
            else { return }
            self.sheet = sheet
            host = container
            container.addGestureRecognizer(pan)
            container.addGestureRecognizer(tap)
        }

        func detach() {
            host?.removeGestureRecognizer(pan)
            host?.removeGestureRecognizer(tap)
            host = nil
            sheet = nil
            bar = nil
            panStart = nil
        }

        // MARK: UIGestureRecognizerDelegate

        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let host, let window = sheet?.presentedViewController.view else { return false }
            let p = touch.location(in: window)
            guard p.y >= -Theme.item, p.y <= stripHeight(in: window) else { return false }
            if gesture === tap {
                guard p.y <= Theme.touch, abs(p.x - window.bounds.midX) <= Theme.windowTapWidth / 2 else { return false }
                if tap.numberOfTouches == 0 { tapStart = expanded }
            } else if pan.numberOfTouches == 0 {
                panStart = (expanded, touch.location(in: host).y)
            }
            return true
        }

        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard gesture === pan else { return true }
            // 橫著滑是返回，不管
            let v = pan.velocity(in: host)
            return abs(v.y) >= abs(v.x)
        }

        func gestureRecognizer(
            _ gesture: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }

        /// 視窗最上面到導覽列底下
        private func stripHeight(in window: UIView) -> CGFloat {
            if bar?.window == nil { bar = sheet.flatMap { Self.navigationBar(in: $0.presentedViewController) } }
            guard let bar, bar.window != nil else { return Theme.windowStrip }
            return bar.convert(bar.bounds, to: window).maxY
        }

        private static func navigationBar(in controller: UIViewController) -> UINavigationBar? {
            if let nav = controller as? UINavigationController { return nav.navigationBar }
            for child in controller.children {
                if let found = navigationBar(in: child) { return found }
            }
            return nil
        }

        // MARK: 換高度

        @objc private func panned() {
            guard pan.state == .ended, let host, let start = panStart else { return }
            let travel = pan.location(in: host).y - start.y
            guard
                let expand = WindowPull.target(
                    expanded: start.expanded, travel: travel, velocity: pan.velocity(in: host).y)
            else { return }
            move(expand, animated: true)
        }

        @objc private func tapped() {
            // 系統的橫條點一下也會換高度。目標照手指放下時的高度算，兩邊換到同一個，不會換過去又換回來
            move(!tapStart, animated: !UIAccessibility.isReduceMotionEnabled)
        }

        /// 等系統自己的放手處理做完，下一輪再換，不然會被它蓋回去
        private func move(_ expand: Bool, animated: Bool) {
            DispatchQueue.main.async { [weak self] in
                guard let self, let sheet = self.sheet else { return }
                // 半高放不下鍵盤
                if !expand { sheet.presentedViewController.view.endEditing(true) }
                // 半高的名字是 SwiftUI 取的，從視窗現有的高度裡找，不寫死
                let id = sheet.detents.map { $0.identifier }.first { ($0 == .large) == expand }
                if let id, (sheet.selectedDetentIdentifier == .large) != expand {
                    if animated {
                        sheet.animateChanges { sheet.selectedDetentIdentifier = id }
                    } else {
                        sheet.selectedDetentIdentifier = id
                    }
                }
                // SwiftUI 那邊同一輪跟上。高度已經一樣，它不會再動一次
                self.onResize(expand)
            }
        }
    }
}

/// 這一頁真的進來了、真的要離開了，各叫一次。
/// SwiftUI 的 onDisappear 要等整頁滑完才來，視窗會多留在首頁上一下；這裡在返回一開始就收。
/// 左緣滑到一半：先不動，放手確定要離開才收，滑回來取消就當沒發生。
/// blocksBack 是 true 的時候停掉這一頁的返回手勢；變回 false、離開這一頁、這一頁被拿掉，都會還原。
struct PageLifecycle: UIViewControllerRepresentable {
    let blocksBack: Bool
    let onShow: () -> Void
    let onLeave: () -> Void

    func makeUIViewController(context: Context) -> Watcher {
        Watcher()
    }

    func updateUIViewController(_ watcher: Watcher, context: Context) {
        watcher.onShow = onShow
        watcher.onLeave = onLeave
        watcher.blocksBack = blocksBack
        watcher.applyBack()
    }

    static func dismantleUIViewController(_ watcher: Watcher, coordinator: ()) {
        watcher.releaseBack()
    }

    final class Watcher: UIViewController {
        var onShow: () -> Void = {}
        var onLeave: () -> Void = {}
        var blocksBack = false
        private var onScreen = false
        private var shown = false
        /// 被這一頁停掉的返回手勢
        private var held: [UIGestureRecognizer] = []

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            onScreen = true
            applyBack()
            show(tries: 30)
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            guard let move = transitionCoordinator, move.isInteractive else {
                leave()
                return
            }
            move.notifyWhenInteractionChanges { [weak self] state in
                if !state.isCancelled { self?.leave() }
            }
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            leave()
        }

        /// 別的視窗還在收（例如從設定頁開範例報告），等它收完再升起，不然會跳不出來
        private func show(tries: Int) {
            guard onScreen, !shown else { return }
            if tries > 0, view.window?.rootViewController?.presentedViewController != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.show(tries: tries - 1)
                }
                return
            }
            shown = true
            DispatchQueue.main.async { [onShow] in onShow() }
        }

        /// 只動這一頁所在的那個 UINavigationController。視窗裡的是另一個，不受影響
        func applyBack() {
            guard blocksBack, onScreen else {
                releaseBack()
                return
            }
            guard let nav = navigationController else { return }
            var gestures: [UIGestureRecognizer] = []
            if let edge = nav.interactivePopGestureRecognizer { gestures.append(edge) }
            if #available(iOS 26.0, *), let content = nav.interactiveContentPopGestureRecognizer {
                gestures.append(content)
            }
            for gesture in gestures where gesture.isEnabled {
                gesture.isEnabled = false
                held.append(gesture)
            }
        }

        func releaseBack() {
            for gesture in held { gesture.isEnabled = true }
            held = []
        }

        private func leave() {
            onScreen = false
            releaseBack()
            guard shown else { return }
            shown = false
            // 可能正在 SwiftUI 更新畫面的途中被叫到，下一輪再改狀態
            DispatchQueue.main.async { [onLeave] in onLeave() }
        }
    }
}
