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
    let attachments: [KomensAttachment]?
    let canConfirm: Bool?
    let canAnswer: Bool?
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
        case attachments = "Attachments"
        case canConfirm = "CanConfirm"
        case canAnswer = "CanAnswer"
        case confirmed = "Confirmed"
        case lifeTime = "LifeTime"
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

struct KomensMessageTypesResponse: Decodable {
    let messageTypes: [KomensMessageTypeOption]
    let recipients: [KomensRecipient]?

    enum CodingKeys: String, CodingKey {
        case messageTypes = "MessageTypes"
        case recipients = "Recipients"
    }
}

struct KomensMessageTypeOption: Decodable, Identifiable, Hashable {
    var id: String { abbreviation }
    let abbreviation: String
    let name: String
    let showEmailNotification: Bool?
    let hasTitle: Bool?
    let recipientsTypes: [KomensRecipientType]
    let superType: String?
    let showConfirmation: Bool?

    enum CodingKeys: String, CodingKey {
        case abbreviation = "Abbreviation"
        case name = "Name"
        case showEmailNotification = "ShowEmailNotification"
        case hasTitle = "HasTitle"
        case recipientsTypes = "RecipientsTypes"
        case superType = "SuperType"
        case showConfirmation = "ShowConfirmation"
    }
}

struct KomensRecipientType: Decodable, Identifiable, Hashable {
    var id: String { code }
    let code: String
    let name: String
    let showCopyForClassTeacher: Bool?
    let showCopyForDirector: Bool?
    let showCopyForParent: Bool?
    let typeOfSelection: String?
    let recipients: [KomensRecipient]

    enum CodingKeys: String, CodingKey {
        case code = "Code"
        case name = "Name"
        case showCopyForClassTeacher = "ShowCopyForClassTeacher"
        case showCopyForDirector = "ShowCopyForDirector"
        case showCopyForParent = "ShowCopyForParent"
        case typeOfSelection = "TypeOfSelection"
        case recipients = "Recipients"
    }

    enum Selection {
        case none, single, multiple
    }

    var selection: Selection {
        switch typeOfSelection?.uppercased() {
        case "ZERO": return .none
        case "ONE": return .single
        default: return .multiple
        }
    }
}

struct KomensRecipient: Decodable, Identifiable, Hashable {
    var id: String { code }
    let code: String
    let isDefault: Bool?
    let abbreviation: String?
    let displayName: String?
    let name: String?

    var title: String {
        let display = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !display.isEmpty { return display }
        let name = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? code : name
    }

    enum CodingKeys: String, CodingKey {
        case code = "Code"
        case isDefault = "IsDefault"
        case abbreviation = "Abbreviation"
        case displayName = "DisplayName"
        case name = "Name"
    }
}

struct NewKomensMessage: Encodable {
    var messageType: String
    var title: String
    var text: String
    var recipientType: String
    var recipients: [String]
    var dateFrom: String? = nil
    var dateTo: String? = nil
    var previousMessageId: String? = nil
    var copyForClassTeacher = false
    var copyForParent = false
    var emailNotification = false
    var sendAsDirector = false
    var requireConfirmation = false

    enum CodingKeys: String, CodingKey {
        case messageType = "MessageType"
        case title = "Title"
        case text = "Text"
        case recipientType = "RecipientType"
        case recipients = "Recipients"
        case lifetime = "Lifetime"
        case dateFrom = "DateFrom"
        case dateTo = "DateTo"
        case previousMessageId = "PreviousMessageId"
        case copyForClassTeacher = "CopyForClassTeacher"
        case copyForParent = "CopyForParent"
        case emailNotification = "EmailNotification"
        case sendAsDirector = "SendAsDirector"
        case requireConfirmation = "RequireConfirmation"
        case typeOfRatingId = "TypeOfRatingId"
        case scale = "Scale"
        case attachments = "Attachments"
        case draftDate = "DraftDate"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(messageType, forKey: .messageType)
        try container.encode(title, forKey: .title)
        try container.encode(text, forKey: .text)
        try container.encode(recipientType, forKey: .recipientType)
        try container.encode(recipients, forKey: .recipients)
        try container.encodeNil(forKey: .lifetime)
        try container.encode(dateFrom, forKey: .dateFrom)
        try container.encode(dateTo, forKey: .dateTo)
        try container.encode(previousMessageId, forKey: .previousMessageId)
        try container.encode(copyForClassTeacher, forKey: .copyForClassTeacher)
        try container.encode(copyForParent, forKey: .copyForParent)
        try container.encode(emailNotification, forKey: .emailNotification)
        try container.encode(sendAsDirector, forKey: .sendAsDirector)
        try container.encode(requireConfirmation, forKey: .requireConfirmation)
        try container.encodeNil(forKey: .typeOfRatingId)
        try container.encodeNil(forKey: .scale)
        try container.encode([String](), forKey: .attachments)
        try container.encodeNil(forKey: .draftDate)
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

struct AbsenceResponse: Decodable {
    let percentageThreshold: Double?
    let absences: [AbsenceDay]?
    let absencesPerSubject: [SubjectAbsence]?

