#if os(macOS)
import SwiftUI

/// Komens and Nástěnka: the message list in the list column, the selected message in the detail
/// column, with search and compose in the window toolbar.
struct MacMessagesView: View {
    let type: BakiClient.MessageType

    @Environment(MacDetailModel.self) private var detail
    @State private var messages: [KomensMessage] = []
    @State private var isLoading = false
    @State private var loadFailed = false
    @State private var showingCompose = false
    @State private var searchText = ""
    @State private var selection: KomensMessage.ID?

    private var title: String {
        switch type {
        case .received: return "Komens"
        case .noticeboard: return "Nástěnka"
        }
    }

    private var subtitle: String? {
        guard !messages.isEmpty else { return nil }
        let unread = messages.filter(\.isUnread).count
        if type == .received, unread > 0 { return "\(unread) nepřečtených" }
        return "\(messages.count) zpráv"
    }

    /// Messages matching the search text in sender, title or body.
    private var filtered: [KomensMessage] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return messages }
        return messages.filter { message in
            [message.sender?.name ?? message.relevantName, message.title, message.text]
                .contains { $0?.localizedStandardContains(query) == true }
        }
    }

    var body: some View {
        Group {
            if messages.isEmpty && isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if messages.isEmpty && loadFailed {
                ContentUnavailableView {
                    Label("Zprávy se nepodařilo načíst", systemImage: "exclamationmark.triangle")
                } actions: {
                    Button("Zkusit znovu") { Task { await load() } }
                }
            } else if messages.isEmpty {
                ContentUnavailableView("Žádné zprávy", systemImage: "tray")
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List(filtered, selection: $selection) { message in
                    row(message)
                        .tag(message.id)
                }
                .macList()
            }
        }
        .macScreen(title: title) {
            MacScreenHeader(title: title, subtitle: subtitle)
        }
        .searchable(text: $searchText, prompt: "Hledat")
        .toolbar {
            if type == .received {
                ToolbarItem(placement: .primaryAction) {
                    Button("Nová zpráva", systemImage: "square.and.pencil") {
                        showingCompose = true
                    }
                }
            }
        }
        .sheet(isPresented: $showingCompose) {
            ComposeMessageView()
        }
        .onChange(of: selection) {
            guard let message = messages.first(where: { $0.id == selection }) else { return }
            detail.show(id: message.id, content: AnyView(MessageDetailView(message: message)))
            Task { await markAsRead(message) }
        }
        .focusedSceneValue(\.refreshAction, RefreshAction { Task { await load() } })
        .task { await load() }
    }

    private func row(_ message: KomensMessage) -> some View {
        let sender = message.sender?.name ?? message.relevantName
        let title = message.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return HStack(alignment: .top, spacing: 12) {
            SenderAvatar(name: sender)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(sender ?? "")
                        .font(.headline)
                        .fontWeight(message.isUnread ? .bold : .semibold)
                        .lineLimit(1)
                    if message.isUnread {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 8, height: 8)
                            .accessibilityLabel("Nepřečteno")
                    }
                    Spacer(minLength: 0)
                    if message.attachments?.isEmpty == false {
                        Image(systemName: "paperclip")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Obsahuje přílohu")
                    }
                }
                if !title.isEmpty {
                    Text(title)
                        .font(.subheadline)
                        .lineLimit(2)
                }
                if let date = message.effectiveDateString {
                    Text(BakiDate.formatDisplayDate(date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func markAsRead(_ message: KomensMessage) async {
        guard message.read == false, let index = messages.firstIndex(where: { $0.id == message.id }) else { return }
        messages[index].read = true
        do {
            try await BakiClient.shared.markMessageAsRead(message)
            NotificationCenter.default.post(name: .bakiKomensReadChanged, object: nil)
        } catch {
            if let index = messages.firstIndex(where: { $0.id == message.id }) {
                messages[index].read = false
            }
        }
    }

    private func load() async {
        isLoading = true
        if let fetched = try? await BakiClient.shared.fetchMessages(type: type) {
            messages = fetched
        }
        isLoading = false
    }
}
#endif
