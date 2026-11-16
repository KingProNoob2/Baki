#if os(macOS)
import SwiftUI

/// Rozvrh: one day or the whole week in the list column, the selected lesson in the detail column.
struct MacTimetableView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case day = "Den"
        case week = "Týden"

        var id: Self { self }
    }

    @Environment(MacDetailModel.self) private var detail
    @State private var mode: Mode = SavedMode.load("timetable", default: .day)
    @State private var weekOffset = TimetableScreen.todayWeekOffset
    @State private var selectedWeekday = TimetableScreen.todayWeekday
    @State private var weeks: [Int: TimetableResponse] = TimetableScreen.initialWeeks()
    @State private var loadedWeeks: Set<Int> = []
    @State private var selection: String?

    private var days: [Day] { weeks[weekOffset]?.days ?? [] }

    private var currentDay: Day? {
        days.first { $0.dayOfWeek == selectedWeekday } ?? days.first
    }

    private var isShowingToday: Bool {
        weekOffset == TimetableScreen.todayWeekOffset
            && (mode == .week || selectedWeekday == TimetableScreen.todayWeekday)
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
        .macScreen(title: "Rozvrh") {
            MacScreenHeader(title: "Rozvrh", subtitle: TimetableScreen.weekRangeText(for: weekOffset)) {
                if !isShowingToday {
                    Button("Dnes", systemImage: "arrow.uturn.backward") { goToToday() }
                        .buttonStyle(.glass)
                        .controlSize(.regular)
                }
            }
        }
        .toolbar {
            // Week arrows on the left, the day switcher centred in the column, the view menu on the right.
            ToolbarItemGroup {
                Button("Předchozí týden", systemImage: "chevron.left") { changeWeek(by: -1) }
                    .disabled(weekOffset <= TimetableScreen.weekRange.lowerBound)
                Button("Další týden", systemImage: "chevron.right") { changeWeek(by: 1) }
                    .disabled(weekOffset >= TimetableScreen.weekRange.upperBound)
            }
            ToolbarSpacer(.flexible)
            if mode == .day, !days.isEmpty {
                ToolbarItem {
                    Picker("Den", selection: $selectedWeekday) {
                        ForEach(days) { day in
                            Text(String(dayName(day).prefix(2)))
                                .accessibilityLabel(dayName(day))
                                .tag(day.dayOfWeek)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            ToolbarSpacer(.flexible)
            ToolbarItem {
                Menu {
                    Picker("Zobrazení", selection: $mode) {
                        ForEach(Mode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                } label: {
                    Label("Zobrazení", systemImage: mode == .day ? "calendar.day.timeline.left" : "calendar")
                }
            }
        }
        .onChange(of: mode) { SavedMode.save("timetable", mode) }
        .onChange(of: selection) { showSelectedLesson() }
        .focusedSceneValue(\.refreshAction, RefreshAction { Task { await load(offset: weekOffset) } })
        .focusedSceneValue(\.timetableCommands, TimetableCommands(
            previousWeek: weekOffset > TimetableScreen.weekRange.lowerBound ? { changeWeek(by: -1) } : nil,
            nextWeek: weekOffset < TimetableScreen.weekRange.upperBound ? { changeWeek(by: 1) } : nil,
            today: isShowingToday ? nil : { goToToday() }
        ))
        .task(id: weekOffset) {
            await load(offset: weekOffset)
            for neighbour in [weekOffset + 1, weekOffset - 1]
            where TimetableScreen.weekRange.contains(neighbour) && weeks[neighbour] == nil {
                await load(offset: neighbour)
            }
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let timetable = weeks[weekOffset]

        if timetable == nil && !loadedWeeks.contains(weekOffset) {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if days.isEmpty {
            ContentUnavailableView("Žádný rozvrh", systemImage: "calendar")
        } else {
            List(selection: $selection) {
                switch mode {
                case .day:
                    if let day = currentDay {
                        daySection(day, timetable: timetable, now: now)
                    }
                case .week:
                    ForEach(days) { daySection($0, timetable: timetable, now: now) }
                }
            }
            .macList()
        }
    }

    // MARK: Rows

    private func daySection(_ day: Day, timetable: TimetableResponse?, now: Date) -> some View {
        let lessons = TimetableScreen.lessons(in: day)
        let statuses = TimetableScreen.statuses(for: lessons, in: day, timetable: timetable, now: now)

        return Section {
            if lessons.isEmpty {
                Text("Volno")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            }
            ForEach(Array(lessons.enumerated()), id: \.offset) { index, atom in
                let status = statuses[index] ?? .none
                LessonRow(
                    atom: atom,
                    subject: timetable?.subject(id: atom.subjectId),
                    room: timetable?.room(id: atom.roomId),
                    hour: timetable?.hour(id: atom.hourId),
                    status: status
                )
                .padding(.vertical, 4)
                .tag(rowID(day, index))
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isActive(status) ? Color.green.opacity(0.15) : Color.clear)
                        .padding(.horizontal, 6)
                )
            }
        } header: {
            dayHeader(day)
        } footer: {
            if TimetableScreen.isToday(day), !lessons.isEmpty, statuses.values.allSatisfy({ $0 == .past }) {
                Text("Vyučování pro dnešek skončilo.")
            }
        }
    }

    private func dayHeader(_ day: Day) -> some View {
        let isToday = TimetableScreen.isToday(day)
        let date = BakiDate.parse(day.date)
        let hasChanges = day.atoms.contains { $0.change != nil }

        return HStack(spacing: 8) {
            Text(dayName(day))
                .font(.headline)
                .foregroundStyle(isToday ? Color.orange : .primary)
            if let date {
                Text(TimetableScreen.shortDateFormatter.string(from: date))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if isToday {
                Text("Dnes")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.18), in: Capsule())
            }
            Spacer()
            if hasChanges {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Změna rozvrhu")
            }
        }
        .textCase(nil)
        .padding(.vertical, 4)
    }

    private func isActive(_ status: LessonStatus) -> Bool {
        if case .active = status { return true }
        return false
    }

    private func dayName(_ day: Day) -> String {
        BakiDate.weekdayName(dayOfWeek: day.dayOfWeek, date: BakiDate.parse(day.date))
    }

    private func rowID(_ day: Day, _ index: Int) -> String {
        "\(day.date)|\(index)"
    }

    // MARK: Actions

    private func showSelectedLesson() {
        guard let selection,
              let timetable = weeks[weekOffset],
              let day = days.first(where: { selection.hasPrefix($0.date + "|") }),
              let index = Int(selection.dropFirst(day.date.count + 1)) else { return }

        let lessons = TimetableScreen.lessons(in: day)
        guard lessons.indices.contains(index) else { return }
        let atom = lessons[index]

        detail.show(
            id: selection,
            content: AnyView(MacLessonDetail(
                atom: atom,
                day: day,
                subject: timetable.subject(id: atom.subjectId),
                teacher: timetable.teacher(id: atom.teacherId),
                room: timetable.room(id: atom.roomId),
                hour: timetable.hour(id: atom.hourId)
            ))
        )
    }

    private func changeWeek(by delta: Int) {
        let target = weekOffset + delta
        guard TimetableScreen.weekRange.contains(target) else { return }
        withAnimation { weekOffset = target }
    }

    private func goToToday() {
        withAnimation {
            weekOffset = TimetableScreen.todayWeekOffset
            selectedWeekday = TimetableScreen.todayWeekday
        }
    }

    private func ensureValidWeekday() {
        if !days.isEmpty && !days.contains(where: { $0.dayOfWeek == selectedWeekday }) {
            selectedWeekday = days[0].dayOfWeek
        }
    }

    private func load(offset: Int) async {
        let isCurrentWeek = offset == 0
        let date = isCurrentWeek ? nil : TimetableScreen.weekInterval(for: offset)?.start
        let response = try? await BakiClient.shared.fetchTimetable(date: date, updatesCache: isCurrentWeek)

        guard !Task.isCancelled else { return }
        if let response {
            weeks[offset] = response
            if offset == weekOffset {
                ensureValidWeekday()
            }
        }
        loadedWeeks.insert(offset)
    }
}

/// Detail column for a single lesson.
struct MacLessonDetail: View {
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
        MacDetailForm {
            Section {
                MacHero(title: subjectName, subtitle: timeRange) {
                    MacTile(tint: tint) {
                        VStack(spacing: 0) {
                            Text(hour.map { $0.caption.isEmpty ? "–" : $0.caption } ?? "–")
                                .font(.system(size: 42, weight: .bold, design: .rounded).monospacedDigit())
                            Text("hodina")
                                .font(.caption.weight(.semibold))
                        }
                    }
                }
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
        }
        .navigationTitle(subjectName)
    }
}
#endif
