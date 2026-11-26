import Foundation

/// 生日只存在手機裡。送給 AI 的只有算出來的年紀
struct Birthday: Codable, Equatable {
    var year: Int
    var month: Int
    var day: Int

    /// 不管手機設成國曆、民國還是農曆，都用西元算
    static let gregorian = Calendar(identifier: .gregorian)

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(_ date: Date, calendar: Calendar = Birthday.gregorian) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 2000, month: c.month ?? 1, day: c.day ?? 1)
    }

    var date: Date? {
        Self.gregorian.date(from: DateComponents(year: year, month: month, day: day))
    }

    /// 實歲
    func age(on now: Date, calendar: Calendar = Birthday.gregorian) -> Int {
        let today = calendar.dateComponents([.year, .month, .day], from: now)
        let y = today.year ?? year, m = today.month ?? month, d = today.day ?? day
        let passed = (m, d) >= (month, day)
        return y - year - (passed ? 0 : 1)
    }

    /// 未滿 18 歲、或明顯打錯的不收
    func isAccepted(on now: Date, calendar: Calendar = Birthday.gregorian) -> Bool {
        Profile.ages.contains(age(on: now, calendar: calendar))
    }
}

/// 使用者填的簡介，全部選填，只存在手機裡；提問時以文字送出（第一次要先同意）。
/// 只用來挑跟他有關的古書條文，不會說成是從臉上看出來的
struct Profile: Codable, Equatable {
    static let ages = 18...120

    /// 舊版手填的年紀。填了生日就不再用這一格
    var age: Int?
    var gender = ""
    var relation = ""
    var work = ""
    var intro = ""
    var name = ""
    var birthday: Birthday?
    var kids = ""
    var siblings = ""
    var field = ""
    var topics: [String] = []
    var events: [String] = []
    /// 眉毛和鼻子在掃描前已經問過（Answers），這裡不重複
    var faceChanges: [String] = []
    var answerLength = ""

    enum CodingKeys: String, CodingKey {
        case age, gender, relation, work, intro, name, birthday, kids, siblings, field, topics, events, faceChanges
        case answerLength
    }

    var isEmpty: Bool { self == Profile() }

    /// 填了幾欄，給設定頁那一列看
    var filledCount: Int {
        let texts = [gender, relation, work, name, kids, siblings, field, answerLength]
        let lists = [faceChanges]
        let hasAge = birthday != nil || age != nil
        return texts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count + lists.filter { !$0.isEmpty }.count + (hasAge ? 1 : 0)
    }

    /// 現在幾歲。有生日照生日算，沒有就用舊版手填的；不在 18–120 歲就當沒填
    func currentAge(on now: Date = Date()) -> Int? {
        guard let years = birthday?.age(on: now) ?? age, Self.ages.contains(years) else { return nil }
        return years
    }

    /// 問古書用的那一份：年紀換成現在的，生日拿掉
    func forAsk(on now: Date = Date()) -> Profile {
        var out = self
        out.age = currentAge(on: now)
        // 「想問的事」那一區拿掉了（多米 11/26）。舊版填過的看不到也改不了，不再送出去
        out.topics = []
        out.events = []
        out.intro = ""
        out.birthday = nil
        return out
    }
}

extension Profile {
    /// 舊版的檔案沒有新欄位，缺的一律當沒填
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        age = try c.decodeIfPresent(Int.self, forKey: .age)
        gender = try c.decodeIfPresent(String.self, forKey: .gender) ?? ""
        relation = try c.decodeIfPresent(String.self, forKey: .relation) ?? ""
        work = try c.decodeIfPresent(String.self, forKey: .work) ?? ""
        intro = try c.decodeIfPresent(String.self, forKey: .intro) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        birthday = try c.decodeIfPresent(Birthday.self, forKey: .birthday)
        kids = try c.decodeIfPresent(String.self, forKey: .kids) ?? ""
        siblings = try c.decodeIfPresent(String.self, forKey: .siblings) ?? ""
        field = try c.decodeIfPresent(String.self, forKey: .field) ?? ""
        topics = try c.decodeIfPresent([String].self, forKey: .topics) ?? []
        events = try c.decodeIfPresent([String].self, forKey: .events) ?? []
        faceChanges = try c.decodeIfPresent([String].self, forKey: .faceChanges) ?? []
        answerLength = try c.decodeIfPresent(String.self, forKey: .answerLength) ?? ""
    }
}

/// 送出去的那一份。這裡沒有生日這個欄位，不會不小心帶出去
struct ProfileWire: Encodable {
    let age: Int?
    let gender: String
    let relation: String
    let work: String
    let intro: String
    let name: String
    let kids: String
    let siblings: String
    let field: String
    let topics: [String]
    let events: [String]
    let faceChanges: [String]
    let answerLength: String

    init(_ p: Profile, on now: Date = Date()) {
        age = p.currentAge(on: now)
        gender = p.gender
        relation = p.relation
        work = p.work
        intro = p.intro
        name = p.name
        kids = p.kids
        siblings = p.siblings
        field = p.field
        topics = p.topics
        events = p.events
        faceChanges = p.faceChanges
        answerLength = p.answerLength
    }
}
