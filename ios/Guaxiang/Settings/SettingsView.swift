import SwiftUI
import VeggieKit

extension VeggieConfig {
    /// 瓜相在蔬菜家族裡的那一份設定。回饋信箱和隱私權政策網址等多米給了再填（.vibe/代決清單.md）
    static let app = VeggieConfig(
        name: "瓜相",
        slug: "guaxiang",
        tagline: "掃一次臉，看古書怎麼說你",
        appStoreID: nil,
        supportEmail: nil,
        privacyURL: nil
    )
}

/// 設定頁。區塊順序照蔬菜家族固定順序（準則 3-3）：app 專屬 → 一般 → 資料 → 購買 → 支援 → 關於 → 頁尾。
/// 只放現在能用的列（3-4）：沒有報告就不放匯出；StoreKit 還沒接就不放購買那一區。
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    /// 報告視窗裡的那一頁：沒有「完成」，也不能關掉整個視窗
    var embedded = false
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system.rawValue
    @AppStorage(VeggieHaptics.storageKey) private var haptics = true
    @State private var confirmErase = false
    @State private var confirmEraseAgain = false
    @State private var showPaywall = false
    @State private var toast: String?
    @State private var filled = 0

    private let config = VeggieConfig.app

    private var style: VeggieStyle {
        VeggieStyle(
            textPrimary: .primary, textSecondary: Theme.secondary, textTertiary: Theme.tertiary,
            accent: Theme.accent, destructive: Theme.danger, canvas: Theme.canvas, surface: Theme.card, body: .body,
            headline: .headline, subheadline: .subheadline, footnote: .footnote, rowHeight: Theme.rowHeight)
    }

    var body: some View {
        NavigationStack {
            Page {
                PageTitle(title: "設定", pushed: true)
                group("關於你") {
                    NavigationLink {
                        Deferred { ProfileView() }
                    } label: {
                        VeggieRow(
                            icon: "person", title: "簡介", value: filled == 0 ? "還沒填" : "填了 \(filled) 項", accessory: .push)
                    }
                }

                group(nil) {
                    NavigationLink {
                        PrivacyNoteView()
                    } label: {
                        VeggieRow(icon: "lock", title: "你的資料去了哪裡", accessory: .push)
                    }
                }

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
                    if let saved = model.saved {
                        ShareLink(item: exportJSON(saved.measurement), preview: SharePreview("瓜相量測數字")) {
                            VeggieRow(icon: "square.and.arrow.up", title: VeggieText.exportData, value: "只有數字")
                        }
                        divider
                    }
                    Button {
                        confirmErase = true
                    } label: {
                        VeggieRow(icon: "trash", title: VeggieText.eraseAll, destructive: true)
                    }
                }

                if Paywall.enforced {
                    group(VeggieText.purchase) {
                        Button {
                            showPaywall = true
                        } label: {
                            VeggieRow(icon: "book.closed", title: "完整版", accessory: .push)
                        }
                        divider
                        Button {
                            // 第 8 步接 StoreKit 時從這裡接（Store/Storage.swift 的 Paywall）
                        } label: {
                            VeggieRow(icon: "arrow.clockwise", title: VeggieText.restore)
                        }
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
                            Deferred { DevToolsView() }
                        } label: {
                            VeggieRow(icon: "wrench.and.screwdriver", title: "範例報告、連電腦、金鑰", accessory: .push)
                        }
                    }
                #endif

                VeggieFooter(config: config, logo: Image("Logo")) { toast = $0 }
                    .padding(.top, Theme.footerTop - Theme.section - Theme.group)
                if let toast { Note(toast).frame(maxWidth: .infinity) }
            }
            .buttonStyle(.plain)
            .veggieStyle(style)
            // 從簡介頁回來也會叫到
            .onAppear { filled = Storage.shared.load(Profile.self, from: .profile)?.filledCount ?? 0 }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !embedded {
                    ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() }.fontWeight(.semibold) }
                }
            }
            .onChange(of: appearance) { _, value in (Appearance(rawValue: value) ?? .system).apply() }
            // 清除問兩次，兩次的按鈕字不同（準則 3-3、5-26）。購買紀錄不動
            .confirmationDialog(
                model.saved == nil
                    ? "要清除報告、照片、簡介和問答紀錄嗎？"
                    : "要清除報告、照片、簡介和問答紀錄嗎？想留數字的話，先用上面的「匯出資料」。",
                isPresented: $confirmErase, titleVisibility: .visible
            ) {
                Button("繼續清除", role: .destructive) { confirmEraseAgain = true }
            }
            .alert("清掉就救不回來", isPresented: $confirmEraseAgain) {
                Button("永久刪除", role: .destructive) {
                    model.eraseAll()
                    if !embedded { dismiss() }
                }
                Button("先不用", role: .cancel) {}
            } message: {
                Text("手機裡的報告、照片、簡介和問答紀錄會全部刪掉，app 回到第一次打開的樣子。已經買的完整版不受影響。")
            }
            .sheet(isPresented: $showPaywall) { PaywallView() }
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.separator).frame(height: Theme.hairline).padding(.leading, Theme.touch)
    }

    private func group<Content: View>(_ title: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.item) {
            if let title {
                Text(title).font(.footnote).foregroundStyle(Theme.secondary).padding(.horizontal, Theme.cardPad)
            }
            VStack(spacing: 0) { content() }
                .padding(.horizontal, Theme.cardPad)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
        .padding(.top, Theme.section - Theme.group)
    }

    private func exportJSON(_ m: Measurement) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(m) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

/// 你的資料去了哪裡。上架時的隱私權政策會照這一頁的內容寫（HANDOFF 第九節）
struct PrivacyNoteView: View {
    @AppStorage(Storage.Keys.aiConsent) private var consent = false

    var body: some View {
        Page {
            PageTitle(title: "你的資料去了哪裡", pushed: true)
            Card {
                CardBlock(divider: false) {
                    Text("只在這支手機上").font(.headline)
                    Text("相機畫面、臉部網格、深度資料只在掃描當下用來算比例，算完就丟。只留最正的那一張照片和上面的標註位置，放在報告最上面。")
                }
                CardBlock {
                    Text("存在手機裡的").font(.headline)
                    Text("上一次的照片和標註位置、量測數字、你填的簡介（含生日）、問答紀錄。照片鎖機的時候讀不到，也不會跟著 iCloud 備份走。按「清除所有資料」會全部刪掉。")
                }
                CardBlock {
                    Text("會離開手機的").font(.headline)
                    Text("只有「問古書」：你同意、按下送出之後，問題、前幾題的問答、簡介和這次量測結果的文字整理會傳給 AI（Anthropic 的 Claude）產生回答。生日只換算成年紀。照片和臉部座標不在裡面。")
                    if consent {
                        Button("撤回同意") { consent = false }.buttonStyle(.ghost)
                        Note("撤回之後，下次問古書會再問你一次。已經傳出去的收不回來。")
                    } else {
                        Note("你現在沒有同意，什麼都不會傳出去。第一次問古書的時候會問你。")
                    }
                }
                CardBlock {
                    Text("不做的事").font(.headline)
                    Text("不拿臉部資料打廣告、不做使用者分析、不接受上傳照片。")
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// NavigationLink 的目的頁在設定頁每次重畫時就會建一次；這兩頁一建就讀檔、讀鑰匙圈，包起來等真的推進去才建
private struct Deferred<Content: View>: View {
    let make: () -> Content

    var body: some View { make() }
}
