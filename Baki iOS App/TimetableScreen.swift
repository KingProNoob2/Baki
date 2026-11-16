import SwiftUI

enum LessonStatus: Equatable {
    case none
    case past
    case active(progress: Double, minutesLeft: Int)
    case next(minutesUntil: Int)
}

struct TimetableScreen: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case day = "Den"
        case week = "Týden"

        var id: Self { self }

        var systemImage: String {
            switch self {
            case .day: return "calendar.day.timeline.left"
            case .week: return "calendar"
            }
        }
    }

    static let weekRange = -10...10

    @State private var mode: Mode = SavedMode.load("timetable", default: .day)
    @State private var weekOffset = Self.todayWeekOffset
    @State private var selectedWeekday = Self.todayWeekday
    @State private var weeks: [Int: TimetableResponse] = Self.initialWeeks()
    @State private var loadedWeeks: Set<Int> = []
    /// Mirrors !isShowingToday but changes inside withAnimation, so only the toolbar animates.
    @State private var showsTodayButton = false

    private var isShowingToday: Bool {
        weekOffset == Self.todayWeekOffset && (mode == .week || selectedWeekday == Self.todayWeekday)
    }

    /// The day shown in day mode, nil in week mode or before the week has loaded.
    private var selectedDay: Day? {
        guard mode == .day, let days = weeks[weekOffset]?.days, !days.isEmpty else { return nil }
        return days.first { $0.dayOfWeek == selectedWeekday } ?? days[0]
    }

    private func dayMenuTitle(for day: Day) -> String {
        guard let date = BakiDate.parse(day.date) else { return dayName(for: day) }
        return "\(dayName(for: day)) \(Self.shortDateFormatter.string(from: date))"
    }

    /// Floating glass button showing the selected day; opens a system glass menu to pick another.
    @ViewBuilder
    private var dayMenuButton: some View {
        if let selected = selectedDay, let days = weeks[weekOffset]?.days {
            let dayNumber = BakiDate.parse(selected.date).map { Calendar.current.component(.day, from: $0) }

            Menu {
                Picker("Den", selection: Binding(
                    get: { selected.dayOfWeek },
                    set: { weekday in withAnimation { selectedWeekday = weekday } }
                )) {
                    ForEach(days) { day in
                        Text(dayMenuTitle(for: day)).tag(day.dayOfWeek)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                VStack(spacing: 0) {
                    Text(String(dayName(for: selected).prefix(2)))
                        .font(.caption2.weight(.semibold))
                    Text(dayNumber.map(String.init) ?? "")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                }
                .frame(width: 56, height: 56)
                .foregroundStyle(.primary)
            }
            // Keep Monday at the top even though the menu opens upwards.
            .menuOrder(.fixed)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Vybrat den")
            .accessibilityValue(dayName(for: selected))
            .padding(.trailing, 20)
            .padding(.bottom, 12)
        }
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
        .navigationTitle("Rozvrh")
        .overlay(alignment: .bottomTrailing) {
            dayMenuButton
        }
        .onChange(of: mode) { SavedMode.save("timetable", mode) }
        .onAppear { showsTodayButton = !isShowingToday }
        .onChange(of: isShowingToday) { _, showing in
            withAnimation { showsTodayButton = !showing }
        }
        .toolbar {
            if showsTodayButton {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Dnes") { goToToday() }
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Předchozí týden", systemImage: "chevron.left") {
                    changeWeek(by: -1)
                }
                .disabled(weekOffset <= Self.weekRange.lowerBound)
                Button("Další týden", systemImage: "chevron.right") {
                    changeWeek(by: 1)
                }
                .disabled(weekOffset >= Self.weekRange.upperBound)
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Zobrazení", selection: $mode) {
                        ForEach(Mode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.systemImage).tag(mode)
                        }
                    }
                } label: {
                    Label("Zobrazení", systemImage: mode.systemImage)
                }
            }
        }
        .task(id: weekOffset) {
            await loadTimetable(offset: weekOffset)
            for neighbour in [weekOffset + 1, weekOffset - 1]
            where Self.weekRange.contains(neighbour) && weeks[neighbour] == nil {
                await loadTimetable(offset: neighbour)
            }
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let timetable = weeks[weekOffset]
        let days = timetable?.days ?? []

        if timetable == nil && !loadedWeeks.contains(weekOffset) {
            TimetableSkeleton()
        } else if days.isEmpty {
            ContentUnavailableView("Žádný rozvrh", systemImage: "calendar")
                .refreshable { await loadTimetable(offset: weekOffset) }
        } else {
            switch mode {
            case .day:
                dayList(days: days, timetable: timetable, now: now)
            case .week:
                weekList(days: days, timetable: timetable, now: now)
            }
        }
    }

    private func dayList(days: [Day], timetable: TimetableResponse?, now: Date) -> some View {
        let day = days.first { $0.dayOfWeek == selectedWeekday } ?? days[0]

        return dayListBody(day, timetable: timetable, now: now)
    }

    private func dayListBody(_ day: Day, timetable: TimetableResponse?, now: Date) -> some View {
        let lessons = Self.lessons(in: day)
        let statuses = Self.statuses(for: lessons, in: day, timetable: timetable, now: now)

        return GroupedList {
            Section {
                if lessons.isEmpty {
                    Text("Volno")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(lessons.enumerated()), id: \.offset) { index, atom in
                    lessonLink(for: atom, in: day, timetable: timetable, status: statuses[index] ?? .none)
                }
            } header: {
                dayHeader(day)
            } footer: {
                if Self.isToday(day), !lessons.isEmpty, statuses.values.allSatisfy({ $0 == .past }) {
                    Text("Vyučování pro dnešek skončilo.")
                }
            }
        }
        .groupedList()
        .listSectionSpacing(0)
        .environment(\.defaultMinListRowHeight, 0)
        .refreshable { await loadTimetable(offset: weekOffset) }
    }

    private func goToToday() {
        withAnimation {
            weekOffset = Self.todayWeekOffset
            selectedWeekday = Self.todayWeekday
        }
    }

    private func weekList(days: [Day], timetable: TimetableResponse?, now: Date) -> some View {
        return ScrollViewReader { proxy in
            GroupedList {
                ForEach(days) { day in
                    let lessons = Self.lessons(in: day)
                    let statuses = Self.statuses(for: lessons, in: day, timetable: timetable, now: now)
                    Section {
                        if lessons.isEmpty {
                            Text("Volno")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(Array(lessons.enumerated()), id: \.offset) { index, atom in
                            lessonLink(for: atom, in: day, timetable: timetable, status: statuses[index] ?? .none)
                        }
                    } header: {
                        dayHeader(day)
                    }
                    .id(day.id)
                }
            }
            .groupedList()
            .refreshable { await loadTimetable(offset: weekOffset) }
            .onAppear {
                if let today = days.first(where: { Self.isToday($0) }) {
                    proxy.scrollTo(today.id, anchor: .top)
                }
            }
        }
    }


    private func changeWeek(by delta: Int) {
        let target = weekOffset + delta
        guard Self.weekRange.contains(target) else { return }
        withAnimation { weekOffset = target }
    }

    private func dayHeader(_ day: Day) -> some View {
        let isToday = Self.isToday(day)
        let date = BakiDate.parse(day.date)

        return HStack(spacing: 6) {
            Text(dayName(for: day))
                .font(.headline)
                .foregroundStyle(.primary)
            if let date {
                Text(Self.shortDateFormatter.string(from: date))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if isToday {
                Text("Dnes")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.18), in: Capsule())
            }
            Spacer()
        }
        .textCase(nil)
    }

    private func lessonLink(for atom: Atom, in day: Day, timetable: TimetableResponse?, status: LessonStatus) -> some View {
        let subject = timetable?.subject(id: atom.subjectId)
        let room = timetable?.room(id: atom.roomId)
        let hour = timetable?.hour(id: atom.hourId)
        let isActive: Bool = {
            if case .active = status { return true }
            return false
        }()

        return NavigationLink {
            LessonDetailView(
                atom: atom,
                day: day,
                subject: subject,
                teacher: timetable?.teacher(id: atom.teacherId),
                room: room,
                hour: hour
            )
        } label: {
            LessonRow(atom: atom, subject: subject, room: room, hour: hour, status: status)
        }
        .listRowBackground(isActive ? Color.green.opacity(0.18) : nil)
    }

    static func lessons(in day: Day) -> [Atom] {
        day.atoms.filter { $0.subjectId != nil || $0.change != nil }
    }

    static func statuses(for lessons: [Atom], in day: Day, timetable: TimetableResponse?, now: Date) -> [Int: LessonStatus] {
        guard let date = BakiDate.parse(day.date), Calendar.current.isDateInToday(date) else { return [:] }

        var result: [Int: LessonStatus] = [:]
        var foundNext = false
        for (index, atom) in lessons.enumerated() {
            guard let hour = timetable?.hour(id: atom.hourId), let dates = hour.dates(on: date) else { continue }
            if dates.end <= now {
                result[index] = .past
            } else if dates.start <= now {
                let total = dates.end.timeIntervalSince(dates.start)
                let progress = total > 0 ? now.timeIntervalSince(dates.start) / total : 0
                let minutesLeft = Int(ceil(dates.end.timeIntervalSince(now) / 60))
                result[index] = .active(progress: progress, minutesLeft: minutesLeft)
            } else if !foundNext && !atom.isCancelled {
                foundNext = true
                result[index] = .next(minutesUntil: Int(ceil(dates.start.timeIntervalSince(now) / 60)))
            }
        }
        return result
    }

    static func isToday(_ day: Day) -> Bool {
        BakiDate.parse(day.date).map(Calendar.current.isDateInToday) ?? false
    }

    private func loadTimetable(offset: Int) async {
        let isCurrentWeek = offset == 0
        let date = isCurrentWeek ? nil : Self.weekInterval(for: offset)?.start
        let response = try? await BakiClient.shared.fetchTimetable(date: date, updatesCache: isCurrentWeek)

        guard !Task.isCancelled else { return }
        if let response {
            weeks[offset] = response
        }
        loadedWeeks.insert(offset)
    }

    static var todayWeekday: Int {
        let weekday = (Calendar.current.component(.weekday, from: Date()) + 5) % 7 + 1
        return weekday >= 6 ? 1 : weekday
    }

    static var todayWeekOffset: Int {
        let weekday = (Calendar.current.component(.weekday, from: Date()) + 5) % 7 + 1
        return weekday >= 6 ? 1 : 0
    }

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        return calendar
    }()

    static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "cs_CZ")
        formatter.dateFormat = "d. M."
        return formatter
    }()

    static func weekInterval(for offset: Int) -> DateInterval? {
        guard let shifted = calendar.date(byAdding: .weekOfYear, value: offset, to: Date()) else { return nil }
        return calendar.dateInterval(of: .weekOfYear, for: shifted)
    }

    static func initialWeeks() -> [Int: TimetableResponse] {
        guard let cached = CredentialStorage.cachedTimetable else { return [:] }
        for offset in [0, 1] {
            if let week = weekInterval(for: offset),
               cached.days.contains(where: { BakiDate.parse($0.date).map(week.contains) == true }) {
                return [offset: cached]
            }
        }
        return [:]
    }

    static func weekTitle(for offset: Int) -> String {
        switch offset {
        case 0: return "Tento týden"
        case 1: return "Příští týden"
        case -1: return "Minulý týden"
        case 2...4: return "Za \(offset) týdny"
        case 5...: return "Za \(offset) týdnů"
        default: return "Před \(-offset) týdny"
        }
    }

    static func weekRangeText(for offset: Int) -> String? {
        guard let start = weekInterval(for: offset)?.start,
              let friday = calendar.date(byAdding: .day, value: 4, to: start) else { return nil }
        return "\(shortDateFormatter.string(from: start)) – \(shortDateFormatter.string(from: friday))"
    }

    private func dayName(for day: Day) -> String {
        BakiDate.weekdayName(dayOfWeek: day.dayOfWeek, date: BakiDate.parse(day.date))
    }
}