    enum CodingKeys: String, CodingKey {
        case percentageThreshold = "PercentageThreshold"
        case absences = "Absences"
        case absencesPerSubject = "AbsencesPerSubject"
    }
}

struct AbsenceDay: Decodable, Identifiable {
    var id: String { date }
    let date: String
    let unsolved: Int
    let ok: Int
    let missed: Int
    let late: Int
    let soon: Int
    let school: Int
    let distanceTeaching: Int

    var parsedDate: Date? { BakiDate.parse(date) }

    var isEmpty: Bool {
        unsolved + ok + missed + late + soon + school + distanceTeaching == 0
    }

    enum CodingKeys: String, CodingKey {
        case date = "Date"
        case unsolved = "Unsolved"
        case ok = "Ok"
        case missed = "Missed"
        case late = "Late"
        case soon = "Soon"
        case school = "School"
        case distanceTeaching = "DistanceTeaching"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(String.self, forKey: .date)
        unsolved = (try? c.decodeIfPresent(Int.self, forKey: .unsolved)) ?? 0
        ok = (try? c.decodeIfPresent(Int.self, forKey: .ok)) ?? 0
        missed = (try? c.decodeIfPresent(Int.self, forKey: .missed)) ?? 0
        late = (try? c.decodeIfPresent(Int.self, forKey: .late)) ?? 0
        soon = (try? c.decodeIfPresent(Int.self, forKey: .soon)) ?? 0
        school = (try? c.decodeIfPresent(Int.self, forKey: .school)) ?? 0
        distanceTeaching = (try? c.decodeIfPresent(Int.self, forKey: .distanceTeaching)) ?? 0
    }
}

struct SubjectAbsence: Decodable, Identifiable {
    let id = UUID()
    let subjectName: String
    let lessonsCount: Int
    let base: Int
    let late: Int
    let soon: Int
    let school: Int
    let distanceTeaching: Int

    var percentage: Double {
        lessonsCount > 0 ? Double(base) / Double(lessonsCount) : 0
    }

    enum CodingKeys: String, CodingKey {
        case subjectName = "SubjectName"
        case lessonsCount = "LessonsCount"
        case base = "Base"
        case late = "Late"
        case soon = "Soon"
        case school = "School"
        case distanceTeaching = "DistanceTeaching"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        subjectName = (try? c.decodeIfPresent(String.self, forKey: .subjectName)) ?? "Předmět"
        lessonsCount = (try? c.decodeIfPresent(Int.self, forKey: .lessonsCount)) ?? 0
        base = (try? c.decodeIfPresent(Int.self, forKey: .base)) ?? 0
        late = (try? c.decodeIfPresent(Int.self, forKey: .late)) ?? 0
        soon = (try? c.decodeIfPresent(Int.self, forKey: .soon)) ?? 0
        school = (try? c.decodeIfPresent(Int.self, forKey: .school)) ?? 0
        distanceTeaching = (try? c.decodeIfPresent(Int.self, forKey: .distanceTeaching)) ?? 0
    }
}

struct UserInfo: Decodable {
    let fullName: String?
    let schoolOrganizationName: String?
    let userType: String?
    let userTypeText: String?
    let schoolClass: HomeworkRef?
    let studyYear: Int?

    var schoolName: String? {
        let name = schoolOrganizationName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let placeholders = ["název školy", "nazev skoly"]
        return name.isEmpty || placeholders.contains(name.lowercased()) ? nil : name
    }

    var displayName: String {
        let full = fullName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return full.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? full
    }

    var className: String? {
        let name = (schoolClass?.abbrev ?? schoolClass?.name)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return name?.isEmpty == false ? name : nil
    }

