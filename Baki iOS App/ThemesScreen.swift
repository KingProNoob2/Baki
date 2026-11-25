import SwiftUI

enum ThemeSortOrder: String, CaseIterable, Identifiable {
    case newest = "Nejnovější"
    case oldest = "Od začátku"

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .newest: return "arrow.down"
        case .oldest: return "arrow.up"
        }
    }
}

struct SubjectAbbrevBadge: View {
    let text: String
    var size: CGFloat = 42

    var body: some View {
        let display = text.trimmingCharacters(in: .whitespacesAndNewlines)
        Text(display.isEmpty ? "–" : display)
            .font(.system(size: display.count > 4 ? 11 : (display.count > 3 ? 12 : 14), weight: .bold, design: .rounded))
            .foregroundStyle(Color.accentColor)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 4)
            .frame(width: size, height: size)
            .background(Color.accentColor.opacity(0.14), in: .rect(cornerRadius: 10, style: .continuous))
    }
}

struct SubjectThemeRow: View {
    let item: SubjectTheme

    private var formattedDate: String {
        let formatted = BakiDate.formatCzechDate(item.date)
        return formatted.isEmpty ? item.date : formatted
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if item.theme.isEmpty {
                    Text("Bez zadaného tématu")
                        .font(.body)
                        .foregroundStyle(.secondary)
                } else {
                    Text(item.theme)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !item.note.isEmpty {
                    HStack(alignment: .top, spacing: 5) {
                        Image(systemName: "note.text")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                        Text(item.note)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !formattedDate.isEmpty || !item.hourCaption.isEmpty {
                    HStack(spacing: 6) {
                        if !formattedDate.isEmpty {
                            Text(formattedDate)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        if !item.hourCaption.isEmpty {
                            if !formattedDate.isEmpty {
                                Text("·")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            Text(item.hourCaption)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Spacer(minLength: 8)

            if !item.lessonLabel.isEmpty {
                Text("č. \(item.lessonLabel)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.14), in: Capsule())
                    .fixedSize()
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

enum ThemesFormat {
    static func lessonCountText(_ count: Int) -> String {
        switch count {
        case 1: return "1 hodina"
        case 2...4: return "\(count) hodiny"
        default: return "\(count) hodin"
        }
    }

    static func subjectCountText(_ count: Int) -> String {
        switch count {
        case 1: return "1 předmět"
        case 2...4: return "\(count) předměty"
        default: return "\(count) předmětů"
        }
    }

    static func sortedThemes(_ themes: [SubjectTheme], order: ThemeSortOrder) -> [SubjectTheme] {
        let indexed = themes.enumerated().sorted { lhs, rhs in
            let d1 = lhs.element.parsedDate ?? .distantPast
            let d2 = rhs.element.parsedDate ?? .distantPast
            if d1 != d2 {
                return order == .newest ? d1 > d2 : d1 < d2
            }
            let l1 = Int(lhs.element.lessonLabel) ?? 0
            let l2 = Int(rhs.element.lessonLabel) ?? 0
            if l1 != l2 {
                return order == .newest ? l1 > l2 : l1 < l2
            }
            return order == .newest ? lhs.offset > rhs.offset : lhs.offset < rhs.offset
        }
        return indexed.map(\.element)
    }
}

struct ThemesScreen: View {
    @State private var subjects: [SubjectInfo] = []
    @State private var selectedSubjectID: SubjectInfo.ID?
    @State private var isLoading = false
    @State private var loaded = false
    @State private var loadFailed = false
    @State private var searchText = ""

    private var filteredSubjects: [SubjectInfo] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return subjects }
        return subjects.filter {
            $0.subjectName.localizedCaseInsensitiveContains(query)
            || $0.subjectAbbrev.localizedCaseInsensitiveContains(query)
            || ($0.teacherName?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var selectedSubject: SubjectInfo? {
        if let selectedSubjectID {
            return filteredSubjects.first { $0.id == selectedSubjectID } ?? filteredSubjects.first
        }
        return filteredSubjects.first
    }

    var body: some View {
        Group {
            if !loaded && isLoading {
                ThemesListSkeleton()
            } else if subjects.isEmpty && loadFailed {
                ContentUnavailableView {
                    Label("Předměty se nepodařilo načíst", systemImage: "exclamationmark.triangle")
                } actions: {
                    Button("Zkusit znovu") { Task { await load() } }
                }
            } else if subjects.isEmpty {
                ContentUnavailableView(
                    "Žádné předměty",
                    systemImage: "book.pages",
                    description: Text("Škola zatím nezveřejnila žádné předměty.")
                )
            } else if filteredSubjects.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                #if os(iOS)
                DuoAdaptiveSplit(primaryRatio: 0.40) {
                    compactSubjectsList
                } primary: {
                    splitSubjectsList
                } secondary: {
                    if let selected = selectedSubject {
                        SubjectThemesDetailScreen(subject: selected, isEmbeddedInSplit: true)
                            .id(selected.subjectID)
                    } else {
                        ContentUnavailableView("Vyberte předmět", systemImage: "book.pages")
                    }
                }
                #else
                compactSubjectsList
                #endif
            }
        }
        .navigationTitle("Témata")
        .searchable(text: $searchText, prompt: "Hledat předmět")
        // System Liquid Glass search in the top bar: a bottom bar would sit under the tab bar.
        .searchToolbarBehavior(.minimize)
        .toolbar {
            DefaultToolbarItem(kind: .search, placement: .topBarTrailing)
        }
        .task {
            guard !loaded else { return }
            await load()
        }
        .refreshable { await load() }
    }

    private var compactSubjectsList: some View {
        GroupedList {
            Section {
                ForEach(filteredSubjects) { subject in
                    NavigationLink {
                        SubjectThemesDetailScreen(subject: subject)
                    } label: {
                        subjectRow(subject)
                    }
                }
            } header: {
                Text("Předměty (\(filteredSubjects.count))")
            }
        }
        .groupedList()
    }

    #if os(iOS)
    private var splitSubjectsList: some View {
        GroupedList {
            Section {
                ForEach(filteredSubjects) { subject in
                    let isSelected = selectedSubject?.id == subject.id
                    Button {
                        selectedSubjectID = subject.id
                    } label: {
                        subjectRow(subject, showsDisclosure: false)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        isSelected ? Color.accentColor.opacity(0.14) : nil
                    )
                }
            } header: {
                Text("Předměty (\(filteredSubjects.count))")
            }
        }
        .groupedList()
    }
    #endif

    private func subjectRow(_ subject: SubjectInfo, showsDisclosure: Bool = true) -> some View {
        HStack(spacing: 12) {
            SubjectAbbrevBadge(text: subject.displayAbbrev)

            VStack(alignment: .leading, spacing: 2) {
                Text(subject.displayName)
                    .font(.body.weight(.medium))
                    .lineLimit(2)

                if let teacher = subject.teacherName {
                    Text(teacher)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func load() async {
        isLoading = true
        defer {
            isLoading = false
            loaded = true
        }

        do {
            let fetched = try await BakiClient.shared.fetchSubjects()
            subjects = fetched.sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
            loadFailed = false
        } catch {
            if subjects.isEmpty { loadFailed = true }
        }
    }
}

struct SubjectThemesDetailScreen: View {
    let subject: SubjectInfo
    var isEmbeddedInSplit: Bool = false

    @State private var themes: [SubjectTheme] = []
    @State private var resolvedSubject: Subject?
    @State private var isLoading = false
    @State private var loaded = false
    @State private var loadFailed = false
    @State private var searchText = ""
    @State private var sortOrder: ThemeSortOrder = SavedMode.load("themesSort", default: .newest)

    private var title: String {
        let name = resolvedSubject?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? subject.displayName : name
    }

    private var displayedThemes: [SubjectTheme] {
        let sorted = ThemesFormat.sortedThemes(themes, order: sortOrder)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sorted }
        return sorted.filter {
            $0.theme.localizedCaseInsensitiveContains(query)
            || $0.note.localizedCaseInsensitiveContains(query)
            || $0.lessonLabel.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        let content = Group {
            if !loaded && isLoading {
                ThemesDetailSkeleton()
            } else if themes.isEmpty && loadFailed {
                ContentUnavailableView {
                    Label("Témata se nepodařilo načíst", systemImage: "exclamationmark.triangle")
                } actions: {
                    Button("Zkusit znovu") { Task { await load() } }
                }
            } else if themes.isEmpty {
                ContentUnavailableView(
                    "Žádná témata",
                    systemImage: "book.pages",
                    description: Text("V tomto předmětu zatím nejsou zapsána žádná témata hodin.")
                )
            } else if displayedThemes.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                GroupedList {
                    if isEmbeddedInSplit {
                        Section {
                            HStack(spacing: 12) {
                                Text(title)
                                    .font(.headline)
                                Spacer(minLength: 8)
                                sortMenu
                            }
                        }
                    }

                    if let teacher = subject.teacherName {
                        Section {
                            LabeledContent {
                                Text(teacher)
                            } label: {
                                Label("Vyučující", systemImage: "person")
                            }
                            LabeledContent {
                                Text(ThemesFormat.lessonCountText(themes.count))
                            } label: {
                                Label("Zapsaných hodin", systemImage: "book.pages")
                            }
                        }
                    }

                    Section {
                        ForEach(Array(displayedThemes.enumerated()), id: \.offset) { _, item in
                            SubjectThemeRow(item: item)
                        }
                    } header: {
                        Text("Probrané učivo (\(displayedThemes.count))")
                    }
                }
                .groupedList()
            }
        }
        .onChange(of: sortOrder) { SavedMode.save("themesSort", sortOrder) }
        .task(id: subject.subjectID) { await load() }
        .refreshable { await load() }

        if isEmbeddedInSplit {
            content
        } else {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $searchText, prompt: "Hledat v tématech")
                // System Liquid Glass search in the top bar: a bottom bar would sit under the tab bar.
                .searchToolbarBehavior(.minimize)
                .toolbar {
                    DefaultToolbarItem(kind: .search, placement: .topBarTrailing)
                    ToolbarItem(placement: .topBarTrailing) {
                        sortMenu
                    }
                }
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Řazení", selection: $sortOrder) {
                ForEach(ThemeSortOrder.allCases) { order in
                    Label(order.rawValue, systemImage: order.systemImage).tag(order)
                }
            }
        } label: {
            Label("Řazení", systemImage: sortOrder.systemImage)
        }
    }

    private func load() async {
        isLoading = true
        defer {
            isLoading = false
            loaded = true
        }

        do {
            let response = try await BakiClient.shared.fetchSubjectThemes(subjectId: subject.subjectID)
            resolvedSubject = response.subject
            themes = response.themes
            loadFailed = false
        } catch {
            if themes.isEmpty { loadFailed = true }
        }
    }
}

private struct ThemesListSkeleton: View {
    var body: some View {
        GroupedList {
            Section {
                ForEach(0..<8, id: \.self) { _ in
                    HStack(spacing: 12) {
                        SubjectAbbrevBadge(text: "ČJL")
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Český jazyk a literatura")
                                .font(.body.weight(.medium))
                            Text("Mgr. Jana Nováková")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .groupedList()
        .skeletonPulse()
    }
}

private struct ThemesDetailSkeleton: View {
    var body: some View {
        GroupedList {
            Section {
                ForEach(0..<6, id: \.self) { _ in
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Opakování a procvičování učiva z předchozí hodiny")
                                .font(.body)
                            Text("12. 11. 2026 · 3. hod")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text("č. 30")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.2), in: Capsule())
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .groupedList()
        .skeletonPulse()
    }
}
