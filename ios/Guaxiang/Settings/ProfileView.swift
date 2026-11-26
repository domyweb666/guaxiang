import SwiftUI

/// 關於你：全部選填，改了自動存。只用來挑跟使用者有關的古書條文
struct ProfileView: View {
    @State private var profile = Storage.shared.load(Profile.self, from: .profile) ?? Profile()
    @State private var pickingBirthday = false
    @State private var draft = Date()
    @State private var birthdayError: String?
    @State private var confirmClear = false

    var body: some View {
        Page {
            PageTitle(
                title: "關於你", lead: "全部選填，改了自動存。這些只用來挑跟你有關的古書條文，不會說成是從臉上看出來的。",
                pushed: true)
            Card {
                CardBlock(divider: false) {
                    Text("怎麼稱呼").font(.headline)
                    field("例如 小美", $profile.name, limit: Prompt.Limits.short)
                    Note("為什麼問：回答開頭叫你一聲，其他地方不會用。")
                }
                CardBlock { birthday }
                CardBlock {
                    single("性別", ["男", "女"], $profile.gender, "為什麼問：古書的流年男生從左邊算、女生從右邊算，婚姻那一項用詞也不同。")
                }
            }

            SectionTitle("家人和感情")
            Card {
                CardBlock(divider: false) {
                    single(
                        "感情狀態", ["單身", "交往中", "已婚", "分居或離婚", "喪偶"], $profile.relation,
                        "為什麼問：古書感情那一項原本是寫給已婚的人，照你的狀況換說法。")
                }
                CardBlock {
                    single("孩子", ["沒有", "有"], $profile.kids, "為什麼問：古書有子女這一項，決定要不要講到。")
                }
                CardBlock {
                    single("兄弟姊妹", ["獨生", "有"], $profile.siblings, "為什麼問：古書有兄弟朋友這一項，獨生的話只講朋友。")
                }
            }

            SectionTitle("工作")
            Card {
                CardBlock(divider: false) {
                    single(
                        "工作狀態", ["上班族", "自己創業或接案", "學生", "家管", "退休", "待業", "其他"], $profile.work,
                        "為什麼問：古書的工作、團隊兩項，要照你的狀況講才聽得懂。")
                }
                CardBlock {
                    Text("做哪一行").font(.headline)
                    field("例如 餐飲、軟體", $profile.field, limit: Prompt.Limits.short)
                    Note("為什麼問：問工作的時候，用你那一行聽得懂的講法。")
                }
            }

            SectionTitle("想問的事")
            Card {
                CardBlock(divider: false) {
                    multiple(
                        "最想問哪方面", ["錢財", "工作", "感情", "家人", "朋友", "搬家出國", "整體"], $profile.topics,
                        "為什麼問：問古書的建議問題，會先放這幾項。")
                }
                CardBlock {
                    multiple(
                        "最近正在面對的事", ["換工作", "創業", "考試", "結婚", "搬家", "沒有特別的"], $profile.events,
                        "為什麼問：挑條文的時候，先看跟這件事有關的。決定還是要你自己做。")
                }
                CardBlock {
                    Text("想多說一點").font(.headline)
                    field("最近在煩惱什麼", $profile.intro, limit: Prompt.Limits.intro, lines: 3...8)
                    Note("為什麼問：你說得越清楚，越挑得到相關的條文。最多 400 字。")
                }
            }

            SectionTitle("臉和回答")
            Card {
                CardBlock(divider: false) {
                    multiple(
                        "臉上動過或最近有變化的", ["牙齒矯正", "嘴唇動過", "明顯疤痕"], $profile.faceChanges,
                        "為什麼問：這附近量到的可能受影響，回答會提醒你。眉毛和鼻子在掃描前已經問過。")
                }
                CardBlock {
                    Text("回答要短還是一般").font(.headline)
                    Picker("回答要短還是一般", selection: $profile.answerLength) {
                        Text("一般").tag("")
                        Text("短").tag("短")
                    }
                    .pickerStyle(.segmented)
                    Note("為什麼問：短的 100 字以內，一般 250 字以內。")
                }
            }

            Note("不問生辰八字和時辰、姓名筆畫、血型、星座，因為這個 app 只看臉。簡介只存在這支手機，問古書的時候才會用文字送出去，生日不送，只送年紀。")
                .padding(.horizontal, Theme.tight)
            if !profile.isEmpty {
                Button("清除簡介") { confirmClear = true }.buttonStyle(.ghost)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: profile) { _, value in save(value) }
        .alert("要清除簡介嗎？", isPresented: $confirmClear) {
            Button("清除", role: .destructive) {
                profile = Profile()
                pickingBirthday = false
                birthdayError = nil
            }
            Button("先不用", role: .cancel) {}
        } message: {
            Text("這一頁填的會全部清掉，救不回來。報告和問答還在。")
        }
    }

    private func save(_ value: Profile) {
        if value.isEmpty {
            Storage.shared.remove(.profile)
        } else {
            Storage.shared.save(value, to: .profile)
        }
    }

    // MARK: 生日

    @ViewBuilder private var birthday: some View {
        Text("生日").font(.headline)
        if pickingBirthday {
            DatePicker("生日", selection: $draft, in: range, displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .environment(\.calendar, Birthday.gregorian)
                .frame(maxWidth: .infinity)
                .frame(height: Theme.wheelHeight)
                .clipped()
            Button("就是這一天", action: keepBirthday).buttonStyle(.ghost)
            Button("取消") { pickingBirthday = false }.buttonStyle(.textOnly)
        } else if let b = profile.birthday {
            Text("\(String(b.year)) 年 \(b.month) 月 \(b.day) 日" + ageText)
            HStack(spacing: Theme.section) {
                Button("修改") { openBirthday(b.date) }
                Button("拿掉", role: .destructive) { profile.birthday = nil }
            }
            .buttonStyle(.borderless)
            .frame(minHeight: Theme.touch)
        } else {
            if let age = profile.age { Text("之前填的是 \(age) 歲。填了生日，年紀每年會自己變。") }
            Button("填生日") { openBirthday(nil) }.buttonStyle(.ghost)
            if profile.age != nil {
                Button("拿掉之前填的年紀") { profile.age = nil }.buttonStyle(.textOnly)
            }
        }
        if let birthdayError { Note(birthdayError, warn: true) }
        Note("為什麼問：古書的流年是一歲看一個部位，要知道你今年幾歲。未滿 18 歲的不收。")
    }

    private var ageText: String {
        profile.currentAge().map { "・\($0) 歲" } ?? ""
    }

    private var range: ClosedRange<Date> {
        let calendar = Birthday.gregorian
        let now = Date()
        let latest = calendar.date(byAdding: .year, value: -Profile.ages.lowerBound, to: now) ?? now
        let earliest = calendar.date(byAdding: .year, value: -Profile.ages.upperBound, to: now) ?? latest
        return min(earliest, latest)...latest
    }

    private func openBirthday(_ date: Date?) {
        let start = Birthday(year: 1995, month: 1, day: 1).date ?? range.upperBound
        draft = min(max(date ?? start, range.lowerBound), range.upperBound)
        birthdayError = nil
        pickingBirthday = true
    }

    private func keepBirthday() {
        let picked = Birthday(draft)
        guard picked.isAccepted(on: Date()) else {
            birthdayError = "這個工具只給滿 18 歲的人使用，這個生日沒有存。"
            return
        }
        profile.birthday = picked
        profile.age = nil
        birthdayError = nil
        pickingBirthday = false
    }

    // MARK: 欄位

    private func field(
        _ prompt: String, _ text: Binding<String>, limit: Int, lines: ClosedRange<Int> = 1...2
    ) -> some View {
        TextField(prompt, text: text, axis: .vertical)
            .lineLimit(lines)
            .padding(Theme.rowPadV)
            .background(Theme.fill)
            .clipShape(RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous))
            .onChange(of: text.wrappedValue) { _, value in
                // 只按了換行或空白：當成沒填，提示字才會回來
                if !value.isEmpty, value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    text.wrappedValue = ""
                    return
                }
                let clipped = Prompt.clip(value, limit)
                if clipped != value { text.wrappedValue = clipped }
            }
    }

