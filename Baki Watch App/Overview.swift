import SwiftUI

struct OverviewMark: Identifiable {
    var id: String { mark.id }
    let mark: Mark
    let subject: Subject
    let averageText: String?
    let subjectNote: String?
}

struct NextLesson: Identifiable {
    var id: String { "\(day.date)_\(atom.id)_\(hour?.id ?? 0)" }
    let atom: Atom
    let day: Day
    let subject: Subject?
    let teacher: Teacher?
    let room: Room?
    let hour: Hour?
    let startDate: Date?
    let endDate: Date?

    func isNow(at now: Date = Date()) -> Bool {
        guard let startDate, let endDate else { return false }
        return startDate <= now && now < endDate
    }

    var isNow: Bool { isNow() }
}

struct CarouselPageIndicator: View {
    let count: Int
    let selectedIndex: Int

    var body: some View {
        if count > 1 {
            let selectedIndex = min(selectedIndex, count - 1)
            HStack(spacing: 3) {
                ForEach(0..<count, id: \.self) { i in
                    Capsule()
                        .fill(i == selectedIndex ? Color.primary.opacity(0.75) : Color.primary.opacity(0.18))
                        .frame(width: i == selectedIndex ? 10 : 3, height: 2)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: selectedIndex)
            .padding(.top, 1)
        }
    }
}

struct OverviewMarkCardView: View {
    let item: OverviewMark

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.subject.displayName)
                    .font(.caption2)
                    .bold()
                    .foregroundStyle(.blue)
                    .lineLimit(1)

                let caption = item.mark.caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                Text(caption.isEmpty ? "Známka" : caption)
                    .font(.headline)
                    .bold()
                    .lineLimit(1)

