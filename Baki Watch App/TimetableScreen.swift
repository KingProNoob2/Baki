import SwiftUI

struct TimetableScreen: View {
    private static let weekRange = -10...10

    @State private var weekOffset = 0
    @State private var weeks: [Int: TimetableResponse] = Self.initialWeeks()
    @State private var loadedWeeks: Set<Int> = []
    @State private var expandedDays: Set<String> = []
    @State private var pagerSettled = false

    var body: some View {
        ZStack {
            TabView(selection: $weekOffset) {
                ForEach(Self.weekRange, id: \.self) { offset in
                    weekPage(offset: offset)
                        .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .opacity(pagerSettled ? 1 : 0)

            if !pagerSettled {
                weekPage(offset: weekOffset)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .bakiHeader("Rozvrh")
        .task {
            try? await Task.sleep(for: .milliseconds(150))
            pagerSettled = true
        }
        .task(id: weekOffset) {
            await loadTimetable(offset: weekOffset)
            for neighbour in [weekOffset + 1, weekOffset - 1]
            where Self.weekRange.contains(neighbour) && weeks[neighbour] == nil {
                await loadTimetable(offset: neighbour)
            }
        }
        .refreshable {
            await loadTimetable(offset: weekOffset)
        }
    }

    private func weekPage(offset: Int) -> some View {
        weekPageContent(offset: offset)
            .ignoresSafeArea(edges: .top)
    }

    @ViewBuilder
    private func weekPageContent(offset: Int) -> some View {
        let timetable = weeks[offset]
        let days = timetable?.days ?? []

        if timetable == nil && !loadedWeeks.contains(offset) {
            TimetableSkeleton()
        } else {
            List {
                Section {
                    if days.isEmpty {
                        Text("Žádný rozvrh")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                    }

                    ForEach(days) { day in
                        dayRow(day)

                        if expandedDays.contains(day.id) {
                            lessonRows(for: day, in: timetable)
                        }
                    }
                } header: {
                    weekHeader(offset: offset)
                        .padding(.bottom, 4)
                }
            }
            .padding(.top, 55)
        }
    }

    private func weekHeader(offset: Int) -> some View {
        VStack(spacing: 1) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .opacity(offset > Self.weekRange.lowerBound ? 1 : 0)
                Text(Self.weekTitle(for: offset))
                    .font(.headline)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .opacity(offset < Self.weekRange.upperBound ? 1 : 0)
            }
            .accessibilityElement(children: .combine)
            if let range = Self.weekRangeText(for: offset) {
                Text(range)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity)
    }

    private func dayRow(_ day: Day) -> some View {
        let date = BakiDate.parse(day.date)
        let isToday = isDayToday(day)
        let isExpanded = expandedDays.contains(day.id)
        let lessonCount = day.atoms.filter { $0.subjectId != nil || $0.change != nil }.count
        let hasChanges = day.atoms.contains { $0.change != nil }

        return Button {
            withAnimation {
                if isExpanded {
                    expandedDays.remove(day.id)
                } else {
                    expandedDays.insert(day.id)
                }
            }
        } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(dayName(for: day))
                            .font(.headline)
                            .foregroundStyle(isToday ? .orange : .primary)
                        if hasChanges {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.orange)
                                .accessibilityLabel("Změna rozvrhu")
                        }
                    }

                    HStack {
                        if let date {
                            Text(Self.shortDateFormatter.string(from: date))
                        }
                        Spacer(minLength: 0)
                        Text(lessonCount > 0 ? Self.lessonCountText(lessonCount) : "Volno")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                if lessonCount > 0 {
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
            }
        }
        .disabled(lessonCount == 0)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Self.dayAccent(isToday: isToday).opacity(isExpanded ? 0.4 : 0.22))
        )
        .accessibilityHint(isExpanded ? "Skryje hodiny" : "Zobrazí hodiny")
    }

    @ViewBuilder
    private func lessonRows(for day: Day, in timetable: TimetableResponse?) -> some View {
        ForEach(Array(day.atoms.enumerated()), id: \.offset) { _, atom in
            let subject = timetable?.subject(id: atom.subjectId)
            let room = timetable?.room(id: atom.roomId)
            let hour = timetable?.hour(id: atom.hourId)
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
                lessonRow(for: atom, subject: subject, room: room, hour: hour)
            }
            .padding(.leading, 12)
            .listRowBackground(
                HStack(spacing: 4) {
                    Capsule()
                        .fill(atom.change != nil ? Color.orange : Color.gray)
                        .frame(width: 3)
                        .padding(.vertical, 6)
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.gray.opacity(0.1))
                }
                .padding(.leading, 6)
            )
        }
    }

    private func isDayToday(_ day: Day) -> Bool {
        BakiDate.parse(day.date).map(Calendar.current.isDateInToday) ?? false
    }

    private static func dayAccent(isToday: Bool) -> Color {
        isToday ? .orange : .gray
    }

    @ViewBuilder
    private func lessonRow(for atom: Atom, subject: Subject?, room: Room?, hour: Hour?) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    if let subject = subject {
                        Text(subject.displayName)
                            .bold()
                    }
                    if let room = room {
                        Text(room.displayName)
                            .foregroundStyle(.secondary)
                    }
                }

                if let change = atom.change {
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                        Text(change.displayDescription)
                            .font(.caption2)
                    }
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                } else if let theme = atom.theme?.trimmingCharacters(in: .whitespacesAndNewlines), !theme.isEmpty {
                    Text(theme)
                        .font(.caption2)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer()

            if let hour = hour, !hour.caption.isEmpty {
                Text("\(hour.caption).")
                    .bold()
                    .font(.system(size: 25))
            }
        }
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

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        return calendar
    }()

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "cs_CZ")
        formatter.dateFormat = "d. M."
        return formatter
    }()

    private static func weekInterval(for offset: Int) -> DateInterval? {
        guard let shifted = calendar.date(byAdding: .weekOfYear, value: offset, to: Date()) else { return nil }
        return calendar.dateInterval(of: .weekOfYear, for: shifted)
    }

    private static func initialWeeks() -> [Int: TimetableResponse] {
        guard let cached = CredentialStorage.cachedTimetable,
              let thisWeek = weekInterval(for: 0),
              cached.days.contains(where: { BakiDate.parse($0.date).map(thisWeek.contains) == true }) else {
            return [:]
        }
        return [0: cached]
    }

    private static func weekTitle(for offset: Int) -> String {
        switch offset {
        case 0: return "Tento týden"
        case 1: return "Příští týden"
        case -1: return "Minulý týden"
        case 2...4: return "Za \(offset) týdny"
        case 5...: return "Za \(offset) týdnů"
        default: return "Před \(-offset) týdny"
        }
    }

    private static func lessonCountText(_ count: Int) -> String {
        switch count {
        case 1: return "1 hodina"
        case 2...4: return "\(count) hodiny"
        default: return "\(count) hodin"
        }
    }

    private static func weekRangeText(for offset: Int) -> String? {
        guard let start = weekInterval(for: offset)?.start,
              let friday = calendar.date(byAdding: .day, value: 4, to: start) else { return nil }
        return "\(shortDateFormatter.string(from: start)) – \(shortDateFormatter.string(from: friday))"
    }

    private func dayName(for day: Day) -> String {
        BakiDate.weekdayName(dayOfWeek: day.dayOfWeek, date: BakiDate.parse(day.date))
    }
}

