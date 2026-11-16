import WidgetKit
import SwiftUI

struct TimetableResponse: Codable {
    let hours: [Hour]
    let days: [Day]
    let subjects: [Subject]?
    let teachers: [Teacher]?
    let rooms: [Room]?

    enum CodingKeys: String, CodingKey {
        case hours = "Hours"
        case days = "Days"
        case subjects = "Subjects"
        case teachers = "Teachers"
        case rooms = "Rooms"
    }
}

struct Hour: Codable, Identifiable {
    let id: Int
    let caption: String
    let beginTime: String
    let endTime: String

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case caption = "Caption"
        case beginTime = "BeginTime"
        case endTime = "EndTime"
    }
}

struct Day: Codable {
    let atoms: [Atom]
    let date: String

    enum CodingKeys: String, CodingKey {
        case atoms = "Atoms"
        case date = "Date"
    }
}

struct Atom: Codable {
    let hourId: Int
    let subjectId: String?
    let teacherId: String?
    let roomId: String?
    let theme: String?
    let change: Change?

    enum CodingKeys: String, CodingKey {
        case hourId = "HourId"
        case subjectId = "SubjectId"
        case teacherId = "TeacherId"
        case roomId = "RoomId"
        case theme = "Theme"
        case change = "Change"
    }
}

struct Change: Codable {
    let changeType: String?
    let description: String?
    let time: String?

    enum CodingKeys: String, CodingKey {
        case changeType = "ChangeType"
        case description = "Description"
        case time = "Time"
    }
}

struct Teacher: Codable, Identifiable {
    let id: String
    let abbrev: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case abbrev = "Abbrev"
        case name = "Name"
    }
}

struct Subject: Codable, Identifiable {
    let id: String
    let abbrev: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case abbrev = "Abbrev"
        case name = "Name"
    }
}

struct Room: Codable, Identifiable {
    let id: String
    let abbrev: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case abbrev = "Abbrev"
        case name = "Name"
    }
}

struct LessonInfo {
    let subject: String
    let room: String
    let hourCaption: String
    let timeRange: String
    var isNow: Bool
    let teacher: String
    let changeInfo: String
    let startDate: Date?
    let endDate: Date?
}

private let appGroupId = "group.com.kpn2.baki"
private let sharedDefaults = UserDefaults(suiteName: appGroupId)
private let jsonDecoder = JSONDecoder()

private func getCredential(_ key: String) -> String {
    sharedDefaults?.string(forKey: key) ?? ""
}

private func saveCredential(_ val: String, key: String) {
    sharedDefaults?.set(val, forKey: key)
}

private func loadCachedTimetable() -> TimetableResponse? {
    guard let data = sharedDefaults?.data(forKey: "cachedTimetable") else { return nil }
    return try? jsonDecoder.decode(TimetableResponse.self, from: data)
}

private func saveCachedTimetable(_ data: Data) {
    sharedDefaults?.set(data, forKey: "cachedTimetable")
}

private func cachedOr(_ error: String) -> (response: TimetableResponse?, error: String?) {
    if let cached = loadCachedTimetable() {
        return (cached, nil)
    }
    return (nil, error)
}

private let dayDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
}()

private let isoFractionalFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

private let isoStandardFormatter = ISO8601DateFormatter()

private func parseDateFromDay(_ dateString: String) -> Date? {
    if let datePart = dateString.split(separator: "T").first, datePart.count == 10,
       let d = dayDateFormatter.date(from: String(datePart)) {
        return d
    }
    return isoFractionalFormatter.date(from: dateString) ?? isoStandardFormatter.date(from: dateString)
}

private struct TimetableLookup {
    let hours: [Int: Hour]
    let subjects: [String: Subject]
    let teachers: [String: Teacher]
    let rooms: [String: Room]

