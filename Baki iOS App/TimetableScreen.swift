import SwiftUI

enum LessonStatus: Equatable {
    case none
    case past
    case active(progress: Double, minutesLeft: Int)
    case next(minutesUntil: Int)
}

struct TimetableScreen: View {
    fileprivate enum Mode: String, CaseIterable, Identifiable {
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

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.allowsDuoSplit) private var allowsDuoSplit

    @State private var mode: Mode = SavedMode.load("timetable", default: .day)
    @State private var weekOffset = Self.todayWeekOffset
    @State private var selectedWeekday = Self.todayWeekday
    #if os(iOS)
    @State private var dayScrollPosition = ScrollPosition(id: Self.todayWeekday)
    #endif
    @State private var weeks: [Int: TimetableResponse] = Self.initialWeeks()
    @State private var weekVersions: [Int: Int] = [:]
    @State private var loadedWeeks: Set<Int> = []
    /// Mirrors !isShowingToday but changes inside withAnimation, so only the toolbar animates.
    @State private var showsTodayButton = false
    @State private var selectedLesson: SelectedLesson?

    private struct SelectedLesson: Equatable {
        let day: Day
        let atom: Atom
        let timetable: TimetableResponse?

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.day.id == rhs.day.id && lhs.atom.id == rhs.atom.id
        }
    }

    private var usesDuoSplit: Bool {
        #if os(iOS)
        allowsDuoSplit && DuoEnvironment.isInnerDisplay(
            horizontalSizeClass: horizontalSizeClass,
            verticalSizeClass: verticalSizeClass
        )
        #else
        false
        #endif
    }

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
        }
    }

    var body: some View {
        #if os(iOS)
        DuoAdaptiveSplit(primaryRatio: 0.48) {
            primaryPane
                .duoFloatingOverlay(isVisible: selectedDay != nil) {
                    dayMenuButton
                }
        } primary: {
            primaryPane
                .duoFloatingOverlay(isVisible: selectedDay != nil) {
                    dayMenuButton
                }
        } secondary: {
            detailPane
        }
        .navigationTitle("Rozvrh")
        .duoPrefersTabBarCompression()
        .onChange(of: mode) { SavedMode.save("timetable", mode) }
        .onAppear { showsTodayButton = !isShowingToday }
        .onChange(of: isShowingToday) { _, showing in
            withAnimation { showsTodayButton = !showing }
        }
        .modifier(TimetableToolbarModifier(
            showsTodayButton: showsTodayButton,
            weekOffset: weekOffset,
            mode: $mode,
            goToToday: goToToday,
            changeWeek: changeWeek
        ))
        .task(id: weekOffset) {
            await loadTimetable(offset: weekOffset)
            for neighbour in [weekOffset + 1, weekOffset - 1]
            where Self.weekRange.contains(neighbour) && weeks[neighbour] == nil {
                await loadTimetable(offset: neighbour)
            }
        }
        #else
        primaryPane
            .duoFloatingOverlay(isVisible: selectedDay != nil) {
                dayMenuButton
            }
            .navigationTitle("Rozvrh")
            .onChange(of: mode) { SavedMode.save("timetable", mode) }
            .onAppear { showsTodayButton = !isShowingToday }
            .onChange(of: isShowingToday) { _, showing in
                withAnimation { showsTodayButton = !showing }
            }
            .modifier(TimetableToolbarModifier(
                showsTodayButton: showsTodayButton,
                weekOffset: weekOffset,
                mode: $mode,
                goToToday: goToToday,
                changeWeek: changeWeek
            ))
            .task(id: weekOffset) {
                await loadTimetable(offset: weekOffset)
                for neighbour in [weekOffset + 1, weekOffset - 1]
                where Self.weekRange.contains(neighbour) && weeks[neighbour] == nil {
                    await loadTimetable(offset: neighbour)
                }
            }
        #endif
    }

    private var primaryPane: some View {
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let lesson = resolvedSelectedLesson {
            LessonDetailView(
                atom: lesson.atom,
                day: lesson.day,
                subject: lesson.timetable?.subject(id: lesson.atom.subjectId),
                teacher: lesson.timetable?.teacher(id: lesson.atom.teacherId),
                room: lesson.timetable?.room(id: lesson.atom.roomId),
                hour: lesson.timetable?.hour(id: lesson.atom.hourId),
                isEmbeddedInSplit: true
            )
        } else {
            ContentUnavailableView(
                "Vyberte hodinu",
                systemImage: "calendar",
                description: Text("Klepnutím na hodinu zobrazíte její podrobnosti.")
            )
        }
    }

    private var resolvedSelectedLesson: SelectedLesson? {
        if let selectedLesson {
            return selectedLesson
        }
        guard usesDuoSplit,
              let timetable = weeks[weekOffset],
              let day = selectedDay ?? timetable.days.first(where: { Self.isToday($0) }) ?? timetable.days.first else {
            return nil
        }
        let lessons = Self.lessons(in: day)
        guard !lessons.isEmpty else { return nil }
        let statuses = Self.statuses(for: lessons, in: day, timetable: timetable, now: Date())
        let preferredIndex = lessons.indices.first {
            if case .active = statuses[$0] { return true }
            return false
        } ?? lessons.indices.first {
            if case .next = statuses[$0] { return true }
            return false
        } ?? 0
        return SelectedLesson(day: day, atom: lessons[preferredIndex], timetable: timetable)
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

    @ViewBuilder
    private func dayList(days: [Day], timetable: TimetableResponse?, now: Date) -> some View {
        #if os(iOS)
        let activeWeekday = days.contains { $0.dayOfWeek == selectedWeekday } ? selectedWeekday : days[0].dayOfWeek

        // Split the standard 16pt inset evenly between the pager's contentMargins (8pt)
        // and each day's List contentMargins (8pt) so edge margins (Mo/Fri) and gaps
        // between adjacent days are all identically 16pt.
        let version = weekVersions[weekOffset] ?? 0
        let minuteBucket = Int(now.timeIntervalSinceReferenceDate / 60)

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(days, id: \.dayOfWeek) { day in
                    EquatableDayPage(
                        dayID: day.id,
                        weekOffset: weekOffset,
                        version: version,
                        minuteBucket: minuteBucket,
                        selectedLessonID: usesDuoSplit ? selectedLesson?.atom.id : nil
                    ) {
                        dayListBody(day, timetable: timetable, now: now)
                            .contentMargins(.horizontal, 8, for: .scrollContent)
                    }
                    .equatable()
                    .containerRelativeFrame(.horizontal)
                }
            }
            .background {
                NavigationContentScrollViewBridge(activeWeekday: activeWeekday, dayCount: days.count)
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, 8, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
        .scrollPosition($dayScrollPosition)
        .onAppear {
            dayScrollPosition.scrollTo(id: activeWeekday)
        }
        .onChange(of: dayScrollPosition.viewID(type: Int.self)) { _, newValue in
            if let newValue, newValue != selectedWeekday {
                selectedWeekday = newValue
            }
        }
        .onChange(of: selectedWeekday) { _, newValue in
            let target = days.contains { $0.dayOfWeek == newValue } ? newValue : days[0].dayOfWeek
            if dayScrollPosition.viewID(type: Int.self) != target {
                withAnimation {
                    dayScrollPosition.scrollTo(id: target)
                }
            }
        }
        .onChange(of: weekOffset) { _, _ in
            dayScrollPosition.scrollTo(id: activeWeekday)
        }
        #else
        let day = days.first { $0.dayOfWeek == selectedWeekday } ?? days[0]
        dayListBody(day, timetable: timetable, now: now)
        #endif
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

    @ViewBuilder
    private func lessonLink(for atom: Atom, in day: Day, timetable: TimetableResponse?, status: LessonStatus) -> some View {
        let subject = timetable?.subject(id: atom.subjectId)
        let room = timetable?.room(id: atom.roomId)
        let hour = timetable?.hour(id: atom.hourId)
        let isActive: Bool = {
            if case .active = status { return true }
            return false
        }()

        if usesDuoSplit {
            let candidate = SelectedLesson(day: day, atom: atom, timetable: timetable)
            let isSelected = resolvedSelectedLesson == candidate

            Button {
                selectedLesson = candidate
            } label: {
                LessonRow(atom: atom, subject: subject, room: room, hour: hour, status: status)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(
                isSelected
                    ? Color.accentColor.opacity(0.14)
                    : (isActive ? Color.green.opacity(0.18) : nil)
            )
        } else {
            NavigationLink {
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
            weekVersions[offset, default: 0] += 1
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
    var isEmbeddedInSplit: Bool = false

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
        .duoDetailNavigationTitle(subjectName, isEmbeddedInSplit: isEmbeddedInSplit)
    }
}

private struct TimetableToolbarModifier: ViewModifier {
    let showsTodayButton: Bool
    let weekOffset: Int
    @Binding var mode: TimetableScreen.Mode
    let goToToday: () -> Void
    let changeWeek: (Int) -> Void

    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 27.1, *) {
            TimetableToolbar27_1(
                showsTodayButton: showsTodayButton,
                weekOffset: weekOffset,
                mode: $mode,
                goToToday: goToToday,
                changeWeek: changeWeek,
                content: content
            )
        } else {
            legacyToolbar(content: content)
        }
        #else
        legacyToolbar(content: content)
        #endif
    }

    private func legacyToolbar(content: Content) -> some View {
        content.toolbar {
            if showsTodayButton {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Dnes") { goToToday() }
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Předchozí týden", systemImage: "chevron.left") {
                    changeWeek(-1)
                }
                .disabled(weekOffset <= TimetableScreen.weekRange.lowerBound)
                Button("Další týden", systemImage: "chevron.right") {
                    changeWeek(1)
                }
                .disabled(weekOffset >= TimetableScreen.weekRange.upperBound)
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Zobrazení", selection: $mode) {
                        ForEach(TimetableScreen.Mode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.systemImage).tag(mode)
                        }
                    }
                } label: {
                    Label("Zobrazení", systemImage: mode.systemImage)
                }
            }
        }
    }
}