    enum CodingKeys: String, CodingKey {
        case fullName = "FullName"
        case schoolOrganizationName = "SchoolOrganizationName"
        case userType = "UserType"
        case userTypeText = "UserTypeText"
        case schoolClass = "Class"
        case studyYear = "StudyYear"
    }
}

struct FinalMarksResponse: Decodable {
    let certificateTerms: [CertificateTerm]

    enum CodingKeys: String, CodingKey {
        case certificateTerms = "CertificateTerms"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.certificateTerms = (try? container.decode([CertificateTerm].self, forKey: .certificateTerms)) ?? []
    }
}

struct CertificateTerm: Decodable, Identifiable {
    var id: String { "\(schoolYear)_\(semester)_\(grade ?? 0)" }

    let finalMarks: [FinalMark]
    let subjects: [Subject]
    let gradeName: String?
    let grade: Int?
    let yearInSchool: Int?
    let schoolYear: String
    let semester: String
    let semesterName: String?
    let repeated: Bool?
    let closed: Bool?
    let achievementText: String?
    let marksAverage: Double?
    let absentHours: Int?
    let notExcusedHours: Int?
    let certificateDate: String?

    enum CodingKeys: String, CodingKey {
        case finalMarks = "FinalMarks"
        case subjects = "Subjects"
        case gradeName = "GradeName"
        case grade = "Grade"
        case yearInSchool = "YearInSchool"
        case schoolYear = "SchoolYear"
        case semester = "Semester"
        case semesterName = "SemesterName"
        case repeated = "Repeated"
        case closed = "Closed"
        case achievementText = "AchievementText"
        case marksAverage = "MarksAverage"
        case absentHours = "AbsentHours"
        case notExcusedHours = "NotExcusedHours"
        case certificateDate = "CertificateDate"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.finalMarks = (try? container.decode([FinalMark].self, forKey: .finalMarks)) ?? []
        self.subjects = (try? container.decode([Subject].self, forKey: .subjects)) ?? []
        self.gradeName = try? container.decodeIfPresent(String.self, forKey: .gradeName)
        self.grade = try? container.decodeIfPresent(Int.self, forKey: .grade)
        self.yearInSchool = try? container.decodeIfPresent(Int.self, forKey: .yearInSchool)
        self.schoolYear = (try? container.decodeIfPresent(String.self, forKey: .schoolYear)) ?? ""
        self.semester = (try? container.decodeIfPresent(String.self, forKey: .semester)) ?? ""
        self.semesterName = try? container.decodeIfPresent(String.self, forKey: .semesterName)
        self.repeated = try? container.decodeIfPresent(Bool.self, forKey: .repeated)
        self.closed = try? container.decodeIfPresent(Bool.self, forKey: .closed)
        self.achievementText = try? container.decodeIfPresent(String.self, forKey: .achievementText)
        if let d = try? container.decodeIfPresent(Double.self, forKey: .marksAverage) {
            self.marksAverage = d
        } else if let s = try? container.decodeIfPresent(String.self, forKey: .marksAverage),
                  let d = Double(s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")) {
            self.marksAverage = d
        } else {
            self.marksAverage = nil
        }
        self.absentHours = try? container.decodeIfPresent(Int.self, forKey: .absentHours)
        self.notExcusedHours = try? container.decodeIfPresent(Int.self, forKey: .notExcusedHours)
        self.certificateDate = try? container.decodeIfPresent(String.self, forKey: .certificateDate)
    }

    var displayTitle: String {
        "\(schoolYear) · \(semesterTitle)"
    }

    var semesterTitle: String {
        let sem = semesterName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let semStr = (sem?.isEmpty == false) ? sem! : semester
        let termStr: String
        if semStr.localizedCaseInsensitiveContains("pol") {
            termStr = semStr
        } else if semStr.hasPrefix("1") {
            termStr = "1. pololetí"
        } else if semStr.hasPrefix("2") {
            termStr = "2. pololetí"
        } else {
            termStr = "\(semStr). pololetí"
        }
        return termStr
    }

