import SwiftUI

struct SubjectMark: Identifiable {
    var id: String { mark.id }
    let mark: Mark
    let subject: Subject
    let averageText: String?
    let subjectNote: String?
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

    @State private var subjects: [SubjectMarks] = []
    @State private var recentMarks: [SubjectMark] = []
    @State private var isLoading: Bool = false
    @State private var loaded: Bool = false
    @State private var loadFailed: Bool = false
    @State private var expandedSubjects: Set<String> = []
    @AppStorage("savedMode_marks") private var storedMode: String = Mode.subjects.rawValue

    private var mode: Mode {
        Mode(rawValue: storedMode) ?? .subjects
    }

    var body: some View {
        Group {
            if subjects.isEmpty && (!loaded || isLoading) {
                MarksSkeleton()
            } else if subjects.isEmpty && loadFailed {
                VStack(spacing: 8) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Známky se nepodařilo načíst")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                    Button("Zkusit znovu") {
                        Task { await loadMarks() }
                    }
                    .tint(.blue)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if subjects.isEmpty {
                Text("Žádné známky")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                List {
                    switch mode {
                    case .subjects:
                        ForEach(subjects) { item in
                            subjectRow(item)

                            if expandedSubjects.contains(item.id) {
                                markRows(for: item)
                            }
                        }
                    case .recent:
                        if recentMarks.isEmpty {
                            Text("Žádné známky")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            Section("Nejnovější") {
                                ForEach(recentMarks) { item in
                                    NavigationLink {
                                        MarkDetailView(
                                            mark: item.mark,
                                            subject: item.subject,
                                            averageText: item.averageText,
                                            subjectNote: item.subjectNote
                                        )
                                    } label: {
                                        recentRow(item)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.top, 60)
            }
        }
        .bakiHeader("Známky")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation {
                        storedMode = (mode == .subjects ? Mode.recent : Mode.subjects).rawValue
                    }
                } label: {
                    Image(systemName: mode == .subjects ? Mode.recent.systemImage : Mode.subjects.systemImage)
                }
                .accessibilityLabel(mode == .subjects ? "Zobrazit nejnovější známky" : "Zobrazit podle předmětů")
            }
        }
        .task {
            await loadMarks()
        }
        .refreshable {
            await loadMarks()
        }
    }

    private func subjectRow(_ item: SubjectMarks) -> some View {
        let isExpanded = expandedSubjects.contains(item.id)
        let hasNewMarks = item.marks.contains { $0.isNew == true }
        let average = item.averageText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = item.subject.name.isEmpty ? item.subject.abbrev : item.subject.name

        return Button {
            withAnimation {
                if isExpanded {
                    expandedSubjects.remove(item.id)
                } else {
                    expandedSubjects.insert(item.id)
                }
            }
        } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(name)
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if hasNewMarks {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 6, height: 6)
                                .accessibilityLabel("Nová známka")
                        }
                    }

                    HStack {
                        Text(item.marks.isEmpty ? "Bez známek" : Self.markCountText(item.marks.count))
                        Spacer(minLength: 0)
                        if !average.isEmpty {
                            Text("Ø \(average)")
                                .accessibilityLabel("Průměr \(average)")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                if !item.marks.isEmpty {
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
            }
        }
        .disabled(item.marks.isEmpty)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.gray.opacity(isExpanded ? 0.4 : 0.22))
        )
        .accessibilityHint(isExpanded ? "Skryje známky" : "Zobrazí známky")
    }

    @ViewBuilder
    private func markRows(for item: SubjectMarks) -> some View {
        ForEach(item.marks) { mark in
            NavigationLink {
                MarkDetailView(
                    mark: mark,
                    subject: item.subject,
                    averageText: item.averageText,
                    subjectNote: item.subjectNote
                )
            } label: {
                markRow(mark)
            }
            .padding(.leading, 12)
            .listRowBackground(
                HStack(spacing: 4) {
                    Capsule()
                        .fill(mark.isNew == true ? Color.red : Color.gray)
                        .frame(width: 3)
                        .padding(.vertical, 6)
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.gray.opacity(0.1))
                }
                .padding(.leading, 6)
            )
        }
    }

    private static func isNewer(_ a: (mark: Mark, date: Date), _ b: (mark: Mark, date: Date)) -> Bool {
        if a.date != b.date { return a.date > b.date }
        let new1 = a.mark.isNew == true
        let new2 = b.mark.isNew == true
        if new1 != new2 { return new1 }
        return a.mark.id > b.mark.id
    }

    private static func sortedNewestFirst(_ item: SubjectMarks) -> SubjectMarks {
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

    private static func makeRecentMarks(from subjects: [SubjectMarks]) -> [SubjectMark] {
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
                        date: mark.parsedDate ?? .distantPast
                    )
                }
            }
            .sorted { Self.isNewer(($0.item.mark, $0.date), ($1.item.mark, $1.date)) }
            .map(\.item)
    }

    private static func markCountText(_ count: Int) -> String {
        switch count {
        case 1: return "1 známka"
        case 2...4: return "\(count) známky"
        default: return "\(count) známek"
        }
    }

    @ViewBuilder
    private func recentRow(_ item: SubjectMark) -> some View {
        let subjectName = item.subject.name.isEmpty ? item.subject.abbrev : item.subject.name
        let caption = item.mark.caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(subjectName)
                        .font(.headline)
                        .lineLimit(1)
                    if item.mark.isNew == true {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                            .accessibilityLabel("Nová známka")
                    }
                }

                Text(caption.isEmpty ? "Známka" : caption)
                    .font(.caption)
                    .lineLimit(1)

                if let dateStr = item.mark.markDate {
                    Text(BakiDate.formatCzechDate(dateStr))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            Text(item.mark.displayText)
                .bold()
                .font(.system(size: 25))
                .foregroundStyle(item.mark.isNew == true ? .red : .primary)
        }
    }

    @ViewBuilder
    private func markRow(_ mark: Mark) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if let caption = mark.caption?.trimmingCharacters(in: .whitespacesAndNewlines), !caption.isEmpty {
                    Text(caption)
                        .bold()
                        .lineLimit(1)
                }
                if let theme = mark.theme?.trimmingCharacters(in: .whitespacesAndNewlines), !theme.isEmpty {
                    Text(theme)
                        .font(.caption2)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer()
            Text(mark.displayText)
                .bold()
                .font(.system(size: 25))
                .foregroundStyle(mark.isNew == true ? .red : .primary)
        }
    }

    private func loadMarks() async {
        isLoading = true
        defer {
            isLoading = false
            loaded = true
        }
        do {
            let response = try await BakiClient.shared.fetchMarks()
            subjects = response.subjects.map(Self.sortedNewestFirst)
            recentMarks = Self.makeRecentMarks(from: response.subjects)
            loadFailed = false
        } catch {
            if subjects.isEmpty { loadFailed = true }
        }
    }
}

