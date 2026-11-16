#if os(macOS)
import SwiftUI

/// Známky: marks grouped by subject or newest first in the list column, the selected mark in the
/// detail column.
struct MacMarksView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case subjects = "Předměty"
        case recent = "Nejnovější"

        var id: Self { self }
    }

    @Environment(MacDetailModel.self) private var detail
    @State private var subjects: [SubjectMarks] = []
    @State private var recent: [SubjectMark] = []
    @State private var isLoading = false
    @State private var loadFailed = false
    @State private var mode: Mode = SavedMode.load("marks", default: .subjects)
    @State private var selection: String?

    private var subtitle: String {
        let total = subjects.reduce(0) { $0 + $1.marks.count }
        let new = subjects.reduce(0) { $0 + $1.marks.filter { $0.isNew == true }.count }
        let count = MarksScreen.markCountText(total)
        return new > 0 ? "\(count) · \(new) nových" : count
    }

    var body: some View {
        Group {
            if subjects.isEmpty && isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if subjects.isEmpty && loadFailed {
                ContentUnavailableView {
                    Label("Známky se nepodařilo načíst", systemImage: "exclamationmark.triangle")
                } actions: {
                    Button("Zkusit znovu") { Task { await load() } }
                }
            } else if subjects.isEmpty {
                ContentUnavailableView("Žádné známky", systemImage: "list.number")
            } else {
                list
            }
        }
        .macScreen(title: "Známky") {
            MacScreenHeader(title: "Známky", subtitle: subjects.isEmpty ? nil : subtitle)
        }
        .toolbar {
            ToolbarItem {
                Picker("Zobrazení", selection: $mode) {
                    ForEach(Mode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .onChange(of: mode) { SavedMode.save("marks", mode) }
        .onChange(of: selection) { showSelectedMark() }
        .focusedSceneValue(\.refreshAction, RefreshAction { Task { await load() } })
        .task { await load() }
    }

    private var list: some View {
        List(selection: $selection) {
            switch mode {
            case .subjects:
                ForEach(subjects) { item in
                    Section {
                        if item.marks.isEmpty {
                            Text("Bez známek")
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 6)
                        }
                        ForEach(item.marks) { mark in
                            markRow(mark)
                                .tag(mark.id)
                        }
                    } header: {
                        subjectHeader(item)
                    }
                }
            case .recent:
                ForEach(recent) { item in
                    recentRow(item)
                        .tag(item.mark.id)
                }
            }
        }
        .macList()
    }

    // MARK: Rows

    private func subjectHeader(_ item: SubjectMarks) -> some View {
        let average = item.averageText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = item.subject.name.isEmpty ? item.subject.abbrev : item.subject.name

        return HStack(spacing: 8) {
            Text(name)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if !average.isEmpty {
                Text("Ø \(average)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(MarkColor.forAverage(average))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .glassEffect(.regular.tint(MarkColor.forAverage(average).opacity(0.25)), in: .capsule)
                    .accessibilityLabel("Průměr \(average)")
            }
        }
        .textCase(nil)
        .padding(.vertical, 4)
    }

    private func markRow(_ mark: Mark) -> some View {
        let caption = mark.caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let theme = mark.theme?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return HStack(spacing: 14) {
            MarkBadge(text: mark.displayText)

            VStack(alignment: .leading, spacing: 3) {
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
                if let date = mark.markDate {
                    Text(BakiDate.formatCzechDate(date))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func recentRow(_ item: SubjectMark) -> some View {
        let caption = item.mark.caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return HStack(spacing: 14) {
            MarkBadge(text: item.mark.displayText)

            VStack(alignment: .leading, spacing: 3) {
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
                if let date = item.mark.markDate {
                    Text(BakiDate.formatCzechDate(date))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: Data

    private func showSelectedMark() {
        guard let id = selection else { return }
        for item in subjects {
            if let mark = item.marks.first(where: { $0.id == id }) {
                detail.show(
                    id: id,
                    content: AnyView(MacMarkDetail(
                        mark: mark,
                        subject: item.subject,
                        averageText: item.averageText,
                        subjectNote: item.subjectNote
                    ))
                )
                return
            }
        }
    }

    private func load() async {
        isLoading = true
        do {
            let response = try await BakiClient.shared.fetchMarks()
            subjects = response.subjects.map { MarksScreen.sortedNewestFirst($0) }
            recent = MarksScreen.makeRecentMarks(from: subjects)
            loadFailed = false
        } catch {
            if subjects.isEmpty { loadFailed = true }
        }
        isLoading = false
    }
}

/// Detail column for a single mark.
struct MacMarkDetail: View {
    let mark: Mark
    let subject: Subject
    let averageText: String?
    let subjectNote: String?

    private var caption: String {
        mark.caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var subjectName: String {
        let name = subject.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? subject.abbrev : name
    }

    var body: some View {
        MacDetailForm {
            Section {
                MacHero(title: caption.isEmpty ? "Známka" : caption, subtitle: subjectName) {
                    MacTile(tint: MarkColor.forMark(mark.displayText)) {
                        Text(mark.displayText)
                            .font(.system(size: 48, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle([Color.yellow, .mint].contains(MarkColor.forMark(mark.displayText)) ? Color.black : .white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                }
                if mark.isNew == true {
                    Label("Nová známka", systemImage: "sparkle")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.blue)
                        .frame(maxWidth: .infinity)
                        .macPlainRow()
                }
            }

            Section("Podrobnosti") {
                if let date = mark.markDate {
                    LabeledContent {
                        Text(BakiDate.formatCzechDate(date))
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
                if let average = averageText?.trimmingCharacters(in: .whitespacesAndNewlines), !average.isEmpty {
                    LabeledContent {
                        Text("Ø \(average)")
                            .fontWeight(.semibold)
                            .foregroundStyle(MarkColor.forAverage(average))
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
        .navigationTitle(subjectName)
    }
}
#endif