    var gradeSubtitle: String? {
        if let g = grade, g > 0 {
            return "\(g). ročník"
        }
        if let gn = gradeName?.trimmingCharacters(in: .whitespacesAndNewlines), !gn.isEmpty {
            switch gn.lowercased() {
            case "first": return "1. ročník"
            case "second": return "2. ročník"
            case "third": return "3. ročník"
            case "fourth": return "4. ročník"
            default:
                if gn.localizedCaseInsensitiveContains("ročník") {
                    return gn
                }
                return "\(gn) ročník"
            }
        }
        if let y = yearInSchool, y > 0 {
            return "\(y). ročník"
        }
        return nil
    }

    func subject(for subjectId: String) -> Subject? {
        subjects.first { $0.id == subjectId }
    }
}

struct FinalMark: Decodable, Identifiable {
    let id: String
    let markText: String
    let subjectId: String
    let markDate: String?
    let editDate: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case markText = "MarkText"
        case subjectId = "SubjectId"
        case markDate = "MarkDate"
        case editDate = "EditDate"
    }
}

struct SubjectsResponse: Decodable {
    let subjects: [SubjectInfo]

    enum CodingKeys: String, CodingKey {
        case subjects = "Subjects"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.subjects = (try? container.decode([SubjectInfo].self, forKey: .subjects)) ?? []
    }
}

struct SubjectInfo: Decodable, Identifiable, Hashable {
    var id: String { subjectID }
    let subjectID: String
    let subjectName: String
    let subjectAbbrev: String
    let teacherID: String?
    let teacherName: String?
    let teacherAbbrev: String?

    var displayName: String {
        subjectName.isEmpty ? (subjectAbbrev.isEmpty ? "Předmět" : subjectAbbrev) : subjectName
    }

    var displayAbbrev: String {
        subjectAbbrev.isEmpty ? subjectName : subjectAbbrev
    }

    init(
        subjectID: String,
        subjectName: String,
        subjectAbbrev: String,
        teacherID: String? = nil,
        teacherName: String? = nil,
        teacherAbbrev: String? = nil
    ) {
        self.subjectID = subjectID
        self.subjectName = subjectName
        self.subjectAbbrev = subjectAbbrev
        self.teacherID = teacherID
        self.teacherName = teacherName
        self.teacherAbbrev = teacherAbbrev
    }

    enum CodingKeys: String, CodingKey {
        case subjectID = "SubjectID"
        case subjectName = "SubjectName"
        case subjectAbbrev = "SubjectAbbrev"
        case teacherID = "TeacherID"
        case teacherName = "TeacherName"
        case teacherAbbrev = "TeacherAbbrev"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.subjectID = ((try? c.decodeIfPresent(String.self, forKey: .subjectID)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.subjectName = ((try? c.decodeIfPresent(String.self, forKey: .subjectName)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.subjectAbbrev = ((try? c.decodeIfPresent(String.self, forKey: .subjectAbbrev)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let tId = (try? c.decodeIfPresent(String.self, forKey: .teacherID))?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.teacherID = tId?.isEmpty == false ? tId : nil
        let tName = (try? c.decodeIfPresent(String.self, forKey: .teacherName))?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.teacherName = tName?.isEmpty == false ? tName : nil
        let tAbbrev = (try? c.decodeIfPresent(String.self, forKey: .teacherAbbrev))?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.teacherAbbrev = tAbbrev?.isEmpty == false ? tAbbrev : nil
    }
}

struct SubjectThemesResponse: Decodable {
    let subject: Subject?
    let themes: [SubjectTheme]

    enum CodingKeys: String, CodingKey {
        case subject = "Subject"
        case themes = "Themes"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.subject = try? c.decodeIfPresent(Subject.self, forKey: .subject)
        self.themes = (try? c.decode([SubjectTheme].self, forKey: .themes)) ?? []
    }
}

struct SubjectTheme: Decodable, Hashable {
    let date: String
    let theme: String
    let note: String
    let hourCaption: String
    let lessonLabel: String

    var parsedDate: Date? { BakiDate.parse(date) }

    enum CodingKeys: String, CodingKey {
        case date = "Date"
        case theme = "Theme"
        case note = "Note"
        case hourCaption = "HourCaption"
        case lessonLabel = "LessonLabel"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.date = ((try? c.decodeIfPresent(String.self, forKey: .date)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.theme = ((try? c.decodeIfPresent(String.self, forKey: .theme)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.note = ((try? c.decodeIfPresent(String.self, forKey: .note)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.hourCaption = ((try? c.decodeIfPresent(String.self, forKey: .hourCaption)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.lessonLabel = ((try? c.decodeIfPresent(String.self, forKey: .lessonLabel)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
