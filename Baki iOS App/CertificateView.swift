import SwiftUI

#if !os(macOS)
extension View {
    fileprivate func certificateListStyle() -> some View {
        listStyle(.insetGrouped)
    }
}
#else
extension View {
    fileprivate func certificateListStyle() -> some View {
        self
    }
}
#endif

/// Vysvědčení (iOS): zobrazuje závěrečné známky ze všech pololetí studia.
struct CertificateScreen: View {
    @State private var terms: [CertificateTerm] = []
    @State private var selectedTermId: String?
    @State private var isLoading = false
    @State private var loaded = false
    @State private var loadFailed = false

    private var selectedTerm: CertificateTerm? {
        if let selectedTermId {
            return terms.first { $0.id == selectedTermId } ?? terms.first
        }
        return terms.first
    }

    var body: some View {
        Group {
            if !loaded && isLoading {
                ProgressView()
            } else if terms.isEmpty && loadFailed {
                ContentUnavailableView {
                    Label("Vysvědčení se nepodařilo načíst", systemImage: "exclamationmark.triangle")
                } actions: {
                    Button("Zkusit znovu") { Task { await load() } }
                }
            } else if terms.isEmpty {
                ContentUnavailableView(
                    "Žádné vysvědčení",
                    systemImage: "graduationcap",
                    description: Text("Škola zatím nezveřejnila žádné vysvědčení.")
                )
            } else {
                #if os(iOS)
                DuoAdaptiveSplit(primaryRatio: 0.42) {
                    compactList
                } primary: {
                    summaryColumn
                } secondary: {
                    marksColumn
                }
                #else
                compactList
                #endif
            }
        }
        .navigationTitle("Vysvědčení")
        .task { await load() }
        .refreshable { await load() }
    }

    private var compactList: some View {
        List {
            if terms.count > 1 {
                termPickerSection
            }

            if let term = selectedTerm {
                summarySection(term)
                marksSection(term)
            }
        }
        .certificateListStyle()
    }

    #if os(iOS)
    private var summaryColumn: some View {
        List {
            if terms.count > 1 {
                termPickerSection
            }

            if let term = selectedTerm {
                summarySection(term)
            }
        }
        .certificateListStyle()
    }

    private var marksColumn: some View {
        List {
            if let term = selectedTerm {
                marksSection(term)
            }
        }
        .certificateListStyle()
    }
    #endif

    // MARK: - Sections

    /// Terms grouped by school year, keeping the order of `terms`.
    private var termsBySchoolYear: [(year: String, terms: [CertificateTerm])] {
        var groups: [(year: String, terms: [CertificateTerm])] = []
        for term in terms {
            if let index = groups.firstIndex(where: { $0.year == term.schoolYear }) {
                groups[index].terms.append(term)
            } else {
                groups.append((term.schoolYear, [term]))
            }
        }
        return groups
    }

    private var termPickerSection: some View {
        Section {
            LabeledContent("Pololetí") {
                Menu {
                    ForEach(termsBySchoolYear, id: \.year) { group in
                        Section(group.terms.first?.gradeSubtitle ?? group.year) {
                            Picker("Pololetí", selection: $selectedTermId) {
                                ForEach(group.terms) { term in
                                    Text(term.semesterTitle).tag(Optional(term.id))
                                }
                            }
                            .pickerStyle(.inline)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(selectedTerm.map { term in
                            [term.gradeSubtitle ?? term.schoolYear, term.semesterTitle].joined(separator: " · ")
                        } ?? "–")
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.footnote.weight(.semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
            }
        } header: {
            Text("Výběr období")
        }
    }

    private func summarySection(_ term: CertificateTerm) -> some View {
        Section {
            VStack(spacing: 12) {
                VStack(spacing: 4) {
                    Text(term.displayTitle)
                        .font(.headline)
                    if let subtitle = term.gradeSubtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if let avg = term.marksAverage {
                    let avgStr = avg.formatted(.number.precision(.fractionLength(2)))
                    VStack(spacing: 2) {
                        Text("Celkový průměr")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text("Ø \(avgStr)")
                            .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(MarkColor.forGrade(avg))
                    }
                    .padding(.vertical, 2)
                }

                if let achievement = term.achievementText?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !achievement.isEmpty {
                    let isHonors = achievement.localizedCaseInsensitiveContains("vyznamen")
                    HStack(spacing: 6) {
                        Image(systemName: isHonors ? "star.fill" : "checkmark.seal.fill")
                        Text(achievement.capitalized)
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(isHonors ? Color.orange : Color.green)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        (isHonors ? Color.orange : Color.green).opacity(0.14),
                        in: Capsule()
                    )
                }

                Divider()
                    .padding(.vertical, 2)

                HStack(alignment: .top, spacing: 12) {
                    if let absent = term.absentHours {
                        VStack(spacing: 2) {
                            Text("Absence")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(absent) h")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                            if let notExcused = term.notExcusedHours, notExcused > 0 {
                                Text("\(notExcused) neoml.")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.red)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }

                    if let certDate = term.certificateDate {
                        let formatted = BakiDate.formatCzechDate(certDate)
                        if !formatted.isEmpty {
                            VStack(spacing: 2) {
                                Text("Datum vydání")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(formatted)
                                    .font(.subheadline.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }

                    if let closed = term.closed {
                        VStack(spacing: 2) {
                            Text("Stav")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(closed ? "Uzavřeno" : "Neuzavřeno")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(closed ? Color.secondary : Color.orange)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
    }

    private func marksSection(_ term: CertificateTerm) -> some View {
        Section {
            if term.finalMarks.isEmpty {
                Text("Žádné známky v tomto pololetí")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(term.finalMarks) { mark in
                    let subject = term.subject(for: mark.subjectId)
                    let name = subject?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let abbrev = subject?.abbrev.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let displayName = !name.isEmpty ? name : (!abbrev.isEmpty ? abbrev : "Předmět")

                    HStack(spacing: 12) {
                        MarkBadge(text: mark.markText)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(displayName)
                                .font(.body.weight(.medium))
                                .lineLimit(2)

                            if !abbrev.isEmpty && abbrev != displayName {
                                Text(abbrev)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if let dateStr = mark.markDate {
                            let formatted = BakiDate.formatCzechDate(dateStr)
                            if !formatted.isEmpty {
                                Text(formatted)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            Text("Závěrečné známky (\(term.finalMarks.count))")
        }
    }

    // MARK: - Loading

    private func load() async {
        isLoading = true
        defer {
            isLoading = false
            loaded = true
        }

        do {
            let fetched = try await BakiClient.shared.fetchFinalMarks()
            terms = fetched.sorted { t1, t2 in
                if t1.schoolYear != t2.schoolYear {
                    return t1.schoolYear > t2.schoolYear
                }
                return t1.semester > t2.semester
            }
            loadFailed = false
            if selectedTermId == nil {
                selectedTermId = terms.first?.id
            }
        } catch {
            if terms.isEmpty { loadFailed = true }
        }
    }
}
