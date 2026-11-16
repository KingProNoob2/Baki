import SwiftUI

/// Předvídač (iOS): pick a subject, then play with hypothetical marks for it.
struct PredictorScreen: View {
    @State private var subjects: [SubjectMarks] = []
    @State private var isLoading = false
    @State private var loaded = false
    @State private var loadFailed = false

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
        }
        .navigationTitle("Předvídač")
        .task { await load() }
        .refreshable { await load() }
    }

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
