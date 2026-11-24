#if DEVTOOLS
    import SwiftUI

    /// 開發工具。只在編譯時有開 DEVTOOLS 的版本裡出現，上架前整區拿掉。
    struct DevToolsView: View {
        @EnvironmentObject private var model: AppModel
        @Environment(\.dismiss) private var dismiss
        @State private var key = ""
        @State private var bridge = ClaudeBridge.current
        @State private var address = ""
        @State private var scanning = false
        @State private var checking = false
        @State private var bridgeNote: String?
        @State private var bridgeFailed = false
        @State private var hasKey = Keychain.get(Storage.Keys.devAPIKey) != nil

        var body: some View {
            Page {
                SectionTitle("範例報告")
                Card {
                    CardBlock(divider: false) {
                        Note("用一組假數字開報告，看畫面長什麼樣。不會蓋掉你存的報告。")
                        Button("開範例報告") {
                            model.openSample()
                            dismiss()
                        }
                        .buttonStyle(.ghost)
                    }
                }

                SectionTitle("連電腦的 Claude CLI")
                bridgeCard

                SectionTitle("問古書的金鑰")
                Card {
                    CardBlock(divider: false) {
                        Note("中繼站還沒架好之前，貼自己的 Anthropic 金鑰可以先試問答。金鑰只存在這支手機的鑰匙圈，直接從手機送出。")
                        if hasKey {
                            Text("已經存了一把金鑰")
                            Button("刪掉金鑰") {
                                Keychain.delete(Storage.Keys.devAPIKey)
                                hasKey = false
                            }
                            .buttonStyle(.ghost)
                        } else {
                            SecureField("sk-ant-...", text: $key)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(10)
                                .background(Theme.fill)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.fieldRadius))
                            Button("存金鑰") {
                                let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !trimmed.isEmpty else { return }
                                Keychain.set(trimmed, for: Storage.Keys.devAPIKey)
                                key = ""
                                hasKey = true
                            }
                            .buttonStyle(.ghost)
                        }
                    }
                }
            }
            .navigationTitle("開發工具")
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $scanning) {
                QRScanner { text in
                    scanning = false
                    connect(text)
                }
                .ignoresSafeArea()
                .overlay(alignment: .topTrailing) {
                    Button("關閉") { scanning = false }
                        .buttonStyle(.borderedProminent)
                        .padding(Theme.screenMargin)
                }
            }
        }

        private var bridgeCard: some View {
            Card {
                CardBlock(divider: false) {
                    Note("在電腦上跑 ios/tools/claude-bridge（npm start），掃它印的 QR code。連上之後問古書都交給那台電腦的 Claude 回答。手機和電腦要連同一個 Wi-Fi，第一次會問區域網路權限，要按允許。")
                    if let bridge {
                        Text("現在連的：\(bridge.masked)")
                        Button("中斷連線") {
                            ClaudeBridge.disconnect()
                            self.bridge = nil
                            bridgeFailed = false
                            bridgeNote = "跟電腦斷開了。"
                        }
                        .buttonStyle(.ghost)
                    }
                    if QRScanner.isSupported {
                        Button("掃 QR code", action: scan).buttonStyle(.ghost).disabled(checking)
                    } else {
                        Note("這支手機（或模擬器）不能掃，把電腦上印的網址貼在下面。")
                    }
                    TextField("http://192.168.…:8790/ask?t=…", text: $address)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(Theme.rowPadV)
                        .background(Theme.fill)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.fieldRadius))
                        .accessibilityLabel("電腦的網址")
                    Button(checking ? "連連看…" : "連線") { connect(address) }
                        .buttonStyle(.ghost)
                        .disabled(checking || address.isEmpty)
                    if let bridgeNote { Note(bridgeNote, warn: bridgeFailed) }
                }
            }
        }

        private func scan() {
            Task { @MainActor in
                if await QRScanner.prepare() {
                    scanning = true
                } else {
                    bridgeFailed = true
                    bridgeNote = "相機沒有開。到 iPhone 的設定把瓜相的相機打開，或把網址貼在下面。"
                }
            }
        }

        private func connect(_ raw: String) {
            guard let found = ClaudeBridge(raw) else {
                bridgeFailed = true
                bridgeNote = "這不是轉接程式的網址。要長得像 http://192.168.x.x:8790/ask?t=一串英數字。"
                return
            }
            checking = true
            bridgeNote = nil
            Task { @MainActor in
                do {
                    let name = try await found.ping()
                    found.save()
                    bridge = found
                    address = ""
                    bridgeFailed = false
                    bridgeNote = "連上「\(name)」了。"
                } catch {
                    bridgeFailed = true
                    bridgeNote = error.localizedDescription
                }
                checking = false
            }
        }
    }
#endif
