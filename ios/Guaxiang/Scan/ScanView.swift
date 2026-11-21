import SwiftUI
import UIKit
import VeggieKit

/// 掃臉：相機畫面、橢圓框、一句提示、進度條
struct ScanView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var session = FaceScanSession()
    @State private var showTip = false

    var body: some View {
        VStack(spacing: Theme.gap) {
            ZStack(alignment: .bottom) {
                CameraPreview(session: session)
                Ellipse()
                    .strokeBorder(
                        session.isGood ? Theme.ok : Color.white.opacity(0.55),
                        style: StrokeStyle(lineWidth: 4, dash: session.isGood ? [] : [8, 6])
                    )
                    .padding(.horizontal, 56)
                    .padding(.vertical, 48)
                Text(session.failure ?? session.hint)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.6), radius: 6, y: 1)
                    .padding(.horizontal, Theme.margin)
                    .padding(.bottom, 22)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .clipped()

            ProgressView(value: Double(session.count), total: Double(ScanGate.needFrames))
                .tint(Theme.ok)
                .padding(.horizontal, Theme.margin)
            Note("\(session.count) / \(ScanGate.needFrames) 張合格畫面")
            #if DEVTOOLS
                Note(session.debugLine)
            #endif
            if showTip {
                Card {
                    CardBlock(divider: false) {
                        Note("卡住了嗎？確認眼鏡拿下來了、面向窗戶、手機拿在眼睛高度、離臉大約一個手掌半的距離，表情放鬆不用笑。")
                    }
                }
                .padding(.horizontal, Theme.margin)
            }
            Spacer(minLength: 0)
            Button("取消") {
                session.stop()
                model.stage = .consent
            }
            .buttonStyle(.ghost)
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, Theme.margin)
        }
        .background(Theme.canvas.ignoresSafeArea())
        .onAppear { session.start(collect: true) }
        .onDisappear { session.stop() }
        .task {
            // 一分鐘還沒掃完，給一張提示卡
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            showTip = true
        }
        .onChange(of: session.count) { _, _ in
            if VeggieHaptics.isEnabled, session.count == ScanGate.needFrames {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
        .onReceive(session.$finished) { capture in
            if let capture { model.scanFinished(capture) }
        }
    }
}

/// 拉髮際線。網格量不到髮際線（哪種方法都抓不到），讓使用者自己拖；有瀏海可以跳過，跳過就不判三停。
struct HairlineView: View {
    @EnvironmentObject private var model: AppModel
    /// 髮際線的高度，佔照片高度的比例（0 在最上面）
    @State private var lineY = 0.25
    @State private var ready = false

    var body: some View {
        Page {
            PageTitle(title: "拉一條髮際線", lead: "相機量不到髮際線。把橘色線拖到你額頭頭髮開始長的地方，三停才算得出來。")
            if let image = model.capture?.best.image {
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .scaleEffect(x: -1, y: 1) // 跟自拍一樣左右相反
                        Rectangle()
                            .fill(Theme.accent)
                            .frame(height: 3)
                            .overlay(Rectangle().stroke(Color.white.opacity(0.7), lineWidth: 1))
                            .overlay(alignment: .topTrailing) {
                                Text("髮際")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Theme.accent)
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.tagRadius))
                                    .offset(x: -10, y: -28)
                            }
                            .offset(y: CGFloat(lineY) * geo.size.height)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0).onChanged { value in
                            lineY = min(0.98, max(0.02, Double(value.location.y / geo.size.height)))
                        }
                    )
                    .accessibilityElement()
                    .accessibilityLabel("髮際線")
                    .accessibilityAdjustableAction { direction in
                        lineY = min(0.98, max(0.02, lineY + (direction == .increment ? -0.01 : 0.01)))
                    }
                }
                .aspectRatio(image.size.width / max(1, image.size.height), contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            }
            Button("就是這裡") { model.finish(hairRatio: ratio()) }
                .buttonStyle(.primary)
            Button("我有瀏海，跳過") { model.finish(hairRatio: nil) }
                .buttonStyle(.ghost)
        }
        .onAppear {
            guard !ready, let best = model.capture?.best, let g = best.glabella else { return }
            ready = true
            // 預設位置：眉心往上，約一個中停的長度
            if let s = best.subnasale {
                lineY = min(0.98, max(0.02, g.y - (s.y - g.y) * 0.95))
            } else {
                lineY = max(0.02, g.y - 0.15)
            }
        }
    }

    private func ratio() -> Double? {
        guard let best = model.capture?.best, let image = best.image, let g = best.glabella, let c = best.chin,
            let fg = best.frame[.glabella], let fc = best.frame[.chin], let cheekR = best.frame[.cheekR],
            let cheekL = best.frame[.cheekL]
        else { return nil }
        let w = Double(image.size.width), h = Double(image.size.height)
        return FeatureEngine.hairRatio(
            lineY: lineY * h, glabella: Pt(x: g.x * w, y: g.y * h), chin: Pt(x: c.x * w, y: c.y * h),
            faceGlabellaToChin: Geometry.dist(fg, fc), faceWidth: Geometry.dist(cheekR, cheekL))
    }
}