struct LessonRow: View {
    let atom: Atom
    let subject: Subject?
    let room: Room?
    let hour: Hour?
    var status: LessonStatus = .none

    private var tint: Color {
        if atom.isCancelled { return .gray }
        if case .active = status { return .green }
        if atom.change != nil { return .orange }
        return .blue
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(hour.map { $0.caption.isEmpty ? "–" : $0.caption } ?? "–")
                .font(.headline.monospacedDigit())
                .foregroundStyle(isActive ? Color.white : tint)
                .frame(width: 36, height: 36)
                .background(
                    isActive ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(tint.opacity(0.18)),
                    in: .rect(cornerRadius: 10, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(subject?.displayName ?? (atom.isCancelled ? "Odpadá" : "Hodina"))
                        .font(.headline)
                        .strikethrough(atom.isCancelled)
                        .foregroundStyle(atom.isCancelled ? .secondary : .primary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    statusLabel
                }

                let details = [room?.displayName, timeRange].compactMap { $0 }
                if !details.isEmpty {
                    Text(details.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let change = atom.change {
                    Text(change.displayDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if case .active(let progress, _) = status {
                    ProgressView(value: min(max(progress, 0), 1))
                        .tint(.green)
                        .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 2)
        .opacity(status == .past ? 0.5 : 1)
    }

    private var isActive: Bool {
        if case .active = status { return true }
        return false
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch status {
        case .active(_, let minutesLeft):
            Text("Probíhá · \(minutesLeft) min")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
        case .next(let minutesUntil):
            Text(minutesUntil < 60 ? "Za \(minutesUntil) min" : "Další")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        case .none, .past:
            EmptyView()
        }
    }

    private var timeRange: String? {
        guard let hour, !hour.beginTime.isEmpty, !hour.endTime.isEmpty else { return nil }
        return "\(hour.beginTime) – \(hour.endTime)"
    }
}

struct TimetableSkeleton: View {
    var body: some View {
        GroupedList {
            ForEach(["Pondělí", "Úterý", "Středa"], id: \.self) { day in
                Section {
                    ForEach(0..<3, id: \.self) { _ in
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Matematika")
                                    .font(.headline)
                                Text("U12 · 08:00 – 08:45")
                                    .font(.subheadline)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text(day)
                        .font(.headline)
                        .textCase(nil)
                }
            }
        }
        .groupedList()
        .skeletonPulse()
    }
}

struct LessonDetailView: View {
    let atom: Atom
    let day: Day
    let subject: Subject?
    let teacher: Teacher?
    let room: Room?
    let hour: Hour?

    private var subjectName: String {
        let name = subject?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let abbrev = subject?.abbrev.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty { return name }
        if !abbrev.isEmpty { return abbrev }
        return "Hodina"
    }

    private var dayLine: String {
        let date = BakiDate.parse(day.date)
        let title = BakiDate.weekdayName(dayOfWeek: day.dayOfWeek, date: date)
        guard date != nil else { return title }
        return "\(title), \(BakiDate.formatCzechDate(day.date))"
    }

    private var timeRange: String? {
        guard let hour, !hour.beginTime.isEmpty, !hour.endTime.isEmpty else { return nil }
        return "\(hour.beginTime) – \(hour.endTime)"
    }

    private var tint: Color {
        if atom.isCancelled { return .gray }
        return atom.change != nil ? .orange : .blue
    }

    var body: some View {
        GroupedList {
            Section {
                VStack(spacing: 12) {
                    VStack(spacing: 0) {
                        Text(hour.map { $0.caption.isEmpty ? "–" : $0.caption } ?? "–")
                            .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                        Text("hodina")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 88, height: 88)
                    .background(tint.gradient, in: .rect(cornerRadius: 24, style: .continuous))

                    VStack(spacing: 4) {
                        Text(subjectName)
                            .font(.title3.weight(.semibold))
                            .strikethrough(atom.isCancelled)
                            .multilineTextAlignment(.center)
                        if let timeRange {
                            Text(timeRange)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if let change = atom.change {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(atom.isCancelled ? "Hodina odpadá" : (change.typeName ?? "Změna rozvrhu"))
                                .font(.headline)
                            if !change.displayDescription.isEmpty {
                                Text(change.displayDescription)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section("Podrobnosti") {
                LabeledContent {
                    Text(dayLine)
                } label: {
                    Label("Den", systemImage: "calendar")
                }

                if let timeRange {
                    LabeledContent {
                        Text(timeRange)
                    } label: {
                        Label("Čas", systemImage: "clock")
                    }
                }

                if let room = room?.displayName {
                    LabeledContent {
                        Text(room)
                    } label: {
                        Label("Místnost", systemImage: "mappin.and.ellipse")
                    }
                }

                if let teacher = teacher?.name {
                    LabeledContent {
                        Text(teacher)
                    } label: {
                        Label("Vyučující", systemImage: "person")
                    }
                }
            }

            if let theme = atom.theme?.trimmingCharacters(in: .whitespacesAndNewlines), !theme.isEmpty {
                Section("Téma") {
                    Text(theme)
                        .textSelection(.enabled)
                }
            }

            if let notice = atom.notice?.trimmingCharacters(in: .whitespacesAndNewlines), !notice.isEmpty {
                Section("Poznámka") {
                    Text(notice)
                        .textSelection(.enabled)
                }
            }
        }
        .groupedList()
        .navigationTitle(subjectName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
