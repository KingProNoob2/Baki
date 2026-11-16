#if os(macOS)
import SwiftUI

/// Témata (Mac): list of subjects in the middle column, lesson themes in the detail column.
struct MacThemesView: View {
    @Environment(MacDetailModel.self) private var detail
    @State private var subjects: [SubjectInfo] = []
    @State private var isLoading = false
    @State private var loaded = false
    @State private var loadFailed = false
    @State private var selection: String?
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

    private var subtitle: String? {
        guard !subjects.isEmpty else { return nil }
        return ThemesFormat.subjectCountText(subjects.count)
    }

    var body: some View {
        Group {
            if !loaded && isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                List(filteredSubjects, selection: $selection) { subject in
                    subjectRow(subject)
                        .tag(subject.id)
                }
                .macList()
            }
        }
        .macScreen(title: "Témata") {
            MacScreenHeader(title: "Témata", subtitle: subtitle)
        }
        .searchable(text: $searchText, prompt: "Hledat předmět")
        .onChange(of: selection) {
            guard let selected = subjects.first(where: { $0.id == selection }) else { return }
            detail.show(id: selected.id, content: AnyView(MacSubjectThemesDetailView(subject: selected)))
        }
        .focusedSceneValue(\.refreshAction, RefreshAction { Task { await load() } })
        .task { await load() }
    }

    private func subjectRow(_ subject: SubjectInfo) -> some View {
        HStack(spacing: 12) {
            SubjectAbbrevBadge(text: subject.displayAbbrev, size: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(subject.displayName)
                    .font(.headline)
                    .lineLimit(1)

                if let teacher = subject.teacherName {
                    Text(teacher)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 3)
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
            if selection == nil, let first = subjects.first {
                selection = first.id
                detail.show(id: first.id, content: AnyView(MacSubjectThemesDetailView(subject: first)))
            }
        } catch {
            if subjects.isEmpty { loadFailed = true }
        }
    }
}

/// Detail column showing lesson themes for a single subject.
struct MacSubjectThemesDetailView: View {
    let subject: SubjectInfo

    @State private var themes: [SubjectTheme] = []
    @State private var resolvedSubject: Subject?
    @State private var isLoading = false
    @State private var loaded = false
    @State private var loadFailed = false
    @State private var sortOrder: ThemeSortOrder = SavedMode.load("themesSort", default: .newest)

    private var title: String {
        let name = resolvedSubject?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? subject.displayName : name
    }

    private var displayedThemes: [SubjectTheme] {
        ThemesFormat.sortedThemes(themes, order: sortOrder)
    }

    var body: some View {
        Group {
            if !loaded && isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if themes.isEmpty && loadFailed {
                ContentUnavailableView {
                    Label("Témata se nepodařilo načíst", systemImage: "exclamationmark.triangle")
                } actions: {
                    Button("Zkusit znovu") { Task { await load() } }
                }
            } else {
                MacDetailForm {
                    MacHero(title: title, subtitle: subject.teacherName) {
                        MacTile(tint: .blue) {
                            Text(subject.displayAbbrev)
                                .font(.system(size: subject.displayAbbrev.count > 4 ? 14 : 18, weight: .bold, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .padding(.horizontal, 6)
                        }
                    }

                    Section("Přehled") {
                        if let teacher = subject.teacherName {
                            LabeledContent("Vyučující", value: teacher)
                        }
                        LabeledContent("Zapsaných hodin", value: ThemesFormat.lessonCountText(themes.count))
                    }

                    if themes.isEmpty {
                        Section("Probrané učivo") {
                            Text("V tomto předmětu zatím nejsou zapsána žádná témata hodin.")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Section {
                            ForEach(Array(displayedThemes.enumerated()), id: \.offset) { _, item in
                                SubjectThemeRow(item: item)
                            }
                        } header: {
                            HStack {
                                Text("Probrané učivo (\(displayedThemes.count))")
                                Spacer()
                                Picker("Řazení", selection: $sortOrder) {
                                    ForEach(ThemeSortOrder.allCases) { order in
                                        Text(order.rawValue).tag(order)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                                .fixedSize()
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: sortOrder) { SavedMode.save("themesSort", sortOrder) }
        .task(id: subject.subjectID) { await load() }
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
#endif
