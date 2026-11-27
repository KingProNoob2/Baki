import SwiftUI

struct SubjectMark: Identifiable, Equatable {
    var id: String { mark.id }
    let mark: Mark
    let subject: Subject
    let averageText: String?
    let subjectNote: String?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.mark.id == rhs.mark.id && lhs.subject.id == rhs.subject.id
    }
}

struct MarksScreen: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case subjects = "Předměty"
        case recent = "Nejnovější"

        var id: Self { self }

        var systemImage: String {
            switch self {
            case .subjects: return "square.stack"
            case .recent: return "clock"
            }
        }
    }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.allowsDuoSplit) private var allowsDuoSplit

    @State private var subjects: [SubjectMarks] = []
    @State private var recentMarks: [SubjectMark] = []
    @State private var isLoading: Bool = false
    @State private var loadFailed: Bool = false
    @State private var mode: Mode = SavedMode.load("marks", default: .subjects)
    @State private var expandedSubjects: Set<String> = []
    @State private var selectedMark: SubjectMark?

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

    private var resolvedSelectedMark: SubjectMark? {
        selectedMark ?? recentMarks.first
    }

    var body: some View {
        Group {
            if subjects.isEmpty && isLoading {
                MarksSkeleton()
            } else if subjects.isEmpty && loadFailed {
                ContentUnavailableView {
                    Label("Známky se nepodařilo načíst", systemImage: "exclamationmark.triangle")
                } actions: {
                    Button("Zkusit znovu") { Task { await loadMarks() } }
                }
            } else if subjects.isEmpty {
                ContentUnavailableView("Žádné známky", systemImage: "list.number")
            } else {
                #if os(iOS)
                DuoAdaptiveSplit(primaryRatio: 0.45) {
                    marksList
                } primary: {
                    marksList
                } secondary: {
                    detailPane
                }
                #else
                marksList
                #endif
            }
        }
        .navigationTitle("Známky")
        .duoPrefersTabBarCompression()
        .onChange(of: mode) { SavedMode.save("marks", mode) }
        .toolbar {
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
        .task {
            await loadMarks()
        }
        .refreshable {
            await loadMarks()
        }
    }

    private var marksList: some View {
        GroupedList {
            switch mode {
            case .subjects:
                subjectSections
            case .recent:
                Section {
                    recentRows
                }
            }
        }
        .groupedList()
        .listSectionSpacing(.compact)
    }

    @ViewBuilder
    private var detailPane: some View {
        if let item = resolvedSelectedMark {
            MarkDetailView(
                mark: item.mark,
                subject: item.subject,
                averageText: item.averageText,
                subjectNote: item.subjectNote,
                isEmbeddedInSplit: true
            )
        } else {
            ContentUnavailableView(
                "Vyberte známku",
                systemImage: "list.number",
                description: Text("Klepnutím na známku zobrazíte její podrobnosti.")
            )
        }
    }

    private var subjectSections: some View {
        ForEach(subjects) { item in
            Section {
                if item.marks.isEmpty {
                    subjectLabel(item)
                } else {
                    DisclosureGroup(isExpanded: expansionBinding(for: item.id)) {
                        ForEach(item.marks) { mark in
                            let entry = SubjectMark(
                                mark: mark,
                                subject: item.subject,
                                averageText: item.averageText,
                                subjectNote: item.subjectNote
                            )
                            markLink(entry: entry) {
                                markRow(mark)
                            }
                        }
                    } label: {
                        subjectLabel(item)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func markLink<RowContent: View>(
        entry: SubjectMark,
        @ViewBuilder label: () -> RowContent
    ) -> some View {
        if usesDuoSplit {
            let isSelected = resolvedSelectedMark == entry
            Button {
                selectedMark = entry
            } label: {
                label()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(isSelected ? Color.accentColor.opacity(0.14) : nil)
        } else {
            NavigationLink {
                MarkDetailView(
                    mark: entry.mark,
                    subject: entry.subject,
                    averageText: entry.averageText,
                    subjectNote: entry.subjectNote
                )
            } label: {
                label()
            }
        }
    }


    private func expansionBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { expandedSubjects.contains(id) },
            set: { isExpanded in
                if isExpanded {
                    expandedSubjects.insert(id)
                } else {
                    expandedSubjects.remove(id)
                }
            }
        )
    }

    private func subjectLabel(_ item: SubjectMarks) -> some View {
        let hasNewMarks = item.marks.contains { $0.isNew == true }
        let average = item.averageText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = item.subject.name.isEmpty ? item.subject.abbrev : item.subject.name

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.headline)
                        .lineLimit(1)
                    if hasNewMarks {
                        NewMarkDot()
                    }
                }

                Text(item.marks.isEmpty ? "Bez známek" : Self.markCountText(item.marks.count))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if !average.isEmpty {
                let averageBadge = Text("Ø \(average)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(MarkColor.forAverage(average))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                averageBadge
                    .background(MarkColor.forAverage(average).opacity(0.18), in: Capsule())
                    .accessibilityLabel("Průměr \(average)")
            }
        }
        .padding(.vertical, 4)
    }

    private func markRow(_ mark: Mark) -> some View {
        let caption = mark.caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let theme = mark.theme?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return HStack(spacing: 12) {
            MarkBadge(text: mark.displayText)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(caption.isEmpty ? "Známka" : caption)
                        .font(.body.weight(.medium))
                        .lineLimit(2)
                    if mark.isNew == true {
                        NewMarkDot()
                    }
                }
                if !theme.isEmpty && theme != caption {
                    Text(theme)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let dateStr = mark.markDate {
                    Text(BakiDate.formatCzechDate(dateStr))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var recentRows: some View {
        ForEach(recentMarks) { item in
            markLink(entry: item) {
                recentRow(item)
            }
        }
    }

    private func recentRow(_ item: SubjectMark) -> some View {
        let caption = item.mark.caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return HStack(spacing: 12) {
            MarkBadge(text: item.mark.displayText)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.subject.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    if item.mark.isNew == true {
                        NewMarkDot()
                    }
                }

                Text(caption.isEmpty ? "Známka" : caption)
                    .font(.subheadline)
                    .lineLimit(1)

                if let dateStr = item.mark.markDate {
                    Text(BakiDate.formatCzechDate(dateStr))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    static func isNewer(_ a: (mark: Mark, date: Date), _ b: (mark: Mark, date: Date)) -> Bool {
        if a.date != b.date { return a.date > b.date }
        let new1 = a.mark.isNew == true
        let new2 = b.mark.isNew == true
        if new1 != new2 { return new1 }
        return a.mark.id > b.mark.id
    }

    static func sortedNewestFirst(_ item: SubjectMarks) -> SubjectMarks {
        let sorted = item.marks
            .map { (mark: $0, date: $0.parsedDate ?? .distantPast) }
            .sorted { Self.isNewer($0, $1) }
            .map(\.mark)

        return SubjectMarks(
            marks: sorted,
            subject: item.subject,
            averageText: item.averageText,
            subjectNote: item.subjectNote,
            temporaryMarkNote: item.temporaryMarkNote,
            pointsOnly: item.pointsOnly,
            markPredictionEnabled: item.markPredictionEnabled
        )
    }

    static func makeRecentMarks(from subjects: [SubjectMarks]) -> [SubjectMark] {
        subjects
            .flatMap { subject in
                subject.marks.map { mark in
                    (
                        item: SubjectMark(
                            mark: mark,
                            subject: subject.subject,
                            averageText: subject.averageText,
                            subjectNote: subject.subjectNote
                        ),
                        date: mark.parsedDate ?? Date.distantPast
                    )
                }
            }
            .sorted { Self.isNewer(($0.item.mark, $0.date), ($1.item.mark, $1.date)) }
            .map(\.item)
    }

    static func markCountText(_ count: Int) -> String {
        switch count {
        case 1: return "1 známka"
        case 2...4: return "\(count) známky"
        default: return "\(count) známek"
        }
    }

    private func loadMarks() async {
        isLoading = true
        do {
            let response = try await BakiClient.shared.fetchMarks()
            subjects = response.subjects.map { Self.sortedNewestFirst($0) }
            recentMarks = Self.makeRecentMarks(from: subjects)
            loadFailed = false
        } catch {
            if subjects.isEmpty { loadFailed = true }
        }
        isLoading = false
    }
}

struct MarksSkeleton: View {
    static let subjects = ["Matematika", "Český jazyk", "Anglický jazyk", "Fyzika", "Chemie"]

    var body: some View {
        GroupedList {
            ForEach(Self.subjects, id: \.self) { subject in
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(subject)
                                .font(.headline)
                            Text("5 známek")
                                .font(.subheadline)
                        }
                        Spacer()
                        Text("Ø 1.50")
                            .font(.subheadline)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .groupedList()
        .listSectionSpacing(.compact)
        .skeletonPulse()
    }
}

enum MarkColor {
    static func forGrade(_ grade: Double) -> Color {
        switch grade {
        case ..<1.5: return .green
        case ..<2.5: return .teal
        case ..<3.5: return .yellow
        case ..<4.5: return .orange
        default: return .red
        }
    }

    static func forMark(_ text: String) -> Color {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first,
              let digit = first.wholeNumberValue, (1...5).contains(digit) else {
            return .gray
        }
        if trimmed.count == 1 {
            return forGrade(Double(digit))
        }
        if trimmed.count == 2, let suffix = trimmed.last, "-+*!".contains(suffix) {
            return forGrade(Double(digit))
        }
        return .gray
    }

    static func foreground(for color: Color) -> Color {
        [Color.yellow, .mint].contains(color) ? .black : .white
    }

    static func forAverage(_ text: String) -> Color {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        if let direct = Double(cleaned) {
            return forGrade(direct)
        }
        let pattern = #"[0-9]+(\.[0-9]+)?"#
        if let match = cleaned.range(of: pattern, options: .regularExpression),
           let extracted = Double(cleaned[match]) {
            return forGrade(extracted)
        }
        return .secondary
    }
}

struct MarkBadge: View {
    let text: String

    var body: some View {
        let display = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if display.isEmpty {
            Text("–")
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .background(Color.secondary.opacity(0.12), in: .rect(cornerRadius: 12, style: .continuous))
        } else {
            let color = MarkColor.forMark(display)
            Text(display)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(MarkColor.foreground(for: color))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: 44, height: 44)
                .background(color.gradient, in: .rect(cornerRadius: 12, style: .continuous))
        }
    }
}

struct NewMarkDot: View {
    var body: some View {
        Circle()
            .fill(Color.blue)
            .frame(width: 8, height: 8)
            .accessibilityLabel("Nová známka")
    }
}

struct MarkDetailView: View {
    let mark: Mark
    let subject: Subject
    let averageText: String?
    let subjectNote: String?
    var isEmbeddedInSplit: Bool = false

    private var caption: String {
        mark.caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var subjectName: String {
        let name = subject.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? subject.abbrev : name
    }

    var body: some View {
        GroupedList {
            Section {
                VStack(spacing: 12) {
                    Text(mark.displayText)
                        .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(MarkColor.foreground(for: MarkColor.forMark(mark.displayText)))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(width: 88, height: 88)
                        .background(
                            MarkColor.forMark(mark.displayText).gradient,
                            in: .rect(cornerRadius: 24, style: .continuous)
                        )

                    VStack(spacing: 4) {
                        Text(caption.isEmpty ? "Známka" : caption)
                            .font(.title3.weight(.semibold))
                            .multilineTextAlignment(.center)
                        Text(subjectName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if mark.isNew == true {
                        Label("Nová známka", systemImage: "sparkle")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.15), in: Capsule())
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section("Podrobnosti") {
                if let dateStr = mark.markDate {
                    LabeledContent {
                        Text(BakiDate.formatCzechDate(dateStr))
                    } label: {
                        Label("Datum", systemImage: "calendar")
                    }
                }

                if let weight = mark.weight {
                    LabeledContent {
                        Text("\(weight)")
                    } label: {
                        Label("Váha", systemImage: "scalemass")
                    }
                }

                if let calc = mark.calculatedMarkText?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !calc.isEmpty, calc != mark.displayText {
                    LabeledContent {
                        Text(calc)
                    } label: {
                        Label("Vypočteno", systemImage: "function")
                    }
                }

                if let avg = averageText?.trimmingCharacters(in: .whitespacesAndNewlines), !avg.isEmpty {
                    LabeledContent {
                        Text("Ø \(avg)")
                            .foregroundStyle(MarkColor.forAverage(avg))
                            .fontWeight(.semibold)
                    } label: {
                        Label("Průměr předmětu", systemImage: "chart.line.uptrend.xyaxis")
                    }
                }

                if let rank = mark.classRankText?.trimmingCharacters(in: .whitespacesAndNewlines), !rank.isEmpty {
                    LabeledContent {
                        Text(rank)
                    } label: {
                        Label("Pořadí ve třídě", systemImage: "person.3")
                    }
                }
            }

            if let theme = mark.theme?.trimmingCharacters(in: .whitespacesAndNewlines),
               !theme.isEmpty, theme != caption {
                Section("Téma") {
                    Text(theme)
                        .textSelection(.enabled)
                }
            }

            if let note = subjectNote?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                Section("Poznámka k předmětu") {
                    Text(note)
                        .textSelection(.enabled)
                }
            }
        }
        .groupedList()
        .duoDetailNavigationTitle(subjectName, isEmbeddedInSplit: isEmbeddedInSplit)
    }
}
