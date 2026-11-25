import SwiftUI

/// Bakaláři's public school directory (https://github.com/bakalari-api/bakalari-api-v3/blob/master/schools_list.md).
struct School: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let schoolUrl: String

    var host: String { URL(string: schoolUrl)?.host() ?? schoolUrl }
}

struct Municipality: Decodable, Identifiable, Hashable {
    let name: String
    let schoolCount: Int

    var id: String { name }
}

enum SchoolDirectory {
    private static let base = "https://sluzby.bakalari.cz/api/v1/municipality"

    private static func fetch<T: Decodable>(_ urlString: String) async throws -> T {
        guard let url = URL(string: urlString) else { throw APIError.invalidURL }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.serverError(http.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// All towns that have at least one school. The nameless "other" group isn't listed.
    static func municipalities() async throws -> [Municipality] {
        let all: [Municipality] = try await fetch(base)
        return all.filter { !$0.name.isEmpty && $0.schoolCount > 0 }
    }

    static func schools(in municipality: Municipality) async throws -> [School] {
        // The server answers 404 for names with a dot, so only the part before it is sent.
        let name = municipality.name.split(separator: ".", maxSplits: 1).first.map(String.init) ?? municipality.name
        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw APIError.invalidURL
        }
        struct Response: Decodable { let schools: [School]? }
        let response: Response = try await fetch(base + "/" + encoded)
        return response.schools ?? []
    }
}

/// Sheet for choosing a school on watchOS: search for the town, then pick the school.
struct SchoolPicker: View {
    let onSelect: (School) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var municipalities: [Municipality] = []
    @State private var query = ""
    @State private var isLoading = true
    @State private var failed = false

    private var filtered: [Municipality] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return municipalities }
        return municipalities.filter { $0.name.localizedStandardContains(text) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if failed {
                    VStack(spacing: 8) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text("Seznam škol se nepodařilo načíst")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                        Button("Zkusit znovu") {
                            Task { await load() }
                        }
                        .tint(.blue)
                    }
                    .padding()
                } else {
                    List(filtered) { municipality in
                        NavigationLink(value: municipality) {
                            HStack {
                                Text(municipality.name)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(municipality.schoolCount)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .overlay {
                        if filtered.isEmpty {
                            Text("Žádné město")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Město")
            .searchable(text: $query, prompt: "Hledat město")
            .navigationDestination(for: Municipality.self) { municipality in
                SchoolList(municipality: municipality) { school in
                    onSelect(school)
                    dismiss()
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard municipalities.isEmpty else { return }
        isLoading = true
        failed = false
        do {
            municipalities = try await SchoolDirectory.municipalities()
        } catch {
            failed = true
        }
        isLoading = false
    }
}

private struct SchoolList: View {
    let municipality: Municipality
    let onSelect: (School) -> Void

    @State private var schools: [School] = []
    @State private var query = ""
    @State private var isLoading = true
    @State private var failed = false

    private var filtered: [School] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return schools }
        return schools.filter { $0.name.localizedStandardContains(text) }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if failed {
                VStack(spacing: 8) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Školy se nepodařilo načíst")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                    Button("Zkusit znovu") {
                        Task { await load() }
                    }
                    .tint(.blue)
                }
                .padding()
            } else {
                List(filtered) { school in
                    Button {
                        onSelect(school)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(school.name)
                                .font(.footnote)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Text(school.host)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .overlay {
                    if filtered.isEmpty {
                        Text("Žádná škola")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(municipality.name)
        .searchable(text: $query, prompt: "Hledat školu")
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        failed = false
        do {
            schools = try await SchoolDirectory.schools(in: municipality)
        } catch {
            failed = true
        }
        isLoading = false
    }
}
