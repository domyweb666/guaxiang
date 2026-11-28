import SwiftUI
import UIKit
import VeggieKit

/// 掃臉：深色底、相機畫面、橢圓框外圈是進度、一次只講一件事
struct ScanView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var session = FaceScanSession()
    @State private var showTip = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var progress: Double { min(1, Double(session.count) / Double(ScanGate.needFrames)) }
    private var percent: Int { Int((progress * 100).rounded(.down)) }

    var body: some View {
        Group {
            if let blocked = session.blocked {
                ScanBlockedView(blocked: blocked)
            } else {
                scanner
            }
        }
        .navigationBarBackButtonHidden(session.blocked == nil)
        .toolbar(session.blocked == nil ? .hidden : .visible, for: .navigationBar)
        .onAppear { session.start() }
        .onDisappear { session.stop() }
        .onReceive(session.$finished) { capture in
            if let capture { model.scanFinished(capture) }
        }
    }

    private var scanner: some View {
        VStack(spacing: Theme.group) {
            HStack {
                Button("取消") {
                    session.stop()
                    model.cancelScan()
                }
                .frame(minWidth: Theme.touch, minHeight: Theme.touch)
                Spacer()
                Text("只留一張照片在手機裡，不上傳").font(.footnote)
            }
            .foregroundStyle(ScanColor.text)
            .padding(.horizontal, Theme.screenMargin)

            ZStack {
                CameraPreview(session: session)
                    .clipShape(Ellipse())
                    .padding(Theme.group)
                Ellipse()
                    .stroke(ScanColor.track, lineWidth: 6)
                    .padding(Theme.group)
                Ellipse()
                    .trim(from: 0, to: progress)
                    .stroke(
                        session.isGood ? ScanColor.good : ScanColor.ring,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .padding(Theme.group)
                    .animation(reduceMotion ? nil : Theme.change, value: session.count)
            }
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .padding(.horizontal, Theme.section)
            .overlay(alignment: .bottom) {
                Text("\(percent)%")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText(value: Double(percent)))
                    .foregroundStyle(ScanColor.text)
                    .padding(.horizontal, Theme.cardPad)
                    .padding(.vertical, Theme.tight)
                    .background(ScanColor.chip)
                    .clipShape(Capsule())
            }
            .accessibilityElement()
            .accessibilityLabel("掃描百分之 \(percent)")

            Text(session.failure ?? session.hint)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .foregroundStyle(ScanColor.text)
                .padding(.horizontal, Theme.screenMargin)
                .padding(.top, Theme.section)
                .accessibilityAddTraits(.updatesFrequently)
            Text("一次只提醒一件事。對了就自動繼續收。")
                .font(.subheadline)
                .foregroundStyle(ScanColor.secondary)

            Spacer(minLength: 0)
            if showTip {
                Text("卡住了嗎？確認眼鏡拿下來了、面向窗戶、手機拿在眼睛高度、離臉大約一個手掌半，表情放鬆不用笑。")
                    .font(.footnote)
                    .foregroundStyle(ScanColor.text)
                    .padding(Theme.cardPad)
                    .background(ScanColor.chip)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous))
                    .padding(.horizontal, Theme.screenMargin)
            }
            #if DEVTOOLS
                Text(session.debugLine).font(.caption2).foregroundStyle(ScanColor.secondary)
            #endif
            Text("掃到 100% 就好。中途離開 app，回來從頭掃。")
                .font(.footnote)
                .foregroundStyle(ScanColor.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.screenMargin)
                .padding(.bottom, Theme.item)
        }
        .background(ScanColor.background.ignoresSafeArea())
        .task {
            // 一分鐘還沒掃完，給一張提示卡
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            showTip = true
        }
        .onChange(of: session.count) { _, count in
            if VeggieHaptics.isEnabled, count == ScanGate.needFrames {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }
}

/// 掃描畫面固定用深色，淺色深色模式都一樣，讓相機畫面最亮
private enum ScanColor {
    static let background = Color(red: 0x1A / 255, green: 0x17 / 255, blue: 0x14 / 255)
    static let chip = Color(red: 0x2C / 255, green: 0x27 / 255, blue: 0x24 / 255)
    static let track = Color(red: 0x3A / 255, green: 0x35 / 255, blue: 0x30 / 255)
    static let ring = Color(red: 0xE8 / 255, green: 0x82 / 255, blue: 0x6F / 255)
    static let good = Color(red: 0x9D / 255, green: 0xC2 / 255, blue: 0xA5 / 255)
    static let text = Color(red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF7 / 255)
    static let secondary = Color(red: 0xA1 / 255, green: 0xA1 / 255, blue: 0xA8 / 255)
}

/// 掃不了：相機被拒、手機沒有原深感相機。整頁說明，給下一步（準則 3-32、10-7）
struct ScanBlockedView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openURL) private var openURL
    let blocked: FaceScanSession.Blocked

    var body: some View {
        VStack(spacing: Theme.section) {
            Spacer(minLength: 0)
            ContentUnavailableView {
                Label(
                    blocked == .denied ? "沒有相機權限，這次掃不了" : "這支手機量不到臉的深度",
                    systemImage: blocked == .denied ? "video.slash" : "faceid")
            } description: {
                Text(
                    blocked == .denied
                        ? "瓜相用前鏡頭量臉的比例。畫面只在手機上處理，不上傳。到設定打開相機就能掃。"
                        : "瓜相要用 Face ID 那顆原深感相機量臉。這支手機沒有，這一版還不能掃。")
            }
            VStack(spacing: Theme.item) {
                if blocked == .denied {
                    Button("前往設定") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .buttonStyle(.primary)
                }
                Button("先看一份範例報告") { model.openSample() }
                    .buttonStyle(PrimaryButtonStyle(kind: blocked == .denied ? .text : .primary))
            }
            .padding(.horizontal, Theme.screenMargin)
            Spacer(minLength: 0)
        }
        .background(Theme.canvas.ignoresSafeArea())
    }
}