                if let weight = item.mark.weight {
                    Text("Váha \(weight)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let calc = item.mark.calculatedMarkText?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !calc.isEmpty,
                          calc != item.mark.displayText {
                    Text("Vypočteno: \(calc)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            Text(item.mark.displayText)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.blue)
                .padding(.trailing, 2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 82)
        .background(Color.blue.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct MarksCarouselView: View {
    let marks: [OverviewMark]
    @State private var selectedIndex: Int = 0

    var body: some View {
        VStack(spacing: 4) {
            TabView(selection: $selectedIndex) {
                ForEach(Array(marks.enumerated()), id: \.element.id) { index, item in
                    NavigationLink {
                        MarkDetailView(
                            mark: item.mark,
                            subject: item.subject,
                            averageText: item.averageText,
                            subjectNote: item.subjectNote
                        )
                    } label: {
                        OverviewMarkCardView(item: item)
                    }
                    .buttonStyle(.plain)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 82)
            .onChange(of: marks.map(\.id)) {
                selectedIndex = 0
            }

            CarouselPageIndicator(count: marks.count, selectedIndex: selectedIndex)
        }
    }
}

struct OverviewTimetableCardView: View {
    let lesson: NextLesson

    private func statusInfo(at now: Date) -> (text: String, color: Color) {
        if lesson.atom.isCancelled {
            return ("Odpadá", .secondary)
        }
        if lesson.isNow(at: now) {
            return ("Probíhá", .green)
        }
        if let end = lesson.endDate, end <= now {
            return ("Proběhla", .secondary)
        }
        if let start = lesson.startDate {
            if Calendar.current.isDateInToday(start) {
                return ("Následuje", .orange)
            } else if Calendar.current.isDateInTomorrow(start) {
                return ("Zítra", .blue)
            } else {
                let weekday = Calendar.current.component(.weekday, from: start)
                return (BakiDate.weekdayName(dayOfWeek: weekday, date: start), .blue)
            }
        }
        return ("Další", .orange)
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            let status = statusInfo(at: context.date)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(status.text)
                        .font(.caption2)
                        .bold()
                        .foregroundStyle(status.color)
                        .lineLimit(1)

                    if let hour = lesson.hour, !hour.caption.isEmpty {
                        Text("• \(hour.caption). hod")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if let room = lesson.room?.displayName {
                        Text(room)
                            .font(.caption2)
                            .bold()
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.orange.opacity(0.25))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                }

                Text(lesson.subject?.displayName ?? (lesson.atom.isCancelled ? "Odpadá" : "Hodina"))
                    .font(.headline)
                    .bold()
                    .strikethrough(lesson.atom.isCancelled)
                    .foregroundStyle(lesson.atom.isCancelled ? .secondary : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                HStack {
                    if let hour = lesson.hour, !hour.beginTime.isEmpty, !hour.endTime.isEmpty {
                        Text("\(hour.beginTime) – \(hour.endTime)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if let change = lesson.atom.change {
                        HStack(spacing: 2) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 8))
                            Text(change.displayDescription)
                                .font(.caption2)
                        }
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 82)
            .background(Color.orange.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

struct TimetableCarouselView: View {
    let lessons: [NextLesson]
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedIndex: Int
    @State private var scrollPosition: ScrollPosition

    init(lessons: [NextLesson]) {
        self.lessons = lessons
        let initial = Self.initialIndex(in: lessons)
        _selectedIndex = State(initialValue: initial)
        _scrollPosition = State(initialValue: ScrollPosition(id: initial))
    }

    private static func initialIndex(in lessons: [NextLesson]) -> Int {
        let now = Date()
        if let activeIndex = lessons.firstIndex(where: { $0.isNow(at: now) && !$0.atom.isCancelled }) {
            return activeIndex
        }
        if let nextIndex = lessons.firstIndex(where: { !$0.atom.isCancelled && ($0.startDate ?? .distantPast) > now }) {
            return nextIndex
        }
        if let activeAny = lessons.firstIndex(where: { $0.isNow(at: now) }) {
            return activeAny
        }
        if let nextAny = lessons.firstIndex(where: { ($0.startDate ?? .distantPast) > now }) {
            return nextAny
        }
        return 0
    }

    var body: some View {
        VStack(spacing: 4) {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(Array(lessons.enumerated()), id: \.element.id) { index, lesson in
                        NavigationLink {
                            LessonDetailView(
                                atom: lesson.atom,
                                day: lesson.day,
                                subject: lesson.subject,
                                teacher: lesson.teacher,
                                room: lesson.room,
                                hour: lesson.hour
                            )
                        } label: {
                            OverviewTimetableCardView(lesson: lesson)
                        }
                        .buttonStyle(.plain)
                        .containerRelativeFrame(.horizontal)
                        .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .scrollPosition($scrollPosition)
            .frame(height: 82)

            CarouselPageIndicator(count: lessons.count, selectedIndex: selectedIndex)
        }
        .onAppear {
            scrollPosition.scrollTo(id: selectedIndex)
        }
        .onChange(of: scrollPosition.viewID(type: Int.self)) { _, newIndex in
            if scrollPosition.isPositionedByUser, let newIndex, lessons.indices.contains(newIndex) {
                selectedIndex = newIndex
            }
        }
        .onChange(of: lessons.map(\.id)) {
            let target = Self.initialIndex(in: lessons)
            selectedIndex = target
            scrollPosition.scrollTo(id: target)
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                let target = Self.initialIndex(in: lessons)
                selectedIndex = target
                scrollPosition.scrollTo(id: target)
            }
        }
    }
}

struct OverviewMessageCardView: View {
    let message: KomensMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                let senderName = message.sender?.name ?? message.relevantName
                Text(senderName?.isEmpty == false ? senderName! : "Zpráva")
                    .font(.caption2)
                    .bold()
                    .foregroundStyle(.red)
                    .lineLimit(1)

                Spacer()

                if let dateStr = message.effectiveDateString {
                    Text(BakiDate.formatCzechDate(dateStr))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            let title = message.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            Text(title.isEmpty ? "Zpráva" : title)
                .font(.headline)
                .bold()
                .lineLimit(1)

            if let text = message.text {
                let preview = cleanHTML(String(text.prefix(400))).replacingOccurrences(of: "\n", with: " ")
                if !preview.isEmpty {
                    Text(preview)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 82)
        .background(Color.red.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct MessagesCarouselView: View {
    let messages: [KomensMessage]
    @State private var selectedIndex: Int = 0

    var body: some View {
        VStack(spacing: 4) {
            TabView(selection: $selectedIndex) {
                ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                    NavigationLink {
                        MessageDetailView(message: message)
                    } label: {
                        OverviewMessageCardView(message: message)
                    }
                    .buttonStyle(.plain)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 82)

            CarouselPageIndicator(count: messages.count, selectedIndex: selectedIndex)
        }
    }
}

struct OverviewHomeworkCardView: View {
    let homework: Homework

    private func dueInfo() -> (text: String, color: Color)? {
        guard let due = homework.dueDate else { return nil }
        let info = DueText.describe(due, isPending: !homework.isDone && !homework.isClosed)
        let color: Color = info.color == .purple ? .secondary : info.color
        return (info.text, color)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text("Úkol")
                    .font(.caption2)
                    .bold()
                    .foregroundStyle(.green)
                    .lineLimit(1)

                Spacer()

                if let due = dueInfo() {
                    Text(due.text)
                        .font(.caption2)
                        .bold()
                        .foregroundStyle(due.color)
                        .lineLimit(1)
                }
            }

            Text(homework.subjectName)
                .font(.headline)
                .bold()
                .lineLimit(1)

            let preview = homework.contentText.replacingOccurrences(of: "\n", with: " ")
            Text(preview.isEmpty ? "Bez textu" : preview)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 82)
        .background(Color.green.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct OverviewHomeworkDoneCardView: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Úkoly")
                    .font(.caption2)
                    .bold()
                    .foregroundStyle(.green)
                    .lineLimit(1)

                Text("Vše hotovo")
                    .font(.headline)
                    .bold()
                    .lineLimit(1)

                Text("Žádné nesplněné úkoly")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 82)
        .background(Color.green.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct HomeworksCarouselView: View {
    let homeworks: [Homework]
    let store: HomeworkStore
    @State private var selectedIndex: Int = 0
    @State private var scrollPosition = ScrollPosition(id: 0)

    var body: some View {
        VStack(spacing: 4) {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(Array(homeworks.enumerated()), id: \.element.id) { index, homework in
                        NavigationLink {
                            HomeworkDetailView(store: store, homeworkID: homework.id)
                        } label: {
                            OverviewHomeworkCardView(homework: homework)
                        }
                        .buttonStyle(.plain)
                        .containerRelativeFrame(.horizontal)
                        .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .scrollPosition($scrollPosition)
            .frame(height: 82)

            CarouselPageIndicator(count: homeworks.count, selectedIndex: selectedIndex)
        }
        .onChange(of: scrollPosition.viewID(type: Int.self)) { _, newIndex in
            if scrollPosition.isPositionedByUser, let newIndex, homeworks.indices.contains(newIndex) {
                selectedIndex = newIndex
            }
        }
        .onChange(of: homeworks.map(\.id)) {
            let clamped = min(selectedIndex, max(0, homeworks.count - 1))
            selectedIndex = clamped
            scrollPosition.scrollTo(id: clamped)
        }
    }
}

struct MarksCarouselSkeleton: View {
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Matematika")
                        .font(.caption2)
                        .bold()

                    Text("Čtvrtletní práce")
                        .font(.headline)
                        .bold()

                    Text("Váha 10")
                        .font(.caption2)
                }

                Spacer(minLength: 4)

                Text("1")
                    .font(.system(size: 34, weight: .bold))
                    .padding(.trailing, 2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 82)
            .background(Color.blue.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .skeletonPulse()

            HStack(spacing: 3) {
                Capsule()
                    .fill(Color.primary.opacity(0.25))
                    .frame(width: 10, height: 2)
                ForEach(0..<2, id: \.self) { _ in
                    Capsule()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: 3, height: 2)
                }
            }
            .padding(.top, 1)
            .skeletonPulse()
        }
    }
}

struct TimetableCarouselSkeleton: View {
    var body: some View {
        VStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("Další")
                        .font(.caption2)
                        .bold()

                    Text("• 2. hod")
                        .font(.caption2)

                    Spacer()

                    Text("U12")
                        .font(.caption2)
                        .bold()
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .clipShape(Capsule())
                }

                Text("Matematika")
                    .font(.headline)
                    .bold()

                Text("08:55 – 09:40")
                    .font(.caption2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 82)
            .background(Color.orange.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .skeletonPulse()

            HStack(spacing: 3) {
                Capsule()
                    .fill(Color.primary.opacity(0.25))
                    .frame(width: 10, height: 2)
                ForEach(0..<2, id: \.self) { _ in
                    Capsule()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: 3, height: 2)
                }
            }
            .padding(.top, 1)
            .skeletonPulse()
        }
    }
}

struct MessagesCarouselSkeleton: View {
    var body: some View {
        VStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Mgr. Jan Novák")
                        .font(.caption2)
                        .bold()
                    Spacer()
                    Text("12. 10.")
                        .font(.caption2)
                }

                Text("Informace k výuce")
                    .font(.headline)
                    .bold()

                Text("Text zprávy z Komens")
                    .font(.caption2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 82)
            .background(Color.red.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .skeletonPulse()

            HStack(spacing: 3) {
                Capsule()
                    .fill(Color.primary.opacity(0.25))
                    .frame(width: 10, height: 2)
                ForEach(0..<2, id: \.self) { _ in
                    Capsule()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: 3, height: 2)
                }
            }
            .padding(.top, 1)
            .skeletonPulse()
        }
    }
}

struct HomeworksCarouselSkeleton: View {
    var body: some View {
        VStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Úkol")
                        .font(.caption2)
                        .bold()
                    Spacer()
                    Text("Zítra")
                        .font(.caption2)
                }

                Text("Matematika")
                    .font(.headline)
                    .bold()

                Text("Pracovní list str. 12")
                    .font(.caption2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 82)
            .background(Color.green.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .skeletonPulse()

            HStack(spacing: 3) {
                Capsule()
                    .fill(Color.primary.opacity(0.25))
                    .frame(width: 10, height: 2)
                ForEach(0..<2, id: \.self) { _ in
                    Capsule()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: 3, height: 2)
                }
            }
            .padding(.top, 1)
            .skeletonPulse()
        }
    }
}

struct OverviewSkeleton: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                MarksCarouselSkeleton()

                TimetableCarouselSkeleton()

                MessagesCarouselSkeleton()

                HomeworksCarouselSkeleton()

                NavigationLink("Menu") {}
                    .skeletonPulse()
            }
            .padding(.top, 55)
        }
        .bakiHeader("Baki", blurred: true)
        .allowsHitTesting(false)
    }
}

struct Overview: View {
    @Environment(\.scenePhase) private var scenePhase

    @State private var subjects: [SubjectMarks] = []
    @State private var timetable: TimetableResponse?
    @State private var receivedMessages: [KomensMessage] = []
    @State private var noticeMessages: [KomensMessage] = []
    @State private var homeworkStore = HomeworkStore()

    @State private var latestMarks: [OverviewMark] = []
    @State private var latestMessages: [KomensMessage] = []
    @State private var displayedDayLessons: [NextLesson] = []

    @State private var isLoading = true
    @State private var hasLoaded = false
    @State private var lastLoadedAt: Date?
    @State private var showsSkeleton = false
    @State private var loadFailed = false

    private enum LoadResult {
        case marks(MarksResponse?)
        case timetable(TimetableResponse?)
        case received([KomensMessage]?)
        case notices([KomensMessage]?)
        case homeworks([Homework]?)
    }

    private var hasAnyData: Bool {
        timetable != nil || !subjects.isEmpty || !receivedMessages.isEmpty || !noticeMessages.isEmpty || homeworkStore.hasLoaded
    }

    private var pendingHomeworks: [Homework] {
        Array(
            homeworkStore.homeworks
                .filter { !$0.isDone && !$0.isClosed }
                .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
                .prefix(5)
        )
    }

    private static func makeLatestMarks(from subjects: [SubjectMarks]) -> [OverviewMark] {
        let all = subjects.flatMap { sm in
            sm.marks.map { mark in
                OverviewMark(
                    mark: mark,
                    subject: sm.subject,
                    averageText: sm.averageText,
                    subjectNote: sm.subjectNote
                )
            }
        }
        let dated = all.map { ($0, $0.mark.parsedDate ?? .distantPast) }
        return dated.sorted { a, b in
            if a.1 != b.1 {
                return a.1 > b.1
            }
            let new1 = a.0.mark.isNew == true
            let new2 = b.0.mark.isNew == true
            if new1 != new2 {
                return new1
            }
            return a.0.mark.id > b.0.mark.id
        }
        .prefix(5)
        .map(\.0)
    }

    private static func makeLatestMessages(_ messages: [KomensMessage]) -> [KomensMessage] {
        var seen = Set<String>()
        let unique = messages.filter { seen.insert($0.id).inserted }
        let dated = unique.map { ($0, $0.parsedDate ?? .distantPast) }
        return dated.sorted { a, b in
            if a.1 != b.1 {
                return a.1 > b.1
            }
            return (a.0.effectiveDateString ?? "") > (b.0.effectiveDateString ?? "")
        }
        .prefix(5)
        .map(\.0)
    }

    private static func lessons(from timetable: TimetableResponse?) -> [NextLesson] {
        guard let timetable else { return [] }
        let now = Date()
        let calendar = Calendar.current

        let hoursById = Dictionary(timetable.hours.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let sortedDays = timetable.days.compactMap { day -> (day: Day, date: Date)? in
            guard let d = BakiDate.parse(day.date) else { return nil }
            return (day, d)
        }.sorted { $0.date < $1.date }

        func lessons(for day: Day, on dayDate: Date) -> [NextLesson] {
            let groupedAtoms = Dictionary(grouping: day.atoms, by: { $0.hourId })
            var list: [NextLesson] = []
            for hourId in groupedAtoms.keys.sorted() {
                guard let atoms = groupedAtoms[hourId],
                      let hour = hoursById[hourId],
                      let dates = hour.dates(on: dayDate) else {
                    continue
                }

                let validAtoms = atoms.filter { $0.subjectId != nil || $0.change != nil || $0.theme != nil }
                guard !validAtoms.isEmpty else { continue }

                let selectedAtom = validAtoms.first(where: { !$0.isCancelled }) ?? validAtoms[0]

                list.append(NextLesson(
                    atom: selectedAtom,
                    day: day,
                    subject: timetable.subject(id: selectedAtom.subjectId),
                    teacher: timetable.teacher(id: selectedAtom.teacherId),
                    room: timetable.room(id: selectedAtom.roomId),
                    hour: hour,
                    startDate: dates.start,
                    endDate: dates.end
                ))
            }
            return list
        }

        var todayLessons: [NextLesson] = []
        if let today = sortedDays.first(where: { calendar.isDateInToday($0.date) }) {
            todayLessons = lessons(for: today.day, on: today.date)
            if todayLessons.contains(where: { ($0.endDate ?? .distantPast) > now }) {
                return todayLessons
            }
        }

        for entry in sortedDays where entry.date > now && !calendar.isDateInToday(entry.date) {
            let list = lessons(for: entry.day, on: entry.date)
            if !list.isEmpty { return list }
        }

        if !todayLessons.isEmpty {
            return todayLessons
        }

        for entry in sortedDays.reversed() {
            let list = lessons(for: entry.day, on: entry.date)
            if !list.isEmpty { return list }
        }

        return []
    }

    private func rebuildMarks() {
        latestMarks = Self.makeLatestMarks(from: subjects)
    }

    private func rebuildMessages() {
        latestMessages = Self.makeLatestMessages(receivedMessages + noticeMessages)
    }

    private func rebuildLessons() {
        displayedDayLessons = Self.lessons(from: timetable)
    }

    var body: some View {
        Group {
            if showsSkeleton || (isLoading && !hasAnyData) {
                OverviewSkeleton()
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        if !latestMarks.isEmpty {
                            MarksCarouselView(marks: latestMarks)
                        } else if isLoading && subjects.isEmpty {
                            MarksCarouselSkeleton()
                        }

                        if !displayedDayLessons.isEmpty {
                            TimetableCarouselView(lessons: displayedDayLessons)
                        } else if isLoading && timetable == nil {
                            TimetableCarouselSkeleton()
                        }

                        if !latestMessages.isEmpty {
                            MessagesCarouselView(messages: latestMessages)
                        } else if isLoading && receivedMessages.isEmpty && noticeMessages.isEmpty {
                            MessagesCarouselSkeleton()
                        }

                        if !pendingHomeworks.isEmpty {
                            HomeworksCarouselView(homeworks: pendingHomeworks, store: homeworkStore)
                        } else if homeworkStore.hasLoaded {
                            NavigationLink {
                                HomeworkScreen()
                            } label: {
                                OverviewHomeworkDoneCardView()
                            }
                            .buttonStyle(.plain)
                        } else if isLoading {
                            HomeworksCarouselSkeleton()
                        }

                        if loadFailed && !isLoading {
                            Text("Data se nepodařilo načíst")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        NavigationLink("Menu") {
                            MainScreen()
                        } .tint(.blue)

                        Button {
                            showsSkeleton = true
                            Task { await loadData() }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.clockwise")
                                Text("Obnovit")
                            }
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoading)
                        .padding(.top, 10)
                    }
                    .padding(.top, 55)
                }
                .bakiHeader("Baki", blurred: true)
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            PhoneLinkManager.shared.stopHandoff()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                rebuildLessons()
                let isStale = lastLoadedAt.map {
                    !Calendar.current.isDateInToday($0) || Date().timeIntervalSince($0) > 15 * 60
                } ?? false
                if hasLoaded, !isLoading, isStale {
                    Task { await loadData() }
                }
            }
        }
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await loadData()
        }
    }

    private func loadData() async {
        isLoading = true
        defer {
            isLoading = false
            showsSkeleton = false
        }

        var anySucceeded = false
        var pendingMessageResults = 2
        var received: [KomensMessage]?
        var notices: [KomensMessage]?

        await withTaskGroup(of: LoadResult.self) { group in
            group.addTask { .marks(try? await BakiClient.shared.fetchMarks()) }
            group.addTask { .timetable(try? await BakiClient.shared.fetchTimetable()) }
            group.addTask { .received(try? await BakiClient.shared.fetchMessages(type: .received)) }
            group.addTask { .notices(try? await BakiClient.shared.fetchMessages(type: .noticeboard)) }
            group.addTask {
                let calendar = Calendar.current
                let today = calendar.startOfDay(for: Date())
                let from = calendar.date(byAdding: .day, value: -30, to: today) ?? today
                let to = calendar.date(byAdding: .day, value: 60, to: today) ?? today
                return .homeworks(try? await BakiClient.shared.fetchHomeworks(from: from, to: to))
            }

            for await result in group {
                switch result {
                case .marks(let marks):
                    guard let marks else { break }
                    anySucceeded = true
                    subjects = marks.subjects
                    rebuildMarks()

                case .timetable(let fetched):
                    if let fetched {
                        anySucceeded = true
                        timetable = fetched
                    } else if timetable == nil {
                        timetable = CredentialStorage.cachedTimetable
                    }
                    rebuildLessons()

                case .received(let messages):
                    received = messages
                    pendingMessageResults -= 1
                case .notices(let messages):
                    notices = messages
                    pendingMessageResults -= 1

                case .homeworks(let fetched):
                    guard let fetched else { break }
                    anySucceeded = true
                    homeworkStore.homeworks = fetched
                    homeworkStore.hasLoaded = true
                }

                if pendingMessageResults == 0 {
                    pendingMessageResults = -1
                    if received != nil || notices != nil {
                        anySucceeded = true
                        if let received { receivedMessages = received }
                        if let notices { noticeMessages = notices }
                        rebuildMessages()
                    }
                }
            }
        }

        loadFailed = !anySucceeded
        if anySucceeded {
            lastLoadedAt = Date()
        }
    }
}
