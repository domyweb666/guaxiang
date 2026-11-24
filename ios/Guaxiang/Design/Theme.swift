import SwiftUI
import UIKit

/// 瓜相的樣子：方向 B「朱印古書」（多米 2026-11-22 在改版畫板上選的）。
/// 暖紙底、白卡片、朱紅印章色當主色，古書原文用宋體。
/// 數值照 domy-design tokens.json：間距用途名（準則 3-46）、圓角刻度、尺寸。
/// domy-design 的 tokens 還沒接進來（私有 repo，見 .vibe/代決清單.md 第 6 項），先把同樣的數字集中在這裡。
/// 畫面檔只准用這裡的名字，不寫裸數字。
enum Theme {
    // MARK: 顏色（淺色／深色各一份，對比都算過 4.5:1）

    /// 主色：朱紅。淺色 #B33A2B（白字 5.9:1），深色 #F2877A（深字 7.6:1）
    static let accent = dynamic(0xB33A2B, 0xF2877A)
    /// 壓在主色上的字
    static let onAccent = dynamic(0xFFFFFF, 0x2A0E0A)
    static let accentSoft = dynamic(0xF6E4DF, 0x3A1E1B)
    /// 合格：綠
    static let ok = dynamic(0x2F6B4F, 0x9DC2A5)
    static let okSoft = dynamic(0xE3ECE5, 0x22322A)
    /// 不合格：琥珀。刻意不用紅，避免跟主色混在一起
    static let bad = dynamic(0x7A4B00, 0xE9C46A)
    static let badSoft = dynamic(0xF6EBD5, 0x3A2F17)
    /// 會刪東西的動作
    static let danger = dynamic(0xC4372C, 0xFF6B5E)

    /// 暖紙畫布（domy-design canvas.warm）
    static let canvas = dynamic(0xF7F4EC, 0x14130F)
    static let card = dynamic(0xFFFFFF, 0x1C1C1E)
    /// 次要按鈕、小格子的底（neutral.surfaceMuted）
    static let fill = dynamic(0xEFEBE3, 0x2C2C2E)
    static let separator = dynamic(0xE5E1D8, 0x38383A)
    static let fieldBorder = dynamic(0xD8D3C8, 0x48484A)
    static let secondary = dynamic(0x66666D, 0xA1A1A8)
    static let tertiary = dynamic(0xA1A1A6, 0x636366)

    // MARK: 照片上的標註（疊在照片上，淺色深色都一樣）

    static let markBrow = fixed(0xC77DFF)
    static let markEye = fixed(0x3DA5FF)
    static let markNose = fixed(0x3DDC84)
    static let markMouth = fixed(0xFF6B8A)
    static let markLine = fixed(0xFFB224)
    /// 壓在 markLine 上的字
    static let markLineText = fixed(0x2A1A00)
    /// 十二宮判得到的那幾宮（跟淺色主色同一個朱紅，白字 5.9:1）
    static let markPalace = fixed(0xB33A2B)
    /// 照片上小標籤的深色底
    static let markShade = Color.black.opacity(0.55)
    static let markWidth: CGFloat = 2
    static let markDot: CGFloat = 10

    // MARK: 間距用途名（domy-design layout，準則 3-46）

    static let pageTop: CGFloat = 40
    static let screenMargin: CGFloat = 20
    static let section: CGFloat = 24
    static let group: CGFloat = 12
    static let item: CGFloat = 8
    static let tight: CGFloat = 4
    static let cardPad: CGFloat = 16
    static let rowPadV: CGFloat = 12
    static let footerTop: CGFloat = 48

    // MARK: 形狀與尺寸

    static let cardRadius: CGFloat = 24
    static let innerRadius: CGFloat = 16
    static let fieldRadius: CGFloat = 12
    static let tagRadius: CGFloat = 8
    /// 列高、一般按鈕（size.row、size.button）
    static let rowHeight: CGFloat = 52
    static let buttonHeight: CGFloat = 52
    /// 每個畫面最主要的那顆按鈕。單手檢查要約 60 點（準則 3-19），先取 56
    static let primaryHeight: CGFloat = 56
    static let touch: CGFloat = 44
    static let barHeight: CGFloat = 10
    static let markSize: CGFloat = 72
    static let emptyIcon: CGFloat = 64
    static let hairline: CGFloat = 1
    static let sketchWidth: CGFloat = 180

    // MARK: 報告的懸浮視窗

