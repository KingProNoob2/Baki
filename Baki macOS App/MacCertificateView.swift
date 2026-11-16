#if os(macOS)
import SwiftUI

/// Vysvědčení (Mac): list of school terms in the list column, certificate details and final marks
/// in the detail column.
struct MacCertificateView: View {
    @Environment(MacDetailModel.self) private var detail
    @State private var terms: [CertificateTerm] = []
    @State private var isLoading = false
    @State private var loaded = false
    @State private var loadFailed = false
    @State private var selection: String?

    private var subtitle: String {
        switch terms.count {
        case 0: return "Žádné vysvědčení"
        case 1: return "1 pololetí"
        case 2...4: return "\(terms.count) pololetí"
        default: return "\(terms.count) pololetí"
        }
    }

    var body: some View {
        Group {
            if !loaded && isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                List(terms, selection: $selection) { term in
                    CertificateTermRow(term: term)
                        .tag(term.id)
                }
                .macList()
            }
        }
        .macScreen(title: "Vysvědčení") {
            MacScreenHeader(title: "Vysvědčení", subtitle: terms.isEmpty ? nil : subtitle)
        }
        .onChange(of: selection) {
            guard let selected = terms.first(where: { $0.id == selection }) else { return }
            detail.show(id: selected.id, content: AnyView(MacCertificateDetailView(term: selected)))
        }
        .focusedSceneValue(\.refreshAction, RefreshAction { Task { await load() } })
        .task { await load() }
    }

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
            if selection == nil, let first = terms.first {
                selection = first.id
                detail.show(id: first.id, content: AnyView(MacCertificateDetailView(term: first)))
            }
        } catch {
            if terms.isEmpty { loadFailed = true }
        }
    }
}

private struct CertificateTermRow: View {
    let term: CertificateTerm

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(term.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                if let grade = term.gradeSubtitle {
                    Text(grade)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let avg = term.marksAverage {
                let avgStr = avg.formatted(.number.precision(.fractionLength(2)))
                Text("Ø \(avgStr)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(MarkColor.forGrade(avg))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(MarkColor.forGrade(avg).opacity(0.15), in: Capsule())
            } else if term.closed == false {
                Text("Neuzavřeno")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.15), in: Capsule())
            }
        }
        .padding(.vertical, 4)
    }
}

/// Detail column showing one certificate with all its subjects and grades.
struct MacCertificateDetailView: View {
    let term: CertificateTerm

    private var averageColor: Color {
        term.marksAverage.map { MarkColor.forGrade($0) } ?? .secondary
    }

    private var averageText: String {
        term.marksAverage.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "–"
    }

    var body: some View {
        MacDetailForm {
            MacHero(title: term.displayTitle, subtitle: term.gradeSubtitle) {
                MacTile(tint: averageColor) {
                    VStack(spacing: 2) {
                        Text("Ø")
                            .font(.caption.weight(.bold))
                        Text(averageText)
                            .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                    }
                }
            }

            Section("Podrobnosti") {
                if let achievement = term.achievementText?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !achievement.isEmpty {
                    LabeledContent("Celkové hodnocení") {
                        Text(achievement.capitalized)
                            .font(.body.weight(.medium))
                            .foregroundStyle(achievement.localizedCaseInsensitiveContains("vyznamen") ? Color.orange : Color.primary)
                    }
                }

                if let absent = term.absentHours {
                    LabeledContent("Absence") {
                        HStack(spacing: 4) {
                            Text("\(absent) h")
                            if let notExcused = term.notExcusedHours, notExcused > 0 {
                                Text("(\(notExcused) neomluvených)")
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }

                if let certDate = term.certificateDate {
                    let formatted = BakiDate.formatCzechDate(certDate)
                    if !formatted.isEmpty {
                        LabeledContent("Datum vydání", value: formatted)
                    }
                }

                if let closed = term.closed {
                    LabeledContent("Stav") {
                        Text(closed ? "Uzavřeno" : "Neuzavřeno")
                            .foregroundStyle(closed ? Color.secondary : Color.orange)
                    }
                }
            }

            Section("Závěrečné známky (\(term.finalMarks.count))") {
                if term.finalMarks.isEmpty {
                    Text("Žádné známky")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(term.finalMarks) { mark in
                        let subject = term.subject(for: mark.subjectId)
                        let name = subject?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        let abbrev = subject?.abbrev.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        let displayName = !name.isEmpty ? name : (!abbrev.isEmpty ? abbrev : "Předmět")

                        HStack(spacing: 12) {
                            MarkBadge(text: mark.markText)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(displayName)
                                    .font(.body.weight(.medium))
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
            }
        }
    }
}
#endif