    private func single(_ title: String, _ options: [String], _ value: Binding<String>, _ why: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.item) {
            Text(title).font(.headline)
            Picker(title, selection: value) {
                Text("不想說").tag("")
                ForEach(options, id: \.self) { Text($0).tag($0) }
                // 舊版存過、現在沒有的選項，留著不動
                if !value.wrappedValue.isEmpty, !options.contains(value.wrappedValue) {
                    Text(value.wrappedValue).tag(value.wrappedValue)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(minHeight: Theme.touch)
            Note(why)
        }
    }

    private func multiple(_ title: String, _ options: [String], _ value: Binding<[String]>, _ why: String)
        -> some View
    {
        VStack(alignment: .leading, spacing: Theme.item) {
            Text(title).font(.headline)
            FlowLayout(spacing: Theme.item) {
                ForEach(options, id: \.self) { option in
                    let on = value.wrappedValue.contains(option)
                    Button {
                        toggle(option, value, options)
                    } label: {
                        Text(option)
                            .font(.subheadline.weight(on ? .semibold : .regular))
                            .foregroundStyle(on ? Theme.onAccent : Color.primary)
                            .padding(.horizontal, Theme.cardPad)
                            .frame(minHeight: Theme.touch)
                            .background(on ? Theme.accent : Theme.fill)
                            .clipShape(Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Note(why)
        }
    }

    /// 「沒有特別的」跟其他選項不會同時選到
    private func toggle(_ option: String, _ value: Binding<[String]>, _ options: [String]) {
        let none = "沒有特別的"
        var picked = value.wrappedValue
        if let i = picked.firstIndex(of: option) {
            picked.remove(at: i)
        } else if option == none {
            picked = [none]
        } else {
            picked.removeAll { $0 == none }
            picked.append(option)
        }
        value.wrappedValue = options.filter { picked.contains($0) }
    }
}
