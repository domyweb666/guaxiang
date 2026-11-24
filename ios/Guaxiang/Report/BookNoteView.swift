import SwiftUI

/// 白話旁邊的小圓鈕。點了從下方彈出原文和估算方式
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
        // 圖示對齊卡片的右邊，觸控範圍往外多一點
        .padding(.trailing, -Theme.group)
        .accessibilityLabel("看原文和估算方式")
        .accessibilityValue(subject)
        .sheet(isPresented: $open) {
            if let content = note() { BookNoteSheet(note: content) }
        }
    }
}

/// 一段白話，右邊一顆小圓鈕
struct PlainLine<Content: View>: View {
    let subject: String
    let note: () -> BookNote?
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .center, spacing: Theme.item) {
            VStack(alignment: .leading, spacing: Theme.tight) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
            InfoButton(subject: subject, note: note)
        }
    }
}

struct BookNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    let note: BookNote

    var body: some View {
        NavigationStack {
            Page {
                book
                if !note.estimates.isEmpty || !note.remarks.isEmpty {
                    SectionTitle("怎麼估的")
                    estimates
                }
                if !note.cannot.isEmpty {
                    SectionTitle("還有什麼量不到")
                    cannot
                }
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

    // MARK: 古書

    @ViewBuilder private var book: some View {
        SectionTitle("古書原文")
        Card {
            ForEach(Array(note.quotes.enumerated()), id: \.offset) { i, quote in
                CardBlock(divider: i > 0) {
                    paragraph(quote.text, font: Theme.quote)
                    labeled("白話", quote.plain)
                }
            }
            if note.noQuote != nil || note.plain != nil {
                CardBlock(divider: !note.quotes.isEmpty) {
                    if let why = note.noQuote { Note(why) }
                    if let plain = note.plain { paragraph(plain, font: .body) }
                }
            }
            if note.source != nil || note.literature != nil || !note.terms.isEmpty {
                CardBlock { facts }
            }
        }
    }

    @ViewBuilder private var facts: some View {
        if let source = note.source { labeled("出處", source) }
        if !note.terms.isEmpty { labeled("古書的叫法", note.terms.joined(separator: "\n")) }
        if let literature = note.literature { labeled("有幾本書這樣說", literature) }
    }

    // MARK: 怎麼估的

    private var estimates: some View {
        Card {
            ForEach(Array(note.estimates.enumerated()), id: \.offset) { i, e in
                CardBlock(divider: i > 0) {
                    paragraph(e.name, font: .subheadline.weight(.semibold))
                    paragraph(e.method, font: .subheadline)
                    ForEach(e.numbers, id: \.self) { Note($0) }
                    ForEach(e.warnings, id: \.self) { Note($0, warn: true) }
                }
            }
            if !note.remarks.isEmpty {
                CardBlock(divider: !note.estimates.isEmpty) {
                    ForEach(note.remarks, id: \.self) { paragraph($0, font: .subheadline) }
                }
            }
        }
    }

    // MARK: 量不到的

    private var cannot: some View {
        Card {
            CardBlock(divider: false) {
                ForEach(note.cannot, id: \.self) { paragraph($0, font: .subheadline) }
            }
        }
    }

    private func labeled(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.tight / 2) {
            Note(label)
            paragraph(text, font: .subheadline)
        }
        .accessibilityElement(children: .combine)
    }

    private func paragraph(_ text: String, font: Font) -> some View {
        Text(text)
            .font(font)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