struct MarksSkeleton: View {
    var body: some View {
        List {
            ForEach(["Matematika", "Český jazyk", "Anglický jazyk", "Fyzika", "Chemie"], id: \.self) { subject in
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(subject)
                            .font(.headline)
                        HStack {
                            Text("5 známek")
                            Spacer(minLength: 0)
                            Text("Ø 1,50")
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
        }
        .padding(.top, 60)
        .skeletonPulse()
    }
}

struct MarkCardView: View {
    let mark: Mark

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if let caption = mark.caption?.trimmingCharacters(in: .whitespacesAndNewlines), !caption.isEmpty {
                    Text(caption)
                        .font(.subheadline)
                        .bold()
                        .lineLimit(1)
                        .foregroundStyle(.blue)
                } else {
                    Text("Známka")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if mark.isNew == true {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                        Text("Nová známka")
                            .font(.caption2)
                            .bold()
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    }
                }

                if let calc = mark.calculatedMarkText?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !calc.isEmpty,
                   calc != mark.displayText {
                    Text("Vypočteno: \(calc)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            Text(mark.displayText)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.blue)
                .padding(.trailing, 2)
        }
        .padding(8)
        .background(Color.blue.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct MarkDetailView: View {
    let mark: Mark
    let subject: Subject
    let averageText: String?
    let subjectNote: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 6) {
                        let cleanName = subject.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let cleanAbbrev = subject.abbrev.trimmingCharacters(in: .whitespacesAndNewlines)

                        Text(cleanName.isEmpty ? cleanAbbrev : cleanName)
                            .font(.headline)
                            .bold()
                            .fixedSize(horizontal: false, vertical: true)

                        if !cleanAbbrev.isEmpty && cleanAbbrev.lowercased() != cleanName.lowercased() {
                            Text(cleanAbbrev)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2.5)
                                .background(Color.blue.opacity(0.25))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color.blue.opacity(0.5), lineWidth: 0.5)
                                )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                MarkCardView(mark: mark)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    if let weight = mark.weight {
                        InfoRow(
                            icon: "scalemass.fill",
                            iconColor: .purple,
                            title: "Váha",
                            subtitle: "\(weight)"
                        )
                    }

                    if let dateStr = mark.markDate {
                        InfoRow(
                            icon: "calendar",
                            iconColor: .orange,
                            title: "Datum",
                            subtitle: BakiDate.formatCzechDate(dateStr)
                        )
                    }

                    if let avg = averageText?.trimmingCharacters(in: .whitespacesAndNewlines), !avg.isEmpty {
                        InfoRow(
                            icon: "chart.line.uptrend.xyaxis",
                            iconColor: .green,
                            title: "Průměr předmětu",
                            subtitle: avg
                        )
                    }

                    if let rank = mark.classRankText?.trimmingCharacters(in: .whitespacesAndNewlines), !rank.isEmpty {
                        InfoRow(
                            icon: "person.3.fill",
                            iconColor: .cyan,
                            title: "Pořadí ve třídě",
                            subtitle: rank
                        )
                    }
                }

                if let theme = mark.theme?.trimmingCharacters(in: .whitespacesAndNewlines), !theme.isEmpty {
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

                if let note = subjectNote?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Image(systemName: "info.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("Poznámka k předmětu")
                                .font(.caption2)
                                .bold()
                                .foregroundStyle(.secondary)
                        }

                        Text(note)
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
