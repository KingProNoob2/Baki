import SwiftUI

enum AbsenceKind: CaseIterable {
    case ok, missed, unsolved, late, soon, school, distanceTeaching

    var title: String {
        switch self {
        case .ok: return "Omluvené"
        case .missed: return "Neomluvené"
        case .unsolved: return "Nevyřízené"
        case .late: return "Pozdní příchody"
        case .soon: return "Brzké odchody"
        case .school: return "Školní akce"
        case .distanceTeaching: return "Distanční výuka"
        }
    }

    var shortTitle: String {
        switch self {
        case .ok: return "omluveno"
        case .missed: return "neomluveno"
        case .unsolved: return "nevyřízeno"
        case .late: return "pozdě"
        case .soon: return "odchod"
        case .school: return "akce"
        case .distanceTeaching: return "distančně"
        }
    }

    var color: Color {
        switch self {
        case .ok: return .green
        case .missed: return .red
        case .unsolved: return .orange
        case .late, .soon: return .yellow
        case .school: return .blue
        case .distanceTeaching: return .purple
        }
    }

    var systemImage: String {
        switch self {
        case .ok: return "checkmark.circle"
        case .missed: return "xmark.circle"
        case .unsolved: return "questionmark.circle"
        case .late: return "clock.badge.exclamationmark"
        case .soon: return "figure.walk.departure"
        case .school: return "building.columns"
        case .distanceTeaching: return "laptopcomputer"
        }
    }

    func count(in day: AbsenceDay) -> Int {
        switch self {
        case .ok: return day.ok
        case .missed: return day.missed
        case .unsolved: return day.unsolved
        case .late: return day.late
        case .soon: return day.soon
        case .school: return day.school
        case .distanceTeaching: return day.distanceTeaching
        }
    }
}

struct AbsenceScreen: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case days = "Dny"
        case subjects = "Předměty"

        var id: Self { self }

        var systemImage: String {
            switch self {
            case .days: return "calendar"
            case .subjects: return "square.stack"
            }
        }
    }

    @State private var response: AbsenceResponse?
    @State private var isLoading = false
    @State private var mode: Mode = SavedMode.load("absence", default: .days)

    private var days: [AbsenceDay] {
        (response?.absences ?? [])
            .filter { !$0.isEmpty }
            .sorted { ($0.parsedDate ?? .distantPast) > ($1.parsedDate ?? .distantPast) }
    }

    private var subjects: [SubjectAbsence] {
        (response?.absencesPerSubject ?? []).sorted { $0.percentage > $1.percentage }
    }

    private var threshold: Double? { response?.percentageThreshold }

    var body: some View {
        Group {
            if response == nil && isLoading {
                ProgressView()
            } else if response == nil {
                ContentUnavailableView {
                    Label("Absenci se nepodařilo načíst", systemImage: "exclamationmark.triangle")
                } actions: {
                    Button("Zkusit znovu") { Task { await load() } }
                }
            } else {
                #if os(iOS)
                DuoAdaptiveSplit(primaryRatio: 0.42) {
                    list
                } primary: {
                    summaryList
                } secondary: {
                    detailsList
                }
                #else
                list
                #endif
            }
        }
        .navigationTitle("Absence")
        .onChange(of: mode) { SavedMode.save("absence", mode) }
        .toolbar {
            if !subjects.isEmpty {
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
        }
        .task {
            guard response == nil else { return }
            await load()
        }
        .refreshable { await load() }
    }

    private var list: some View {
        GroupedList {
            // On the Mac the totals live in the window's detail column instead.
            Section {
                summary
                    .plainGroupedRow()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            switch subjects.isEmpty ? .days : mode {
            case .days:
                daysSection
            case .subjects:
                subjectsSection
            }
        }
        .groupedList()
    }

    #if os(iOS)
    private var summaryList: some View {
        GroupedList {
            Section {
                summary
                    .plainGroupedRow()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
        .groupedList()
    }

    private var detailsList: some View {
        GroupedList {
            switch subjects.isEmpty ? .days : mode {
            case .days:
                daysSection
            case .subjects:
                subjectsSection
            }
        }
        .groupedList()
    }
    #endif

    private var summary: some View {
        let allDays = response?.absences ?? []
        let totals = AbsenceKind.allCases
            .map { kind in (kind, allDays.reduce(0) { $0 + kind.count(in: $1) }) }
            .filter { $0.1 > 0 }

        return Group {
            if totals.isEmpty {
                Label("Žádná absence", systemImage: "checkmark.seal")
                    .font(.headline)
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(totals, id: \.0) { kind, total in
                        VStack(alignment: .leading, spacing: 4) {
                            Image(systemName: kind.systemImage)
                                .font(.headline)
                                .foregroundStyle(kind.color)
                            Text("\(total)")
                                .font(.title.bold().monospacedDigit())
                            Text(kind.title)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .cardBackground(grouped: true)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var daysSection: some View {
        if days.isEmpty {
            Section {
                Text("Žádné zameškané hodiny")
                    .foregroundStyle(.secondary)
            }
        } else {
            Section("Podle dnů") {
                ForEach(days) { day in
                    dayRow(day)
                }
            }
        }
    }

    private func dayRow(_ day: AbsenceDay) -> some View {
        let date = day.parsedDate
        let kinds = AbsenceKind.allCases.filter { $0.count(in: day) > 0 }

        return VStack(alignment: .leading, spacing: 6) {
            if let date {
                Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "cs_CZ"))).capitalizedFirstLetter)
                    .font(.headline)
            } else {
                Text(day.date)
                    .font(.headline)
            }

            HStack(spacing: 6) {
                ForEach(kinds, id: \.self) { kind in
                    Text("\(kind.count(in: day)) \(kind.shortTitle)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(kind.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(kind.color.opacity(0.15), in: Capsule())
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var subjectsSection: some View {
        Section {
            ForEach(subjects) { subject in
                subjectRow(subject)
            }
        } header: {
            Text("Podle předmětů")
        } footer: {
            if let threshold {
                Text("Limit absence je \(threshold.formatted(.percent.precision(.fractionLength(0)))) hodin předmětu.")
            }
        }
    }

    private func subjectRow(_ subject: SubjectAbsence) -> some View {
        let overLimit = threshold.map { subject.percentage >= $0 } ?? false
        let nearLimit = threshold.map { subject.percentage >= $0 * 0.75 } ?? false
        let color: Color = overLimit ? .red : (nearLimit ? .orange : .green)

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(subject.subjectName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(subject.percentage.formatted(.percent.precision(.fractionLength(0))))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(color)
            }

            ProgressView(value: Double(subject.base), total: Double(max(subject.lessonsCount, 1)))
                .tint(color)

            HStack(spacing: 12) {
                Text("\(subject.base) z \(subject.lessonsCount) hodin")
                if subject.late > 0 {
                    Text("\(subject.late)× pozdě")
                }
                if subject.soon > 0 {
                    Text("\(subject.soon)× odchod")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }


    private func load() async {
        isLoading = true
        defer { isLoading = false }
        if let fetched = try? await BakiClient.shared.fetchAbsence() {
            response = fetched
        }
    }
}

extension String {
    var capitalizedFirstLetter: String {
        prefix(1).uppercased() + dropFirst()
    }
}