#if os(iOS)
@available(iOS 27.1, *)
private struct TimetableToolbar27_1<BaseContent: View>: View {
    let showsTodayButton: Bool
    let weekOffset: Int
    @Binding var mode: TimetableScreen.Mode
    let goToToday: () -> Void
    let changeWeek: (Int) -> Void
    let content: BaseContent

    @Environment(\.toolbarVerticalEdge) private var toolbarVerticalEdge

    var body: some View {
        if toolbarVerticalEdge != nil {
            content.toolbar {
                if showsTodayButton {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Dnes", systemImage: "arrow.uturn.backward") {
                            goToToday()
                        }
                    }
                    .visibilityPriority(.low)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Předchozí týden", systemImage: "chevron.left") {
                        changeWeek(-1)
                    }
                    .disabled(weekOffset <= TimetableScreen.weekRange.lowerBound)
                    Button("Další týden", systemImage: "chevron.right") {
                        changeWeek(1)
                    }
                    .disabled(weekOffset >= TimetableScreen.weekRange.upperBound)
                }
                .visibilityPriority(.high)
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Zobrazení", selection: $mode) {
                            ForEach(TimetableScreen.Mode.allCases) { mode in
                                Label(mode.rawValue, systemImage: mode.systemImage).tag(mode)
                            }
                        }
                    } label: {
                        Label("Zobrazení", systemImage: mode.systemImage)
                    }
                }
                .visibilityPriority(.high)
            }
        } else {
            content.toolbar {
                if showsTodayButton {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Dnes") { goToToday() }
                    }
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Předchozí týden", systemImage: "chevron.left") {
                        changeWeek(-1)
                    }
                    .disabled(weekOffset <= TimetableScreen.weekRange.lowerBound)
                    Button("Další týden", systemImage: "chevron.right") {
                        changeWeek(1)
                    }
                    .disabled(weekOffset >= TimetableScreen.weekRange.upperBound)
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Zobrazení", selection: $mode) {
                            ForEach(TimetableScreen.Mode.allCases) { mode in
                                Label(mode.rawValue, systemImage: mode.systemImage).tag(mode)
                            }
                        }
                    } label: {
                        Label("Zobrazení", systemImage: mode.systemImage)
                    }
                }
            }
        }
    }
}
#endif

