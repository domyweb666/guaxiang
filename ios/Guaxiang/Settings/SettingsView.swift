import SwiftUI
import VeggieKit

extension VeggieConfig {
    /// 瓜相在蔬菜家族裡的那一份設定。回饋信箱和隱私權政策網址等多米給了再填（.vibe/代決清單.md）
    static let app = VeggieConfig(
        name: "瓜相",
        slug: "guaxiang",
        tagline: "掃一次臉，看懂古書怎麼說你",
        appStoreID: nil,
        supportEmail: nil,
        privacyURL: nil
    )
}

/// 設定頁。區塊順序照《蔬菜家族共用規格》：一般、資料、支援、關於，最下面是共用頁尾。
/// 「購買」那一區等第 8 步接 StoreKit 再放。
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system.rawValue
    @AppStorage(VeggieHaptics.storageKey) private var haptics = true
    @State private var confirmErase = false
    @State private var toast: String?

    private let config = VeggieConfig.app

    private var style: VeggieStyle {
        VeggieStyle(
            textPrimary: .primary, textSecondary: .secondary, textTertiary: Color(uiColor: .tertiaryLabel),
            accent: Theme.accent, destructive: Theme.bad, canvas: Theme.canvas, surface: Theme.card, body: .body,
            headline: .headline, subheadline: .subheadline, footnote: .footnote, rowHeight: 52)
    }

    var body: some View {
        NavigationStack {
            Page {
                group(VeggieText.general) {
                    Menu {
                        Picker(VeggieText.appearance, selection: $appearance) {
                            ForEach(Appearance.allCases) { Text($0.title).tag($0.rawValue) }
                        }
                    } label: {
                        VeggieRow(
                            icon: "circle.lefthalf.filled", title: VeggieText.appearance,
                            value: (Appearance(rawValue: appearance) ?? .system).title)
                    }
                    divider
                    VeggieToggleRow(icon: "iphone.radiowaves.left.and.right", title: VeggieText.haptics, isOn: $haptics)
                }

                group(VeggieText.data) {
                    NavigationLink {
                        PrivacyNoteView()
                    } label: {
                        VeggieRow(icon: "lock", title: "資料存在哪裡", accessory: .push)
                    }
                    divider
                    Button {
                        confirmErase = true
                    } label: {
                        VeggieRow(icon: "trash", title: VeggieText.eraseAll, destructive: true)
                    }
                }

                group(VeggieText.support) {
                    ShareLink(item: config.shareText) {
                        VeggieRow(icon: "square.and.arrow.up", title: VeggieText.share)
                    }
                }

                group(VeggieText.about) {
                    NavigationLink {
                        VeggieFamilyView(config: config)
                    } label: {
                        VeggieRow(icon: "leaf", title: VeggieText.family, accessory: .push)
                    }
                }

                #if DEVTOOLS
                    group("開發工具（上架前會拿掉）") {
                        NavigationLink {
                            DevToolsView()
                        } label: {
                            VeggieRow(icon: "wrench.and.screwdriver", title: "頂點對照、範例報告、金鑰", accessory: .push)
                        }
                    }
                #endif

                VeggieFooter(config: config, logo: Image("Logo")) { toast = $0 }
                if let toast { Note(toast).frame(maxWidth: .infinity) }
            }
            .buttonStyle(.plain)
            .veggieStyle(style)
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
            }
            .onChange(of: appearance) { _, value in (Appearance(rawValue: value) ?? .system).apply() }
            .confirmationDialog("清除報告、簡介和問答紀錄？清掉就救不回來。", isPresented: $confirmErase, titleVisibility: .visible) {
                Button(VeggieText.eraseAll, role: .destructive) {
                    model.eraseAll()
                    dismiss()
                }
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.leading, 36)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.small) {
            Text(title).font(.footnote).foregroundStyle(Theme.secondary).padding(.horizontal, Theme.cardPadding)
            VStack(spacing: 0) { content() }
                .padding(.horizontal, Theme.cardPadding)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
        .padding(.top, Theme.small)
    }
}

/// 資料存在哪裡。上架時的隱私權政策會照這一頁的內容寫（HANDOFF 第九節）
struct PrivacyNoteView: View {
    var body: some View {
        Page {
            Card {
                CardBlock(divider: false) {
                    Text("只在這支手機上").font(.headline)
                    Text("相機畫面、臉部網格、深度資料只在掃描當下用來算比例，算完就丟，不存檔、不上傳。照片也不存。")
                }
                CardBlock {
                    Text("存在手機裡的").font(.headline)
                    Text("上一次的量測數字、你填的簡介、問答紀錄。按「清除所有資料」會全部刪掉。")
                }
                CardBlock {
                    Text("會離開手機的").font(.headline)
                    Text("只有「問古書」：你勾了同意、按下「問」之後，簡介、問題和這次量測結果的文字整理會傳給 AI（Anthropic 的 Claude）產生回答。照片和臉部座標不在裡面。")
                }
                CardBlock {
                    Text("不做的事").font(.headline)
                    Text("不拿臉部資料打廣告、不做使用者分析、不接受上傳照片。")
                }
            }
        }
        .navigationTitle("資料存在哪裡")
        .navigationBarTitleDisplayMode(.inline)
    }
}
