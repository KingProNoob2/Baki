#if os(macOS)
import SwiftUI

/// Předvídač (Mac): subjects in the list column, the predictor for the selected one in the detail
/// column.
struct MacPredictorView: View {
    @Environment(MacDetailModel.self) private var detail
    @State private var subjects: [SubjectMarks] = []
    @State private var isLoading = false
    @State private var loaded = false
    @State private var loadFailed = false
    @State private var selection: String?

    var body: some View {
        Group {
            if !loaded && isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                List(subjects, selection: $selection) { item in
                    PredictorSubjectRow(item: item)
                        .padding(.vertical, 2)
                        .tag(item.id)
                }
                .macList()
            }
        }
        .macScreen(title: "Předvídač") {
            MacScreenHeader(title: "Předvídač", subtitle: "Vyberte předmět a zkuste přidat známky")
        }
        .onChange(of: selection) {
            guard let item = subjects.first(where: { $0.id == selection }) else { return }
            detail.show(id: item.id, content: AnyView(MarkPredictorView(item: item)))
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
            let response = try await BakiClient.shared.fetchMarks()
            subjects = response.subjects.filter(\.canPredict)
            loadFailed = false
        } catch {
            if subjects.isEmpty { loadFailed = true }
        }
    }
}
#endif
