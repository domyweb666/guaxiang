import SwiftUI
import UIKit

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
            // 分頁裡每一格各有一條，只認現在看得到的那一條
            if let nav = controller as? UINavigationController, nav.navigationBar.window != nil { return nav.navigationBar }
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
