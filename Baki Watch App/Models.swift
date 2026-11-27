import Foundation

struct Subject: Codable, Identifiable {
    let id: String
    let abbrev: String
    let name: String

    var displayName: String { abbrev.isEmpty ? name : abbrev }

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case abbrev = "Abbrev"
        case name = "Name"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.abbrev = (try? container.decode(String.self, forKey: .abbrev))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.name = (try? container.decode(String.self, forKey: .name))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

struct Teacher: Codable, Identifiable {
    let id: String
    let abbrev: String
    let name: String

    var displayName: String { name.isEmpty ? abbrev : name }

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case abbrev = "Abbrev"
        case name = "Name"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.abbrev = (try? container.decode(String.self, forKey: .abbrev))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.name = (try? container.decode(String.self, forKey: .name))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

struct Room: Codable, Identifiable {
    let id: String
    let abbrev: String
    let name: String

    var displayName: String { abbrev.isEmpty ? name : abbrev }

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case abbrev = "Abbrev"
        case name = "Name"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.abbrev = (try? container.decode(String.self, forKey: .abbrev))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.name = (try? container.decode(String.self, forKey: .name))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

struct TimetableResponse: Codable {
    let hours: [Hour]
    let days: [Day]
    let subjects: [Subject]?
    let teachers: [Teacher]?
    let rooms: [Room]?

    private let hoursById: [Int: Hour]
    private let subjectsById: [String: Subject]
    private let teachersById: [String: Teacher]
    private let roomsById: [String: Room]

    func hour(id: Int) -> Hour? { hoursById[id] }
    func subject(id: String?) -> Subject? { id.flatMap { subjectsById[$0] } }
    func teacher(id: String?) -> Teacher? { id.flatMap { teachersById[$0] } }
    func room(id: String?) -> Room? { id.flatMap { roomsById[$0] } }

    enum CodingKeys: String, CodingKey {
        case hours = "Hours"
        case days = "Days"
        case subjects = "Subjects"
        case teachers = "Teachers"
        case rooms = "Rooms"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hours = try container.decode([Hour].self, forKey: .hours)
        days = try container.decode([Day].self, forKey: .days)
        subjects = try container.decodeIfPresent([Subject].self, forKey: .subjects)
        teachers = try container.decodeIfPresent([Teacher].self, forKey: .teachers)
        rooms = try container.decodeIfPresent([Room].self, forKey: .rooms)

        hoursById = Self.index(hours, by: \.id)
        subjectsById = Self.index(subjects ?? [], by: \.id)
        teachersById = Self.index(teachers ?? [], by: \.id)
        roomsById = Self.index(rooms ?? [], by: \.id)
    }

    private static func index<T, Key: Hashable>(_ items: [T], by key: KeyPath<T, Key>) -> [Key: T] {
        Dictionary(items.map { ($0[keyPath: key], $0) }, uniquingKeysWith: { first, _ in first })
    }
}

struct Hour: Codable, Identifiable {
    let id: Int
    let caption: String
    let beginTime: String
    let endTime: String

    func dates(on baseDate: Date) -> (start: Date, end: Date)? {
        let beg = beginTime.split(separator: ":")
        let end = endTime.split(separator: ":")
        guard beg.count >= 2, end.count >= 2,
              let bH = Int(beg[0]), let bM = Int(beg[1]),
              let eH = Int(end[0]), let eM = Int(end[1]),
              let s = Calendar.current.date(bySettingHour: bH, minute: bM, second: 0, of: baseDate),
              let e = Calendar.current.date(bySettingHour: eH, minute: eM, second: 0, of: baseDate) else {
            return nil
        }
        return (s, e)
    }

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case caption = "Caption"
        case beginTime = "BeginTime"
        case endTime = "EndTime"
    }
}

struct Day: Codable, Identifiable {
    var id: String { date }
    let atoms: [Atom]
    let dayOfWeek: Int
    let date: String
    let dayDescription: String?
    let dayType: String?