/// Prevents all 5 day lists from re-evaluating their bodies when unrelated state
/// (such as `selectedWeekday` or toolbar `showsTodayButton`) changes mid-swipe.
private struct EquatableDayPage<Content: View>: View, Equatable {
    let dayID: String
    let weekOffset: Int
    let version: Int
    let minuteBucket: Int
    let selectedLessonID: String?
    let content: () -> Content

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.dayID == rhs.dayID
            && lhs.weekOffset == rhs.weekOffset
            && lhs.version == rhs.version
            && lhs.minuteBucket == rhs.minuteBucket
            && lhs.selectedLessonID == rhs.selectedLessonID
    }

    var body: some View {
        content()
    }
}

#if os(iOS)
import UIKit

/// Tells the enclosing `UINavigationController`'s page controller to track the currently visible
/// day's vertical `List` (`UICollectionView`) as its content scroll view, and keeps that binding
/// synced as the user swipes between days or scrolls vertically — without per-frame view traversal.
private struct NavigationContentScrollViewBridge: UIViewRepresentable {
    let activeWeekday: Int
    let dayCount: Int

    func makeUIView(context: Context) -> BridgeView {
        let view = BridgeView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: BridgeView, context: Context) {
        uiView.update(activeWeekday: activeWeekday, dayCount: dayCount)
    }

    final class BridgeView: UIView {
        private weak var cachedVC: UIViewController?
        private weak var cachedPager: UIScrollView?
        private weak var attachedScrollView: UIScrollView?
        private var cachedCollectionViews: [UICollectionView] = []
        private var dayObservations: [ObjectIdentifier: NSKeyValueObservation] = [:]
        private var lastDayCount = -1
        private var lastActiveWeekday = -1
        private var syncScheduled = false

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil {
                teardown()
            } else {
                scheduleSync(forceRescan: true)
            }
        }

