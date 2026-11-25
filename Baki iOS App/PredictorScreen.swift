import SwiftUI

/// Předvídač (iOS): pick a subject, then play with hypothetical marks for it.
struct PredictorScreen: View {
    @State private var subjects: [SubjectMarks] = []
    @State private var selectedSubjectID: SubjectMarks.ID?
    @State private var isLoading = false
    @State private var loaded = false
    @State private var loadFailed = false

    private var selectedSubject: SubjectMarks? {
        if let selectedSubjectID {
            return subjects.first { $0.id == selectedSubjectID } ?? subjects.first
        }
        return subjects.first
    }

    var body: some View {
        Group {
            if !loaded && isLoading {
                ProgressView()
            } else if subjects.isEmpty && loadFailed {
                ContentUnavailableView {
                    Label("Předvídač se nepodařilo načíst", systemImage: "exclamationmark.triangle")
                } actions: {
                    Button("Zkusit znovu") { Task { await load() } }
                }
            } else if subjects.isEmpty {
                ContentUnavailableView(
                    "Předvídač není dostupný",
                    systemImage: "wand.and.sparkles",
                    description: Text("Žádný předmět teď nepodporuje předpověď průměru.")
                )
            } else {
                #if os(iOS)
                DuoAdaptiveSplit(primaryRatio: 0.40) {
                    compactSubjectsList
                } primary: {
                    splitSubjectsList
                } secondary: {
                    if let selected = selectedSubject {
                        MarkPredictorView(item: selected, isEmbeddedInSplit: true)
                            .id(selected.id)
                    } else {
                        ContentUnavailableView("Vyberte předmět", systemImage: "wand.and.sparkles")
                    }
                }
                #else
                compactSubjectsList
                #endif
            }
        }
        .navigationTitle("Předvídač")
        .task { await load() }
        .refreshable { await load() }
    }

    private var compactSubjectsList: some View {
        GroupedList {
            Section {
                ForEach(subjects) { item in
                    NavigationLink {
                        MarkPredictorView(item: item)
                    } label: {
                        PredictorSubjectRow(item: item)
                    }
                }
            } header: {
                Text("Předmět")
            } footer: {
                Text("Vyberte předmět a zkuste přidat známky, které byste mohli dostat. Průměr spočítá škola.")
            }
        }
        .groupedList()
    }

    #if os(iOS)
    private var splitSubjectsList: some View {
        GroupedList {
            Section {
                ForEach(subjects) { item in
                    let isSelected = selectedSubject?.id == item.id
                    Button {
                        selectedSubjectID = item.id
                    } label: {
                        PredictorSubjectRow(item: item)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        isSelected ? Color.accentColor.opacity(0.14) : nil
                    )
                }
            } header: {
                Text("Předmět")
            } footer: {
                Text("Vyberte předmět a zkuste přidat známky, které byste mohli dostat. Průměr spočítá škola.")
            }
        }
        .groupedList()
    }
    #endif

    private func load() async {
        isLoading = true
        defer {
            isLoading = false
            loaded = true
        }
        do {
            let response = try await BakiClient.shared.fetchMarks()
            subjects = response.subjects.filter(\.canPredict)
            loadFailed = false
        } catch {
            if subjects.isEmpty { loadFailed = true }
        }
    }
}

/// Subject name, its current average and how many marks it has.
struct PredictorSubjectRow: View {
    let item: SubjectMarks

    private var name: String {
        item.subject.name.isEmpty ? item.subject.abbrev : item.subject.name
    }

    var body: some View {
        let average = item.averageText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.headline)
                    .lineLimit(1)
                Text(MarksScreen.markCountText(item.marks.count))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if !average.isEmpty {
                Text("Ø \(average)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(MarkColor.forAverage(average))
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