    enum CodingKeys: String, CodingKey {
        case atoms = "Atoms"
        case dayOfWeek = "DayOfWeek"
        case date = "Date"
        case dayDescription = "DayDescription"
        case dayType = "DayType"
    }
}

struct Atom: Codable, Identifiable {
    var id: String {
        "\(hourId)_\(subjectId ?? "")_\(teacherId ?? "")_\(roomId ?? "")_\(theme ?? "")_\(change?.changeType ?? "")_\(change?.description ?? "")"
    }
    let hourId: Int
    let subjectId: String?
    let teacherId: String?
    let roomId: String?
    let theme: String?
    let notice: String?
    let change: Change?

    var isCancelled: Bool { change?.isCancelled == true }

    enum CodingKeys: String, CodingKey {
        case hourId = "HourId"
        case subjectId = "SubjectId"
        case teacherId = "TeacherId"
        case roomId = "RoomId"
        case theme = "Theme"
        case notice = "Notice"
        case change = "Change"
    }
}

struct Change: Codable {
    let changeType: String?
    let description: String?
    let time: String?
    let typeName: String?
    let typeAbbrev: String?

    var displayDescription: String {
        description ?? typeName ?? changeType ?? "Změna výuky"
    }

    var isCancelled: Bool {
        description?.localizedCaseInsensitiveContains("odpad") == true ||
        changeType?.localizedCaseInsensitiveContains("odpad") == true ||
        typeName?.localizedCaseInsensitiveContains("odpad") == true
    }

    enum CodingKeys: String, CodingKey {
        case changeType = "ChangeType"
        case description = "Description"
        case time = "Time"
        case typeName = "TypeName"
        case typeAbbrev = "TypeAbbrev"
    }
}

struct MarksResponse: Codable {
    let subjects: [SubjectMarks]

    enum CodingKeys: String, CodingKey {
        case subjects = "Subjects"
    }
}

struct SubjectMarks: Codable, Identifiable {
    var id: String { subject.id }
    let marks: [Mark]
    let subject: Subject
    let averageText: String?
    let subjectNote: String?
    let temporaryMarkNote: String?
    let pointsOnly: Bool?
    let markPredictionEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case marks = "Marks"
        case subject = "Subject"
        case averageText = "AverageText"
        case subjectNote = "SubjectNote"
        case temporaryMarkNote = "TemporaryMarkNote"
        case pointsOnly = "PointsOnly"
        case markPredictionEnabled = "MarkPredictionEnabled"
    }
}

struct Mark: Codable, Identifiable {
    let id: String
    let markDate: String?
    let caption: String?
    let theme: String?
    let markText: String?
    let type: String?
    let typeNote: String?
    let weight: Int?
    let subjectId: String?
    let isNew: Bool?
    let calculatedMarkText: String?
    let classRankText: String?
    let teacherId: String?
    let editDate: String?

    var displayText: String { markText ?? "" }

    var parsedDate: Date? {
        BakiDate.parse(markDate)
    }

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case markDate = "MarkDate"
        case caption = "Caption"
        case theme = "Theme"
        case markText = "MarkText"
        case type = "Type"
        case typeNote = "TypeNote"
        case weight = "Weight"
        case subjectId = "SubjectId"
        case isNew = "IsNew"
        case calculatedMarkText = "CalculatedMarkText"
        case classRankText = "ClassRankText"
        case teacherId = "TeacherId"
        case editDate = "EditDate"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.markDate = try? container.decodeIfPresent(String.self, forKey: .markDate)
        self.caption = try? container.decodeIfPresent(String.self, forKey: .caption)
        self.theme = try? container.decodeIfPresent(String.self, forKey: .theme)
        self.markText = try? container.decodeIfPresent(String.self, forKey: .markText)
        self.type = try? container.decodeIfPresent(String.self, forKey: .type)
        self.typeNote = try? container.decodeIfPresent(String.self, forKey: .typeNote)
        if let intWeight = try? container.decodeIfPresent(Int.self, forKey: .weight) {
            self.weight = intWeight
        } else if let doubleWeight = try? container.decodeIfPresent(Double.self, forKey: .weight) {
            self.weight = Int(doubleWeight)
        } else {
            self.weight = nil
        }
        self.subjectId = try? container.decodeIfPresent(String.self, forKey: .subjectId)
        self.isNew = try? container.decodeIfPresent(Bool.self, forKey: .isNew)
        self.calculatedMarkText = try? container.decodeIfPresent(String.self, forKey: .calculatedMarkText)
        self.classRankText = try? container.decodeIfPresent(String.self, forKey: .classRankText)
        self.teacherId = try? container.decodeIfPresent(String.self, forKey: .teacherId)
        self.editDate = try? container.decodeIfPresent(String.self, forKey: .editDate)
    }
}

