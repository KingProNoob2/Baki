#if os(macOS)
import SwiftUI

/// Absence: absence by day or by subject in the list column, the totals in the detail column.
struct MacAbsenceView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case days = "Dny"
        case subjects = "Předměty"

        var id: Self { self }
    }

    @Environment(MacDetailModel.self) private var detail
    @State private var response: AbsenceResponse?
    @State private var isLoading = false
    @State private var loaded = false
    @State private var loadFailed = false
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

    private var totals: [(AbsenceKind, Int)] {
        let allDays = response?.absences ?? []
        return AbsenceKind.allCases
            .map { kind in (kind, allDays.reduce(0) { $0 + kind.count(in: $1) }) }
            .filter { $0.1 > 0 }
    }

    var body: some View {
        Group {
            if response == nil && (!loaded || isLoading) {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if response == nil && loadFailed {
                ContentUnavailableView {
                    Label("Absenci se nepodařilo načíst", systemImage: "exclamationmark.triangle")
                } actions: {
                    Button("Zkusit znovu") { Task { await load() } }
                }
            } else if response == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
            }
        }
        .macScreen(title: "Absence") {
            MacScreenHeader(title: "Absence", subtitle: response == nil ? nil : subtitle)
        }
        .toolbar {
            if !subjects.isEmpty {
                ToolbarItem {
                    Picker("Zobrazení", selection: $mode) {
                        ForEach(Mode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
        .onChange(of: mode) { SavedMode.save("absence", mode) }
        .focusedSceneValue(\.refreshAction, RefreshAction { Task { await load() } })
        .task {
            guard response == nil else { return }
            await load()
        }
    }

    private var subtitle: String {
        totals.isEmpty ? "Žádná absence" : totals.map { "\($0.1) \($0.0.shortTitle)" }.joined(separator: " · ")
    }

    private var list: some View {
        List {
            switch subjects.isEmpty ? .days : mode {
            case .days:
                if days.isEmpty {
                    Text("Žádné zameškané hodiny")
                        .foregroundStyle(.secondary)
                } else {
                    Section("Podle dnů") {
                        ForEach(days) { dayRow($0) }
                    }
                }
            case .subjects:
                Section {
                    ForEach(subjects) { subjectRow($0) }
                } header: {
                    Text("Podle předmětů")
                } footer: {
                    if let threshold {
                        Text("Limit absence je \(threshold.formatted(.percent.precision(.fractionLength(0)))) hodin předmětu.")
                    }
                }
            }
        }
        .macList()
    }

    private func dayRow(_ day: AbsenceDay) -> some View {
        let kinds = AbsenceKind.allCases.filter { $0.count(in: day) > 0 }

        return VStack(alignment: .leading, spacing: 8) {
            if let date = day.parsedDate {
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
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private func subjectRow(_ subject: SubjectAbsence) -> some View {
        let overLimit = threshold.map { subject.percentage >= $0 } ?? false
        let nearLimit = threshold.map { subject.percentage >= $0 * 0.75 } ?? false
        let color: Color = overLimit ? .red : (nearLimit ? .orange : .green)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(subject.subjectName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(subject.percentage.formatted(.percent.precision(.fractionLength(0))))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(color)
            }

            let totalLessons = Double(max(subject.lessonsCount, 1))
            ProgressView(value: min(Double(max(subject.base, 0)), totalLessons), total: totalLessons)
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
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    /// Totals per kind, shown in the detail column once the data has loaded.
    private var summaryPanel: some View {
        MacDetailForm {
            Section {
                MacHero(title: totals.isEmpty ? "Žádná absence" : "Souhrn absence") {
                    MacTile(tint: totals.isEmpty ? .green : .pink) {
                        Image(systemName: totals.isEmpty ? "checkmark.seal" : "person.badge.clock")
                            .font(.system(size: 40, weight: .semibold))
                    }
                }
            }

            if !totals.isEmpty {
                Section("Celkem") {
                    ForEach(totals, id: \.0) { kind, total in
                        LabeledContent {
                            Text("\(total)")
                                .font(.title3.weight(.semibold).monospacedDigit())
                        } label: {
                            Label(kind.title, systemImage: kind.systemImage)
                                .foregroundStyle(kind.color)
                        }
                    }
                }
            }
        }
        .navigationTitle("Absence")
    }

    private func load() async {
        isLoading = true
        defer {
            isLoading = false
            loaded = true
        }
        do {
            let fetched = try await BakiClient.shared.fetchAbsence()
            response = fetched
            loadFailed = false
            detail.show(id: "summary", content: AnyView(summaryPanel))
        } catch {
            if response == nil { loadFailed = true }
        }
    }
}
#endif