    /// 半高：約佔下半
    static let windowFraction: CGFloat = 0.5
    static let windowHalf = PresentationDetent.fraction(windowFraction)
    static let windowRadius: CGFloat = 36
    /// 照片往視窗底下多鋪一段：圓角兩旁和 iOS 26 縮進去的地方才不會露底
    static let windowOverlap: CGFloat = 64
    /// 照片最上面那層淡底，返回鈕和狀態列才看得清楚
    static let scrimOpacity: Double = 0.6

    // MARK: 動作（附錄 E 步驟 4）

    static let press = Animation.snappy
    static let change = Animation.snappy
    static let transition = Animation.smooth
    static let pressScale: CGFloat = 0.96
    static let pressOpacity: Double = 0.85

    // MARK: 字

    /// 古書原文用宋體，跟著系統字級縮放
    static let quote = Font.custom("Songti TC", size: 17, relativeTo: .body)
    static let quoteLarge = Font.custom("Songti TC", size: 20, relativeTo: .title3)
    static let mark = Font.custom("Songti TC", size: 36, relativeTo: .largeTitle).weight(.bold)

    private static func fixed(_ hex: UInt32) -> Color {
        Color(uiColor: rgb(hex))
    }

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(
            uiColor: UIColor { traits in
                rgb(traits.userInterfaceStyle == .dark ? dark : light)
            })
    }

    private static func rgb(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// 白卡片。裡面放一到多個 CardBlock，中間自動畫分隔線
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

struct CardBlock<Content: View>: View {
    var divider = true
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.item) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.cardPad)
            .padding(.vertical, Theme.cardPad)
            .overlay(alignment: .top) {
                if divider {
                    Rectangle().fill(Theme.separator).frame(height: Theme.hairline).padding(.leading, Theme.cardPad)
                }
            }
    }
}

/// 區塊標題：上面留 section，下面到卡片留 item
struct SectionTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.title2.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Theme.section - Theme.group)
            .padding(.horizontal, Theme.tight)
            .accessibilityAddTraits(.isHeader)
    }
}

/// 小字說明
struct Note: View {
    let text: String
    var warn = false

    init(_ text: String, warn: Bool = false) {
        self.text = text
        self.warn = warn
    }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(warn ? Theme.bad : Theme.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 合格／不合格／沒判／實驗 的小標籤
struct Tag: View {
    let text: String
    let color: Color
    var background: Color?

    static func status(_ s: Status) -> Tag {
        switch s {
        case .pass: return Tag(text: "合格", color: Theme.ok, background: Theme.okSoft)
        case .fail: return Tag(text: "不合格", color: Theme.bad, background: Theme.badSoft)
        case .unjudged: return Tag(text: "沒判", color: Theme.secondary, background: Theme.fill)
        }
    }

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, Theme.item)
            .padding(.vertical, Theme.tight / 2)
            .background(background ?? Theme.fill)
            .clipShape(RoundedRectangle(cornerRadius: Theme.tagRadius, style: .continuous))
    }
}

/// 自己畫外觀的可點元件：按下縮到 0.96、變淡一點（附錄 E 第 8 項）
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? Theme.pressScale : 1)
            .opacity(configuration.isPressed ? Theme.pressOpacity : 1)
            .animation(Theme.press, value: configuration.isPressed)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    enum Kind { case primary, ghost, text }
    var kind: Kind = .primary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: height)
            .foregroundStyle(foreground)
            .background(background)
            .clipShape(Capsule())
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? Theme.pressScale : 1)
            .opacity(configuration.isPressed ? Theme.pressOpacity : 1)
            .animation(Theme.press, value: configuration.isPressed)
    }

    private var height: CGFloat {
        switch kind {
        case .primary: return Theme.primaryHeight
        case .ghost: return Theme.buttonHeight
        case .text: return Theme.touch
        }
    }

    private var foreground: Color {
        guard isEnabled else { return Theme.secondary }
        switch kind {
        case .primary: return Theme.onAccent
        case .ghost: return Color.primary
        case .text: return Theme.accent
        }
    }

    private var background: Color {
        switch kind {
        case .primary: return isEnabled ? Theme.accent : Theme.separator
        case .ghost: return Theme.fill
        case .text: return .clear
        }
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    /// 每個畫面最主要的一顆：朱紅實心
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle(kind: .primary) }
    /// 次要：淺底
    static var ghost: PrimaryButtonStyle { PrimaryButtonStyle(kind: .ghost) }
    /// 只有字：朱紅字
    static var textOnly: PrimaryButtonStyle { PrimaryButtonStyle(kind: .text) }
}