struct KomensResponse: Codable {
    let messages: [KomensMessage]?

    enum CodingKeys: String, CodingKey {
        case messages = "Messages"
    }
}

struct KomensMessage: Codable, Identifiable {
    let id: String
    let title: String?
    let text: String?
    let sentDate: String?
    let dateFrom: String?
    var read: Bool?
    let sender: KomensSender?
    let relevantName: String?
    let canConfirm: Bool?
    let confirmed: Bool?
    let lifeTime: String?

    var awaitsConfirmation: Bool {
        (canConfirm == true && confirmed != true) || lifeTime?.caseInsensitiveCompare("ToConfirm") == .orderedSame && confirmed != true
    }

    var isUnread: Bool {
        read == false
    }

    var plainText: String {
        cleanHTML(text ?? "")
    }

    var effectiveDateString: String? {
        sentDate ?? dateFrom
    }

    var parsedDate: Date? {
        BakiDate.parse(effectiveDateString)
    }

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case title = "Title"
        case text = "Text"
        case sentDate = "SentDate"
        case dateFrom = "DateFrom"
        case read = "Read"
        case sender = "Sender"
        case relevantName = "RelevantName"
        case canConfirm = "CanConfirm"
        case confirmed = "Confirmed"
        case lifeTime = "LifeTime"
    }
}

struct KomensSender: Codable, Identifiable {
    let id: String
    let type: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case type = "Type"
        case name = "Name"
    }
}

struct KomensAttachment: Codable, Identifiable {
    let id: String
    let name: String?
    let type: String?
    let size: Int?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case type = "Type"
        case size = "Size"
    }
}

struct HomeworksResponse: Decodable {
    let homeworks: [Homework]?

    enum CodingKeys: String, CodingKey {
        case homeworks = "Homeworks"
    }
}

struct Homework: Decodable, Identifiable {
    let id: String
    let dateStart: String?
    let dateEnd: String?
    let content: String?
    let notice: String?
    var done: Bool?
    let closed: Bool?
    let electronic: Bool?
    let hour: Int?
    let schoolClass: HomeworkRef?
    let group: HomeworkRef?
    let subject: HomeworkRef?
    let teacher: HomeworkRef?
    let attachments: [KomensAttachment]?
    let finished: Bool?

    var startDate: Date? { BakiDate.parse(dateStart) }
    var dueDate: Date? { BakiDate.parse(dateEnd) }
    var isDone: Bool { done == true }
    var isClosed: Bool { closed == true }

    var subjectName: String {
        let name = subject?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty { return name }
        let abbrev = subject?.abbrev?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return abbrev.isEmpty ? "Úkol" : abbrev
    }

    var contentText: String {
        let raw = (content ?? "").replacingOccurrences(of: "\\n", with: "\n")
        return cleanHTML(raw)
    }

    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case dateStart = "DateStart"
        case dateEnd = "DateEnd"
        case content = "Content"
        case notice = "Notice"
        case done = "Done"
        case closed = "Closed"
        case electronic = "Electronic"
        case hour = "Hour"
        case schoolClass = "Class"
        case group = "Group"
        case subject = "Subject"
        case teacher = "Teacher"
        case attachments = "Attachments"
        case finished = "Finished"
    }
}

struct HomeworkRef: Decodable {
    let id: String?
    let abbrev: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case abbrev = "Abbrev"
        case name = "Name"
    }
}
