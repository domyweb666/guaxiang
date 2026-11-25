import SwiftUI

/// 標題旁邊的小圓鈕。點了從下方彈出古書原文
struct InfoButton: View {
    /// 這顆在講哪一項，旁白會唸
    let subject: String
    /// 點開才組內容
    let note: () -> BookNote?
    @State private var open = false

    var body: some View {
        Button {
            open = true
        } label: {
            Image(systemName: "info.circle")
                .font(.body)
                // 再大會超出 44 的框、凸出卡片
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundStyle(Theme.secondary)
                .frame(width: Theme.touch, height: Theme.touch)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        // 緊跟在標題後面，觸控範圍往外多一點，不把那一列撐高
        .padding(.horizontal, -Theme.item)
        .padding(.vertical, -Theme.group)
        .accessibilityLabel("看古書原文")
        .accessibilityValue(subject)
        .sheet(isPresented: $open) {
            if let content = note() { BookNoteSheet(note: content) }
        }
    }
}

/// 古書原文、白話、出處，其他都不放
struct BookNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    let note: BookNote

    var body: some View {
        NavigationStack {
            Page {
                book
            }
            .navigationTitle(note.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("關閉") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Theme.windowRadius)
        .presentationBackground(Theme.canvas)
    }

    @ViewBuilder private var book: some View {
        // 沒有逐字原文的不能叫原文
        SectionTitle(note.quotes.isEmpty ? "古書怎麼說" : "古書原文")
        Card {
            ForEach(Array(note.quotes.enumerated()), id: \.offset) { i, quote in
                CardBlock(divider: i > 0) {
                    paragraph(quote.text, font: Theme.quote)
                    paragraph(quote.plain, font: .body)
                }
            }
            if let plain = note.plain {
                CardBlock(divider: !note.quotes.isEmpty) { paragraph(plain, font: .body) }
            }
            if let source = note.source {
                CardBlock { Note(source) }
            }
        }
    }

    private func paragraph(_ text: String, font: Font) -> some View {
        Text(text)
            .font(font)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