        func update(activeWeekday: Int, dayCount: Int) {
            let countChanged = dayCount != lastDayCount
            let dayChanged = activeWeekday != lastActiveWeekday
            lastDayCount = dayCount
            lastActiveWeekday = activeWeekday
            if countChanged || dayChanged || cachedCollectionViews.isEmpty {
                scheduleSync(forceRescan: countChanged || cachedCollectionViews.isEmpty)
            }
        }

        private func scheduleSync(forceRescan: Bool) {
            guard window != nil else { return }
            if forceRescan {
                cachedCollectionViews.removeAll()
            }
            guard !syncScheduled else { return }
            syncScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.syncScheduled = false
                guard self.window != nil else { return }
                self.refreshObserversAndAttach()
            }
        }

        private func teardown() {
            dayObservations.values.forEach { $0.invalidate() }
            dayObservations.removeAll()
            cachedCollectionViews.removeAll()
            cachedPager = nil

            if let vc = cachedVC, let sv = attachedScrollView, vc.contentScrollView(for: .top) === sv {
                vc.setContentScrollView(nil, for: [.top, .bottom])
            }
            cachedVC = nil
            attachedScrollView = nil
        }

        private func refreshObserversAndAttach() {
            guard let pager = cachedPager ?? enclosingPagerScrollView(),
                  let vc = cachedVC ?? enclosingNavigationPageController() else { return }
            cachedPager = pager
            cachedVC = vc

            if cachedCollectionViews.isEmpty || cachedCollectionViews.contains(where: { $0.window == nil }) {
                cachedCollectionViews = allCollectionViews(in: pager)
                let currentIDs = Set(cachedCollectionViews.map(ObjectIdentifier.init))
                for (id, obs) in dayObservations where !currentIDs.contains(id) {
                    obs.invalidate()
                    dayObservations.removeValue(forKey: id)
                }
                for cv in cachedCollectionViews {
                    let id = ObjectIdentifier(cv)
                    if dayObservations[id] == nil {
                        dayObservations[id] = cv.observe(\.contentOffset, options: [.new]) { [weak self, weak cv] _, _ in
                            MainActor.assumeIsolated {
                                guard let self, let cv else { return }
                                // O(1) fast path: skip all work when already attached to this List.
                                if self.attachedScrollView === cv, self.cachedVC?.contentScrollView(for: .top) === cv {
                                    return
                                }
                                self.attach(cv)
                            }
                        }
                    }
                }
            }

            syncCenteredScrollView(pager: pager, vc: vc)
        }

        private func syncCenteredScrollView(pager: UIScrollView, vc: UIViewController) {
            guard pager.bounds.width > 0, !cachedCollectionViews.isEmpty else { return }
            let visibleCenterX = pager.contentOffset.x + pager.bounds.width * 0.5
            guard let activeCV = cachedCollectionViews.min(by: { lhs, rhs in
                let lDist = abs(lhs.convert(lhs.bounds, to: pager).midX - visibleCenterX)
                let rDist = abs(rhs.convert(rhs.bounds, to: pager).midX - visibleCenterX)
                return lDist < rDist
            }) else { return }

            attach(activeCV, vc: vc)
        }

        private func attach(_ cv: UICollectionView, vc: UIViewController? = nil) {
            guard let targetVC = vc ?? cachedVC ?? enclosingNavigationPageController() else { return }
            cachedVC = targetVC
            if targetVC.contentScrollView(for: .top) !== cv {
                targetVC.setContentScrollView(cv, for: [.top, .bottom])
                targetVC.navigationController?.navigationBar.setNeedsLayout()
            }
            attachedScrollView = cv
        }

        private func enclosingNavigationPageController() -> UIViewController? {
            var responder: UIResponder? = next
            while let current = responder {
                if let vc = current as? UIViewController, let nav = vc.navigationController {
                    if let pageVC = nav.viewControllers.last(where: { self.isDescendant(of: $0.view) }) {
                        return pageVC
                    }
                    return nav.topViewController ?? vc
                }
                responder = current.next
            }
            return nil
        }

        private func enclosingPagerScrollView() -> UIScrollView? {
            var node: UIView? = superview
            while let current = node {
                if let scrollView = current as? UIScrollView, !(current is UICollectionView) {
                    return scrollView
                }
                node = current.superview
            }
            return nil
        }

        private func allCollectionViews(in root: UIView) -> [UICollectionView] {
            var result: [UICollectionView] = []
            for child in root.subviews {
                if let collectionView = child as? UICollectionView {
                    result.append(collectionView)
                } else {
                    result.append(contentsOf: allCollectionViews(in: child))
                }
            }
            return result
        }
    }
}
#endif