struct TimetableSkeleton: View {
    var body: some View {
        List {
            Section {
                ForEach(["Pondělí", "Úterý", "Středa", "Čtvrtek", "Pátek"], id: \.self) { day in
                    HStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(day)
                                .font(.headline)
                            HStack {
                                Text("19. 10.")
                                Spacer(minLength: 0)
                                Text("6 hodin")
                            }
                            .font(.caption2)
                        }
                        Image(systemName: "chevron.down")
                            .font(.footnote.weight(.semibold))
                    }
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.gray.opacity(0.2))
                    )
                }
            } header: {
                VStack(spacing: 1) {
                    Text("Tento týden")
                        .font(.headline)
                    Text("19. 10. – 23. 10.")
                        .font(.caption2)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 4)
            }
        }
        .padding(.top, 55)
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

    private var cleanSubjectName: String {
        let name = subject?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let abbrev = subject?.abbrev.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty {
            return name
        } else if !abbrev.isEmpty {
            return abbrev
        }
        return "Hodina"
    }

    private var subjectAbbrev: String? {
        guard let abbrev = subject?.abbrev.trimmingCharacters(in: .whitespacesAndNewlines), !abbrev.isEmpty,
              let name = subject?.name.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
              name.lowercased() != abbrev.lowercased() else {
            return nil
        }
        return abbrev
    }

    private var dayLine: String {
        let date = BakiDate.parse(day.date)
        let title = BakiDate.weekdayName(dayOfWeek: day.dayOfWeek, date: date)
        guard date != nil else { return title }
        return "\(title), \(BakiDate.formatCzechDate(day.date))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 6) {
                        Text(cleanSubjectName)
                            .font(.headline)
                            .bold()
                            .fixedSize(horizontal: false, vertical: true)

                        if let abbrev = subjectAbbrev {
                            Text(abbrev)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2.5)
                                .background(Color.orange.opacity(0.25))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color.orange.opacity(0.5), lineWidth: 0.5)
                                )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        if let room = room?.displayName {
                            Text(room)
                                .font(.caption2)
                                .bold()
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color.orange.opacity(0.25))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                        Text("Hodina")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }

                    Spacer(minLength: 4)

                    if let hour = hour, !hour.caption.isEmpty {
                        Text("\(hour.caption).")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(.orange)
                            .padding(.trailing, 2)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                if let change = atom.change {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(change.changeType ?? "Změna rozvrhu")
                                .font(.caption)
                                .bold()
                                .foregroundStyle(.orange)

                            if !change.displayDescription.isEmpty {
                                Text(change.displayDescription)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    InfoRow(
                        icon: "calendar",
                        iconColor: .orange,
                        title: "Den",
                        subtitle: dayLine
                    )

                    if let hour = hour {
                        let timeRange = (!hour.beginTime.isEmpty && !hour.endTime.isEmpty) ? "\(hour.beginTime) – \(hour.endTime)" : nil
                        InfoRow(
                            icon: "clock.fill",
                            iconColor: .blue,
                            title: "\(hour.caption). hodina",
                            subtitle: timeRange
                        )
                    }

                    if let room = room?.displayName {
                        InfoRow(
                            icon: "mappin.and.ellipse",
                            iconColor: .red,
                            title: "Místnost",
                            subtitle: room
                        )
                    }

                    if let teacher = teacher?.name {
                        InfoRow(
                            icon: "person.fill",
                            iconColor: .green,
                            title: "Vyučující",
                            subtitle: teacher
                        )
                    }
                }

                if let theme = atom.theme?.trimmingCharacters(in: .whitespacesAndNewlines), !theme.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Image(systemName: "text.book.closed.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("Téma")
                                .font(.caption2)
                                .bold()
                                .foregroundStyle(.secondary)
                        }

                        Text(theme)
                            .font(.body)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let notice = atom.notice?.trimmingCharacters(in: .whitespacesAndNewlines), !notice.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Image(systemName: "info.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("Poznámka")
                                .font(.caption2)
                                .bold()
                                .foregroundStyle(.secondary)
                        }

                        Text(notice)
                            .font(.body)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 12)
        }
    }
}