    init(_ response: TimetableResponse) {
        hours = Dictionary(response.hours.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        subjects = Dictionary((response.subjects ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        teachers = Dictionary((response.teachers ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        rooms = Dictionary((response.rooms ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

private let widgetSession: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 6.0
    config.timeoutIntervalForResource = 8.0
    config.waitsForConnectivity = false
    config.requestCachePolicy = .reloadIgnoringLocalCacheData
    return URLSession(configuration: config)
}()

private func requestTimetable(_ url: URL, bearer: String) async -> TimetableResponse? {
    var request = URLRequest(url: url)
    request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
    guard let (data, response) = try? await widgetSession.data(for: request),
          (response as? HTTPURLResponse)?.statusCode == 200,
          let decoded = try? jsonDecoder.decode(TimetableResponse.self, from: data) else {
        return nil
    }
    saveCachedTimetable(data)
    return decoded
}

private func fetchTimetableResponse() async -> (response: TimetableResponse?, error: String?) {
    let baseURL = getCredential("baseURL")
    let refreshToken = getCredential("refreshToken")
    guard !baseURL.isEmpty, !refreshToken.isEmpty else {
        return cachedOr("Přihlaste se v aplikaci")
    }

    let now = Date()
    let weekday = Calendar.current.component(.weekday, from: now)
    let daysAhead = weekday == 7 ? 2 : (weekday == 1 ? 1 : 0)
    let queryDate = Calendar.current.date(byAdding: .day, value: daysAhead, to: now) ?? now
    let todayStr = dayDateFormatter.string(from: queryDate)

    guard let ttURL = URL(string: baseURL + "/api/3/timetable/actual?date=\(todayStr)") else {
        return (loadCachedTimetable(), "Chybná URL")
    }

    var bearer = getCredential("bearer")

    if !bearer.isEmpty, let decoded = await requestTimetable(ttURL, bearer: bearer) {
        return (decoded, nil)
    }

    guard let loginURL = URL(string: baseURL + "/api/login") else {
        return (loadCachedTimetable(), "Chybná URL")
    }
    var loginReq = URLRequest(url: loginURL)
    loginReq.httpMethod = "POST"
    loginReq.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    let encRefresh = refreshToken.addingPercentEncoding(withAllowedCharacters: allowed) ?? refreshToken
    loginReq.httpBody = "client_id=ANDR&grant_type=refresh_token&refresh_token=\(encRefresh)".data(using: .utf8)

    do {
        let (loginData, loginResp) = try await widgetSession.data(for: loginReq)
        if let httpLogin = loginResp as? HTTPURLResponse, (httpLogin.statusCode == 400 || httpLogin.statusCode == 401) {
            return (loadCachedTimetable(), "Přihlaste se znovu")
        }
        if let json = try? JSONSerialization.jsonObject(with: loginData) as? [String: Any],
           let newBearer = json["access_token"] as? String, !newBearer.isEmpty {
            bearer = newBearer
            saveCredential(newBearer, key: "bearer")
            if let newRefresh = json["refresh_token"] as? String, !newRefresh.isEmpty {
                saveCredential(newRefresh, key: "refreshToken")
            }
        }
    } catch {
        return cachedOr("Chyba sítě")
    }

    guard !bearer.isEmpty else {
        return cachedOr("Přihlaste se")
    }

    if let decoded = await requestTimetable(ttURL, bearer: bearer) {
        return (decoded, nil)
    }
    return cachedOr("Chyba rozvrhu")
}

private func parseLessons(for day: Day, lookup: TimetableLookup, on baseDate: Date) -> [LessonInfo] {
    var lessons: [LessonInfo] = []

    let groupedAtoms = Dictionary(grouping: day.atoms, by: { $0.hourId })

    for hourId in groupedAtoms.keys.sorted() {
        guard let atoms = groupedAtoms[hourId], !atoms.isEmpty,
              let hour = lookup.hours[hourId] else { continue }

        let endParts = hour.endTime.split(separator: ":")
        let begParts = hour.beginTime.split(separator: ":")
        guard endParts.count >= 2, begParts.count >= 2,
              let endH = Int(endParts[0]), let endM = Int(endParts[1]),
              let begH = Int(begParts[0]), let begM = Int(begParts[1]),
              let startDate = Calendar.current.date(bySettingHour: begH, minute: begM, second: 0, of: baseDate),
              let endDate = Calendar.current.date(bySettingHour: endH, minute: endM, second: 0, of: baseDate) else {
            continue
        }

        let validAtoms = atoms.filter { $0.subjectId != nil || $0.change != nil || $0.theme != nil }
        guard !validAtoms.isEmpty else { continue }

        let selectedAtom = validAtoms.first(where: { atom in
            let isCancelled = atom.change?.description?.localizedCaseInsensitiveContains("odpad") == true ||
                              atom.change?.changeType?.localizedCaseInsensitiveContains("odpad") == true
            return !isCancelled
        }) ?? validAtoms[0]

        let subject = selectedAtom.subjectId.flatMap { lookup.subjects[$0] }
        let room = selectedAtom.roomId.flatMap { lookup.rooms[$0] }
        let teacher = selectedAtom.teacherId.flatMap { lookup.teachers[$0] }

        let sub = [subject?.abbrev, subject?.name, selectedAtom.change?.changeType, selectedAtom.change?.description]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "Hodina"
        let rm = (room?.abbrev.isEmpty == false ? room?.abbrev : room?.name) ?? ""
        let tc = (teacher?.name.isEmpty == false ? teacher?.name : teacher?.abbrev) ?? ""
        let caption = hour.caption.isEmpty ? "" : "\(hour.caption). hodina"
        let timeRange = "\(hour.beginTime) - \(hour.endTime)"
        let changeDesc = selectedAtom.change?.description ?? (selectedAtom.change?.changeType != nil ? "Změna" : "")

        lessons.append(LessonInfo(
            subject: sub,
            room: rm,
            hourCaption: caption,
            timeRange: timeRange,
            isNow: false,
            teacher: tc,
            changeInfo: changeDesc,
            startDate: startDate,
            endDate: endDate
        ))
    }

    return lessons.sorted(by: { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) })
}

private func lessons(on date: Date, in response: TimetableResponse, lookup: TimetableLookup) -> [LessonInfo] {
    let target = dayDateFormatter.string(from: date)
    let day = response.days.first { day in
        if day.date.contains(target) { return true }
        guard let d = parseDateFromDay(day.date) else { return false }
        return Calendar.current.isDate(d, inSameDayAs: date)
    }
    guard let day else { return [] }
    return parseLessons(for: day, lookup: lookup, on: date)
}

private func currentOrNextLesson(in lessons: [LessonInfo], at now: Date) -> LessonInfo? {
    if var ongoing = lessons.first(where: { ($0.startDate ?? .distantFuture) <= now && now < ($0.endDate ?? .distantPast) }) {
        ongoing.isNow = true
        return ongoing
    }
    if var upcoming = lessons.first(where: { ($0.startDate ?? .distantPast) > now }) {
        upcoming.isNow = false
        return upcoming
    }
    return nil
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let configuration: ConfigurationAppIntent
    let lesson: LessonInfo?
    let message: String?
}

struct Provider: AppIntentTimelineProvider {
    typealias Entry = SimpleEntry
    typealias Intent = ConfigurationAppIntent

    func placeholder(in context: Context) -> SimpleEntry {
        let now = Date()
        return SimpleEntry(
            date: now,
            configuration: ConfigurationAppIntent(),
            lesson: LessonInfo(
                subject: "Matematika",
                room: "U1",
                hourCaption: "2. hodina",
                timeRange: "08:55 - 09:40",
                isNow: true,
                teacher: "Novák",
                changeInfo: "",
                startDate: now.addingTimeInterval(-15 * 60),
                endDate: now.addingTimeInterval(30 * 60)
            ),
            message: nil
        )
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> SimpleEntry {
        if context.isPreview {
            return placeholder(in: context)
        }

        let now = Date()

        if let cached = loadCachedTimetable() {
            let cachedLessons = lessons(on: now, in: cached, lookup: TimetableLookup(cached))
            if let lesson = currentOrNextLesson(in: cachedLessons, at: now) {
                return SimpleEntry(date: now, configuration: configuration, lesson: lesson, message: nil)
            }
        }

        let (resOpt, msg) = await fetchTimetableResponse()
        guard let res = resOpt else {
            return SimpleEntry(date: now, configuration: configuration, lesson: nil, message: msg ?? "Žádné hodiny")
        }
        let todayLessons = lessons(on: now, in: res, lookup: TimetableLookup(res))
        return currentEntry(for: todayLessons, at: now, configuration: configuration)
    }

    private func currentEntry(for lessons: [LessonInfo], at now: Date, configuration: ConfigurationAppIntent) -> SimpleEntry {
        if let lesson = currentOrNextLesson(in: lessons, at: now) {
            return SimpleEntry(date: now, configuration: configuration, lesson: lesson, message: nil)
        }
        return SimpleEntry(date: now, configuration: configuration, lesson: nil, message: lessons.isEmpty ? "Dnes volno" : "Konec vyučování")
    }

    private func appendTransitions(for lessons: [LessonInfo], after now: Date, configuration: ConfigurationAppIntent, to entries: inout [SimpleEntry]) {
        for (idx, lesson) in lessons.enumerated() {
            if let start = lesson.startDate, start > now {
                var ongoingLesson = lesson
                ongoingLesson.isNow = true
                entries.append(SimpleEntry(date: start, configuration: configuration, lesson: ongoingLesson, message: nil))
            }
            if let end = lesson.endDate, end > now {
                if idx + 1 < lessons.count {
                    var nextLesson = lessons[idx + 1]
                    nextLesson.isNow = false
                    entries.append(SimpleEntry(date: end, configuration: configuration, lesson: nextLesson, message: nil))
                } else {
                    entries.append(SimpleEntry(date: end, configuration: configuration, lesson: nil, message: "Konec vyučování"))
                }
            }
        }
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<SimpleEntry> {
        let (responseOpt, errorMsg) = await fetchTimetableResponse()
        let now = Date()

        guard let response = responseOpt else {
            let entry = SimpleEntry(date: now, configuration: configuration, lesson: nil, message: errorMsg ?? "Žádné hodiny")
            return Timeline(entries: [entry], policy: .after(now.addingTimeInterval(30 * 60)))
        }

        let lookup = TimetableLookup(response)
        let todayLessons = lessons(on: now, in: response, lookup: lookup)

        var entries = [currentEntry(for: todayLessons, at: now, configuration: configuration)]
        appendTransitions(for: todayLessons, after: now, configuration: configuration, to: &entries)

        let futureDays = response.days
            .compactMap { day -> (day: Day, date: Date)? in
                guard let d = parseDateFromDay(day.date),
                      !Calendar.current.isDate(d, inSameDayAs: now),
                      d > now else { return nil }
                return (day, d)
            }
            .sorted(by: { $0.date < $1.date })

        for futureDay in futureDays.prefix(2) {
            let futureLessons = parseLessons(for: futureDay.day, lookup: lookup, on: futureDay.date)
            guard var firstLesson = futureLessons.first else { continue }

            if let morningDate = Calendar.current.date(bySettingHour: 6, minute: 0, second: 0, of: futureDay.date),
               morningDate > now {
                firstLesson.isNow = false
                entries.append(SimpleEntry(date: morningDate, configuration: configuration, lesson: firstLesson, message: nil))
            }

            appendTransitions(for: futureLessons, after: now, configuration: configuration, to: &entries)
        }

        entries.sort(by: { $0.date < $1.date })
        var uniqueEntries: [SimpleEntry] = []
        for entry in entries {
            if let last = uniqueEntries.last, abs(last.date.timeIntervalSince(entry.date)) < 1 {
                if entry.lesson?.isNow == true {
                    uniqueEntries.removeLast()
                    uniqueEntries.append(entry)
                }
            } else {
                uniqueEntries.append(entry)
            }
        }

        let isSchoolActiveToday = todayLessons.contains(where: { ($0.endDate ?? .distantPast) > now })
        let reloadDate: Date

        if isSchoolActiveToday {
            reloadDate = now.addingTimeInterval(90 * 60)
        } else {
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86400)
            let tomorrow6AM = Calendar.current.date(bySettingHour: 6, minute: 0, second: 0, of: tomorrow)
            if let morning = tomorrow6AM, morning > now.addingTimeInterval(3600) {
                reloadDate = min(now.addingTimeInterval(3 * 3600), morning)
            } else {
                reloadDate = now.addingTimeInterval(3 * 3600)
            }
        }

        return Timeline(entries: uniqueEntries, policy: .after(reloadDate))
    }

    func recommendations() -> [AppIntentRecommendation<ConfigurationAppIntent>] {
        [AppIntentRecommendation(intent: ConfigurationAppIntent(), description: "Příští hodina")]
    }
}

struct BakiTimetableWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: Provider.Entry

    var body: some View {
        switch family {
        case .accessoryCircular:
            if let lesson = entry.lesson {
                if lesson.isNow, let start = lesson.startDate, let end = lesson.endDate, start < end {
                    ProgressView(timerInterval: start...end, countsDown: false) {
                        VStack(spacing: 1) {
                            Text(lesson.subject)
                                .font(.system(size: 15, weight: .bold))
                                .minimumScaleFactor(0.6)
                            if !lesson.room.isEmpty {
                                Text(lesson.room)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .progressViewStyle(.circular)
                } else {
                    VStack(spacing: 1) {
                        Text(lesson.subject)
                            .font(.system(size: 16, weight: .bold))
                            .minimumScaleFactor(0.6)
                        if !lesson.room.isEmpty {
                            Text(lesson.room)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.tint)
                        }
                    }
                }
            } else {
                Text("—")
                    .font(.headline)
            }

        case .accessoryInline:
            if let lesson = entry.lesson {
                let roomStr = lesson.room.isEmpty ? "" : " • \(lesson.room)"
                if lesson.isNow, let start = lesson.startDate, let end = lesson.endDate, start < end {
                    Text("\(lesson.subject)\(roomStr) • \(Text(.currentDate, format: .timer(countingDownIn: start..<end.addingTimeInterval(60), maxPrecision: .seconds(60))))")
                } else if let start = lesson.startDate, start > entry.date {
                    Text("Příští: \(lesson.subject)\(roomStr) • za \(Text(.currentDate, format: .timer(countingDownIn: entry.date..<start.addingTimeInterval(60), maxPrecision: .seconds(60))))")
                } else {
                    Text("Příští: \(lesson.subject)\(roomStr)")
                }
            } else {
                Text(entry.message ?? "Žádné hodiny")
            }

        case .accessoryCorner:
            if let lesson = entry.lesson {
                Text(lesson.subject)
                    .font(.title3)
                    .bold()
                    .widgetLabel {
                        if lesson.isNow, let start = lesson.startDate, let end = lesson.endDate, start < end {
                            HStack(spacing: 2) {
                                if !lesson.room.isEmpty {
                                    Text("\(lesson.room) • ")
                                }
                                Text(.currentDate, format: .timer(countingDownIn: start..<end.addingTimeInterval(60), maxPrecision: .seconds(60)))
                            }
                        } else if let start = lesson.startDate, start > entry.date {
                            HStack(spacing: 2) {
                                if !lesson.room.isEmpty {
                                    Text("\(lesson.room) • za ")
                                } else {
                                    Text("za ")
                                }
                                Text(.currentDate, format: .timer(countingDownIn: entry.date..<start.addingTimeInterval(60), maxPrecision: .seconds(60)))
                            }
                        } else {
                            Text(lesson.room.isEmpty ? lesson.timeRange : "\(lesson.room) • \(lesson.timeRange)")
                        }
                    }
            } else {
                Text("—")
            }

        default:
            if let lesson = entry.lesson {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        let statusColor: Color = lesson.isNow ? .green : .orange
                        HStack(spacing: 4) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 5, height: 5)
                            Text(lesson.isNow ? "Probíhá" : "Nadcházející")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(statusColor)
                        }

                        if !lesson.hourCaption.isEmpty {
                            Text("• \(lesson.hourCaption)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if !lesson.room.isEmpty {
                            Text(lesson.room)
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.25))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }

                    HStack(alignment: .firstTextBaseline) {
                        Text(lesson.subject)
                            .font(.system(size: 16, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Spacer()

                        Text(lesson.timeRange)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    if lesson.isNow, let start = lesson.startDate, let end = lesson.endDate, start < end {
                        HStack(spacing: 0) {
                            ProgressView(timerInterval: start...end, countsDown: false) {
                                EmptyView()
                            } currentValueLabel: {
                                EmptyView()
                            }
                            .tint(.green)
                            .labelsHidden()
                            .frame(width: 110)

                            Spacer()

                            Text(.currentDate, format: .timer(countingDownIn: start..<end.addingTimeInterval(60), maxPrecision: .seconds(60)))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.green)
                                .lineLimit(1)
                                .multilineTextAlignment(.trailing)
                        }
                    } else if !lesson.changeInfo.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9))
                            Text(lesson.changeInfo)
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                    } else if let start = lesson.startDate, start > entry.date {
                        HStack(spacing: 4) {
                            Text("Začíná za")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text(.currentDate, format: .timer(countingDownIn: entry.date..<start.addingTimeInterval(60), maxPrecision: .seconds(60)))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.orange)
                                .lineLimit(1)

                            if !lesson.teacher.isEmpty {
                                Spacer()
                                Text(lesson.teacher)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    } else if !lesson.teacher.isEmpty {
                        Text(lesson.teacher)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rozvrh")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(entry.message ?? "Žádné hodiny")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

struct BakiTimetableWidget: Widget {
    let kind: String = "BakiTimetableWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: Provider()) { entry in
            BakiTimetableWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Příští hodina")
        .description("Příští hodina, učebna a čas z rozvrhu.")
        .supportedFamilies([
            .accessoryRectangular,
            .accessoryCircular,
            .accessoryInline,
            .accessoryCorner
        ])
    }
}

#Preview(as: .accessoryRectangular) {
    BakiTimetableWidget()
} timeline: {
    let now = Date()
    SimpleEntry(
        date: now,
        configuration: ConfigurationAppIntent(),
        lesson: LessonInfo(
            subject: "Matematika",
            room: "U1",
            hourCaption: "2. hodina",
            timeRange: "08:55 - 09:40",
            isNow: true,
            teacher: "Novák",
            changeInfo: "",
            startDate: now.addingTimeInterval(-20 * 60),
            endDate: now.addingTimeInterval(25 * 60)
        ),
        message: nil
    )
    SimpleEntry(
        date: now.addingTimeInterval(25 * 60),
        configuration: ConfigurationAppIntent(),
        lesson: LessonInfo(
            subject: "Český jazyk",
            room: "U5",
            hourCaption: "3. hodina",
            timeRange: "10:00 - 10:45",
            isNow: false,
            teacher: "Svobodová",
            changeInfo: "",
            startDate: now.addingTimeInterval(45 * 60),
            endDate: now.addingTimeInterval(90 * 60)
        ),
        message: nil
    )
}