/// 每一頁共用的外框：暖紙底、可捲動、左右留 20。
/// 大標題由 PageTitle 自己留 pageTop；推入的頁面（上面有返回列）用 PageTitle(pushed: true)。
struct Page<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.group) { content }
                .padding(.horizontal, Theme.screenMargin)
                .padding(.bottom, Theme.footerTop)
        }
        .background(Theme.canvas.ignoresSafeArea())
    }
}

/// 底部固定一兩顆按鈕的頁面：內容可以捲，按鈕永遠在拇指碰得到的地方
struct BottomBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: Theme.item) { content }
            .padding(.horizontal, Theme.screenMargin)
            .padding(.top, Theme.group)
            .padding(.bottom, Theme.item)
            .background(Theme.canvas)
    }
}

struct PageTitle: View {
    let title: String
    var lead: String?
    /// 推入的頁面上面已經有返回列，不再多留 pageTop
    var pushed = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.tight) {
            Text(title).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
            if let lead {
                Text(lead).font(.body).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, pushed ? Theme.item : Theme.pageTop)
        .padding(.bottom, Theme.section - Theme.group)
        .padding(.horizontal, Theme.tight)
    }
}

/// 一列：左邊名稱、右邊狀態、最右邊箭頭。整列都能點
struct ReportRow: View {
    let title: String
    var value: String?
    var locked = false

    var body: some View {
        HStack(spacing: Theme.group) {
            Text(title).font(.body).foregroundStyle(Color.primary)
            if locked {
                Text("完整版")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.bad)
                    .padding(.horizontal, Theme.item)
                    .padding(.vertical, Theme.tight / 2)
                    .background(Theme.badSoft)
                    .clipShape(Capsule())
            }
            Spacer(minLength: Theme.item)
            if let value {
                Text(value).font(.subheadline).foregroundStyle(Theme.secondary).multilineTextAlignment(.trailing)
            }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.tertiary)
        }
        .padding(.horizontal, Theme.cardPad)
        .padding(.vertical, Theme.rowPadV)
        .frame(minHeight: Theme.rowHeight)
        .contentShape(Rectangle())
    }
}

struct RowDivider: View {
    var body: some View {
        Rectangle().fill(Theme.separator).frame(height: Theme.hairline).padding(.leading, Theme.cardPad)
    }
}

/// 打勾的那一列
struct CheckRow: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: Theme.group) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? Theme.accent : Theme.tertiary)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: Theme.tight) {
                    Text(title).font(.body).foregroundStyle(Color.primary).multilineTextAlignment(.leading)
                    if let detail { Note(detail) }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// 首頁和範例用的臉部示意圖：一張臉的輪廓，加三停的四條分界線
struct FaceSketch: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * w, y: y * h) }
            var face = Path()
            face.move(to: p(0.5, 0.07))
            face.addCurve(to: p(0.86, 0.49), control1: p(0.76, 0.07), control2: p(0.87, 0.26))
            face.addCurve(to: p(0.5, 0.94), control1: p(0.84, 0.73), control2: p(0.69, 0.93))
            face.addCurve(to: p(0.14, 0.49), control1: p(0.31, 0.93), control2: p(0.16, 0.73))
            face.addCurve(to: p(0.5, 0.07), control1: p(0.13, 0.26), control2: p(0.24, 0.07))
            var features = Path()
            features.move(to: p(0.31, 0.42))
            features.addQuadCurve(to: p(0.44, 0.42), control: p(0.38, 0.39))
            features.move(to: p(0.56, 0.42))
            features.addQuadCurve(to: p(0.69, 0.42), control: p(0.62, 0.39))
            features.move(to: p(0.5, 0.45))
            features.addLine(to: p(0.48, 0.64))
            features.addQuadCurve(to: p(0.53, 0.64), control: p(0.5, 0.66))
            features.move(to: p(0.4, 0.76))
            features.addQuadCurve(to: p(0.6, 0.76), control: p(0.5, 0.8))
            context.stroke(face, with: .color(.primary), lineWidth: 2)
            context.stroke(features, with: .color(.primary), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            for y in [0.2, 0.38, 0.64, 0.93] {
                var line = Path()
                line.move(to: p(0.04, y))
                line.addLine(to: p(0.96, y))
                context.stroke(line, with: .color(Theme.accent), style: StrokeStyle(lineWidth: 1.4, dash: [4, 4]))
            }
        }
        .aspectRatio(0.9, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
