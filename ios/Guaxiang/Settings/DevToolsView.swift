#if DEVTOOLS
    import SwiftUI

    /// 開發工具。只在編譯時有開 DEVTOOLS 的版本裡出現，上架前整區拿掉。
    struct DevToolsView: View {
        @EnvironmentObject private var model: AppModel
        @Environment(\.dismiss) private var dismiss
        @State private var key = ""
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
        }
    }
#endif
