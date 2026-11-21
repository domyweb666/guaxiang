import SwiftUI

/// 瓜相的樣子：蘋果原生風格，分組灰底、白卡片圓角 26、系統字、主色系統橘（HANDOFF 4-5）。
/// 數值集中在這裡，畫面裡不寫裸數字。domy-design 的 tokens 還沒接（見 .vibe/代決清單.md）。
enum Theme {
    static let accent = Color.orange
    static let ok = Color.green
    static let bad = Color.red
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let fill = Color(uiColor: .tertiarySystemFill)
    static let separator = Color(uiColor: .separator)
    static let secondary = Color.secondary

    static let cardRadius: CGFloat = 26
    static let fieldRadius: CGFloat = 12
    static let tagRadius: CGFloat = 8
    static let margin: CGFloat = 16
    static let cardPadding: CGFloat = 18
    static let gap: CGFloat = 14
    static let small: CGFloat = 6
    static let buttonHeight: CGFloat = 54
    static let barHeight: CGFloat = 10

    /// 古書原文用宋體
    static let quote = Font.custom("Songti TC", size: 17, relativeTo: .body)
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
        VStack(alignment: .leading, spacing: Theme.small) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.cardPadding)
            .padding(.vertical, Theme.margin)
            .overlay(alignment: .top) {
                if divider {
                    Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.leading, Theme.cardPadding)
                }
            }
    }
}

struct SectionTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.title2.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Theme.gap)
            .padding(.horizontal, 4)
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
            .foregroundStyle(warn ? Theme.accent : Theme.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 合格／不合格／沒判／實驗 的小標籤
struct Tag: View {
    let text: String
    let color: Color

    static func status(_ s: Status) -> Tag {
        switch s {
        case .pass: return Tag(text: "合格", color: Theme.ok)
        case .fail: return Tag(text: "不合格", color: Theme.bad)
        case .unjudged: return Tag(text: "沒判", color: .gray)
        }
    }

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.16))
            .clipShape(RoundedRectangle(cornerRadius: Theme.tagRadius, style: .continuous))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var isGhost = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: Theme.buttonHeight)
            .foregroundStyle(isGhost ? Color.primary : Color.white)
            .background(isGhost ? Theme.fill : Theme.accent)
            .clipShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
    static var ghost: PrimaryButtonStyle { PrimaryButtonStyle(isGhost: true) }
}

/// 每一頁共用的外框：灰底、可捲動、左右留邊
struct Page<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gap) { content }
                .padding(.horizontal, Theme.margin)
                .padding(.bottom, 40)
        }
        .background(Theme.canvas.ignoresSafeArea())
    }
}

struct PageTitle: View {
    let title: String
    var lead: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
            if let lead {
                Text(lead).font(.body).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 28)
        .padding(.horizontal, 4)
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
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? Theme.accent : Theme.secondary)
                VStack(alignment: .leading, spacing: 4) {
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
