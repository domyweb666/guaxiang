import SwiftUI

/// 完整版。只從被鎖的那一區或設定頁的「完整版」進來，沒有常駐的升級橫幅（準則 6-17）。
/// 一打開就看得到關閉鍵；拒絕寫「先不用」；按鈕寫「購買」不寫「解鎖」（6-16）；付錢前看得到樣子（3-29）。
/// 價格、題數、承諾句都還沒定（.vibe/代決清單.md），StoreKit 第 8 步才接，現在 Paywall.enforced 是 false，這頁不會出現。
struct PaywallView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.group) {
                    HStack {
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color.primary)
                                .frame(width: Theme.touch, height: Theme.touch)
                                .background(Theme.fill)
                                .clipShape(Circle())
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("關閉")
                    }
                    .padding(.top, Theme.cardPad)
                    VStack(alignment: .leading, spacing: Theme.tight) {
                        Text("完整版").font(.title.bold()).accessibilityAddTraits(.isHeader)
                        Text("一次付清，這支 Apple ID 之後都能用。").foregroundStyle(Theme.secondary)
                    }
                    .padding(.horizontal, Theme.tight)
                    Card {
                        line("三停、十二宮、其他古書條文", divider: false)
                        line("問古書 \(Paywall.includedQuestions) 題")
                        line("再掃幾次都會出完整報告")
                    }
                    .padding(.top, Theme.section - Theme.group)
                    sample
                }
                .padding(.horizontal, Theme.screenMargin)
                .padding(.bottom, Theme.section)
            }
            BottomBar {
                Button("購買完整版") {
                    // 第 8 步接 StoreKit：只由這顆按鈕觸發付款視窗，價格用 displayPrice（6-13）
                }
                .buttonStyle(.primary)
                Button("先不用") { dismiss() }.buttonStyle(.textOnly)
                Button("恢復購買") {
                    // 第 8 步接 StoreKit，結果用 VeggieText 的三句
                }
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
                .frame(minHeight: Theme.touch)
            }
        }
        .background(Theme.canvas.ignoresSafeArea())
    }

    private func line(_ text: String, divider: Bool = true) -> some View {
        VStack(spacing: 0) {
            if divider { RowDivider() }
            HStack(alignment: .firstTextBaseline, spacing: Theme.group) {
                Image(systemName: "checkmark").font(.subheadline.weight(.bold)).foregroundStyle(Theme.accent)
                Text(text)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.cardPad)
            .padding(.vertical, Theme.rowPadV)
        }
    }

    /// 付錢前先看樣子：十二宮「錢財」那一宮的卡，內容是規則庫的真條文，標明是範例
    @ViewBuilder private var sample: some View {
        if let g = model.rules?.palaces.first(where: { $0.id == "caibo" }), let yuanwen = g.yuanwen {
            Note("付錢前先看樣子（範例）").padding(.top, Theme.section - Theme.group).padding(.horizontal, Theme.tight)
            Card {
                CardBlock(divider: false) {
                    HStack {
                        Text("\(g.topic)・\(g.name)").font(.headline)
                        Spacer()
                        Tag.status(.pass)
                    }
                    Text(yuanwen).font(Theme.quote)
                    if let source = g.source { Note(source + "・範例只量了鼻樑直不直") }
                }
            }
        }
    }
}
