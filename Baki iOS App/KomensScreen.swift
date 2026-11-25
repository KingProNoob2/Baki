import SwiftUI
import QuickLook

struct KomensScreen: View {
    var body: some View {
        MessagesScreen(type: .received)
    }
}

struct NoticeboardScreen: View {
    var body: some View {
        MessagesScreen(type: .noticeboard)
    }
}

struct MessagesScreen: View {
    let type: BakiClient.MessageType

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.allowsDuoSplit) private var allowsDuoSplit

    @State private var messages: [KomensMessage] = []
    @State private var isLoading: Bool = false
    @State private var loadFailed = false
    @State private var showingCompose = false
    @State private var searchText = ""
    @State private var selectedMessageID: String?

    private var usesDuoSplit: Bool {
        #if os(iOS)
        allowsDuoSplit && DuoEnvironment.isInnerDisplay(
            horizontalSizeClass: horizontalSizeClass,
            verticalSizeClass: verticalSizeClass
        )
        #else
        false
        #endif
    }

    private var selectedMessage: KomensMessage? {
        guard let selectedMessageID else { return nil }
        return filteredMessages.first { $0.id == selectedMessageID }
            ?? messages.first { $0.id == selectedMessageID }
    }

    /// Messages matching the search text in sender, title or body.
    private var filteredMessages: [KomensMessage] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return messages }
        return messages.filter { message in
            [message.sender?.name ?? message.relevantName, message.title, message.text]
                .contains { $0?.localizedStandardContains(query) == true }
        }
    }

    private var screenTitle: String {
        switch type {
        case .received:
            return "Komens"
        case .noticeboard:
            return "Nástěnka"
        }
    }

    var body: some View {
        Group {
            if messages.isEmpty && isLoading {
                MessagesSkeleton()
            } else if messages.isEmpty && loadFailed {
                ContentUnavailableView {
                    Label("Zprávy se nepodařilo načíst", systemImage: "exclamationmark.triangle")
                } actions: {
                    Button("Zkusit znovu") { Task { await loadMessages() } }
                }
            } else if messages.isEmpty {
                Text("Žádné zprávy")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                #if os(iOS)
                DuoAdaptiveSplit(primaryRatio: 0.42) {
                    messagesList
                        .overlay {
                            if filteredMessages.isEmpty {
                                ContentUnavailableView.search(text: searchText)
                            }
                        }
                        .duoFloatingOverlay(isVisible: type == .received) {
                            composeButton
                        }
                } primary: {
                    messagesList
                        .overlay {
                            if filteredMessages.isEmpty {
                                ContentUnavailableView.search(text: searchText)
                            }
                        }
                        .duoFloatingOverlay(isVisible: type == .received) {
                            composeButton
                        }
                } secondary: {
                    detailPane
                }
                #else
                messagesList
                    .overlay {
                        if filteredMessages.isEmpty {
                            ContentUnavailableView.search(text: searchText)
                        }
                    }
                    .duoFloatingOverlay(isVisible: type == .received) {
                        composeButton
                    }
                #endif
            }
        }
        .navigationTitle(screenTitle)
        .duoPrefersTabBarCompression()
        #if os(iOS)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Hledat"
        )
        #else
        .searchable(text: $searchText, prompt: "Hledat")
        #endif
        .sheet(isPresented: $showingCompose) {
            ComposeMessageView()
        }
        .onAppear {
            #if os(iOS)
            PhoneLinkManager.shared.stopHandoff()
            #endif
        }
        .task {
            await loadMessages()
        }
        .refreshable {
            await loadMessages()
        }
    }

    private var messagesList: some View {
        GroupedList {
            ForEach(filteredMessages) { message in
                if usesDuoSplit {
                    Button {
                        selectedMessageID = message.id
                    } label: {
                        messageRow(message)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(selectedMessageID == message.id ? Color.accentColor.opacity(0.14) : nil)
                } else {
                    NavigationLink {
                        MessageDetailView(message: message)
                            .task { await markAsRead(message) }
                    } label: {
                        messageRow(message)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let message = selectedMessage {
            MessageDetailView(message: message, isEmbeddedInSplit: true)
                .task(id: message.id) {
                    await markAsRead(message)
                }
        } else {
            ContentUnavailableView(
                "Vyberte zprávu",
                systemImage: "envelope",
                description: Text("Klepnutím na zprávu zobrazíte její text a přílohy.")
            )
        }
    }

    private var composeButton: some View {
        Button {
            showingCompose = true
        } label: {
            Image(systemName: "square.and.pencil")
                .font(.title2.weight(.medium))
                .frame(width: 56, height: 56)
                .foregroundStyle(.primary)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel("Nová zpráva")
    }

    @ViewBuilder
    private func messageRow(_ message: KomensMessage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let sender = message.sender?.name ?? message.relevantName, !sender.isEmpty {
                    Text(sender)
                        .font(.headline)
                        .lineLimit(1)
                }
                Spacer()
                if message.attachments?.isEmpty == false {
                    Image(systemName: "paperclip")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Obsahuje přílohu")
                }
                if message.isUnread {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                }
            }

            if let title = message.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                Text(title)
                    .font(.subheadline)
                    .lineLimit(1)
            }

            if let dateStr = message.effectiveDateString {
                Text(BakiDate.formatDisplayDate(dateStr))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
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

    private func loadMessages() async {
        isLoading = true
        do {
            messages = try await BakiClient.shared.fetchMessages(type: type)
            loadFailed = false
        } catch {
            if messages.isEmpty { loadFailed = true }
        }
        isLoading = false
    }
}

struct MessagesSkeleton: View {
    var body: some View {
        GroupedList {
            ForEach(0..<4, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Mgr. Jan Novák")
                            .font(.headline)
                            .lineLimit(1)
                        Spacer()
                    }

                    Text("Informace k organizaci výuky ve škole")
                        .font(.subheadline)
                        .lineLimit(1)

                    Text("2026-10-07")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .skeletonPulse()
    }
}

struct MessageDetailView: View {
    let message: KomensMessage
    var isEmbeddedInSplit: Bool = false
    @State private var showingReply = false

    private var canReply: Bool {
        message.canAnswer == true && message.sender?.id.isEmpty == false
    }

    private var title: String {
        let title = message.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? "Zpráva" : title
    }

    private var sender: String? {
        let name = (message.sender?.name ?? message.relevantName)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return name?.isEmpty == false ? name : nil
    }

    var body: some View {
        let cleanText = cleanHTML(message.text ?? "")

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(title)
                    .font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                HStack(spacing: 12) {
                    SenderAvatar(name: sender)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(sender ?? "Neznámý odesílatel")
                            .font(.headline)
                            .lineLimit(2)
                        if let dateStr = message.effectiveDateString {
                            Text(BakiDate.formatDisplayDate(dateStr))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Divider()

                if !cleanText.isEmpty {
                    Text((try? AttributedString(
                        markdown: cleanText,
                        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                    )) ?? AttributedString(cleanText))
                        .font(.body)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                } else if message.attachments?.isEmpty ?? true {
                    ContentUnavailableView("Zpráva nemá žádný text", systemImage: "text.alignleft")
                }

                if let attachments = message.attachments, !attachments.isEmpty {
                    AttachmentsSection(attachments: attachments)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .duoDetailNavigationTitle("", isEmbeddedInSplit: isEmbeddedInSplit)
        .toolbar {
            if !cleanText.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: "\(title)\n\n\(cleanText)")
                }
            }
            if canReply {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Odpovědět", systemImage: "arrowshape.turn.up.left") {
                        showingReply = true
                    }
                }
                .duoHighVisibilityPriority()
            }
        }
        .sheet(isPresented: $showingReply) {
            ReplyView(message: message, recipientName: sender)
        }
    }
}

struct AttachmentsSection: View {
    let attachments: [KomensAttachment]

    @State private var previewURL: URL?
    @State private var downloading: Set<String> = []
    @State private var downloadFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(attachments.count == 1 ? "Příloha" : "Přílohy (\(attachments.count))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(attachments) { attachment in
                Button {
                    Task { await open(attachment) }
                } label: {
                    AttachmentRow(attachment: attachment, isDownloading: downloading.contains(attachment.id))
                }
                .buttonStyle(.plain)
                .disabled(downloading.contains(attachment.id))
            }
        }
        .quickLookPreview($previewURL)
        .alert("Přílohu se nepodařilo stáhnout", isPresented: $downloadFailed) {
            Button("OK", role: .cancel) {}
        }
    }

    private func open(_ attachment: KomensAttachment) async {
        downloading.insert(attachment.id)
        defer { downloading.remove(attachment.id) }
        do {
            previewURL = try await BakiClient.shared.downloadAttachment(attachment)
        } catch {
            downloadFailed = true
        }
    }
}

private struct AttachmentRow: View {
    let attachment: KomensAttachment
    let isDownloading: Bool

    private var name: String {
        let name = attachment.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Příloha" : name
    }

    private var icon: String {
        let type = attachment.type?.lowercased() ?? ""
        let ext = (name as NSString).pathExtension.lowercased()
        if type.hasPrefix("image/") || ["jpg", "jpeg", "png", "heic", "gif"].contains(ext) { return "photo" }
        if type == "application/pdf" || ext == "pdf" { return "doc.richtext" }
        if type.hasPrefix("video/") { return "film" }
        if type.hasPrefix("audio/") { return "waveform" }
        if ["doc", "docx", "odt", "rtf", "txt"].contains(ext) { return "doc.text" }
        if ["xls", "xlsx", "ods", "csv"].contains(ext) { return "tablecells" }
        if ["ppt", "pptx", "odp"].contains(ext) { return "rectangle.on.rectangle" }
        if ["zip", "rar", "7z"].contains(ext) { return "doc.zipper" }
        return "doc"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 40, height: 40)
                .background(Color.accentColor.opacity(0.15), in: .rect(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                if let size = attachment.size, size > 0 {
                    Text(Int64(size).formatted(.byteCount(style: .file)))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if isDownloading {
                ProgressView()
            } else {
                Image(systemName: "arrow.down.circle")
                    .font(.title3)
                    .foregroundStyle(.tint)
            }
        }
        .padding(12)
        .cardBackground()
        .contentShape(.rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Otevře přílohu")
    }
}

struct SenderAvatar: View {
    let name: String?

    private var initials: String {
        guard let name else { return "" }
        let words = name
            .split(separator: " ")
            .filter { !$0.hasSuffix(".") && !$0.hasSuffix(",") }
        return words.prefix(2).compactMap(\.first).map { String($0).uppercased() }.joined()
    }

    var body: some View {
        ZStack {
            Circle().fill(Color.accentColor.gradient)
            if initials.isEmpty {
                Image(systemName: "person.fill")
            } else {
                Text(initials)
                    .font(.headline)
            }
        }
        .foregroundStyle(.white)
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }
}

private enum HTMLCleaner {
    static let replacements: [(regex: NSRegularExpression, template: String)] = [
        ("(?i)<a\\s+[^>]*href=[\"']([^\"']*)[\"'][^>]*>(.*?)</a>", "[$2]($1)"),
        ("(?i)<br\\s*/?>", "\n"),
        ("(?i)</p>|</div>|</tr>", "\n\n"),
        ("(?i)<li[^>]*>", "\n• "),
        ("<[^>]+>", "")
    ].compactMap { pattern, template in
        (try? NSRegularExpression(pattern: pattern)).map { ($0, template) }
    }

    static let excessNewlines = try? NSRegularExpression(pattern: "\n{3,}")

    static let entities: [(String, String)] = [
        ("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"),
        ("&quot;", "\""), ("&apos;", "'"), ("&#39;", "'"),
        ("&ndash;", "–"), ("&mdash;", "—"), ("&hellip;", "…"),
        ("&bull;", "•"), ("&copy;", "©"), ("&euro;", "€"),
        ("&amp;", "&")
    ]

    static func replace(_ regex: NSRegularExpression?, in text: String, with template: String) -> String {
        guard let regex else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}

func cleanHTML(_ html: String) -> String {
    guard !html.isEmpty else { return "" }
    var text = html

    for (regex, template) in HTMLCleaner.replacements {
        text = HTMLCleaner.replace(regex, in: text, with: template)
    }

    if text.contains("&") {
        for (entity, replacement) in HTMLCleaner.entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
    }

    text = HTMLCleaner.replace(HTMLCleaner.excessNewlines, in: text, with: "\n\n")

    return text.trimmingCharacters(in: .whitespacesAndNewlines)
}

struct ComposeMessageView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var types: [KomensMessageTypeOption] = []
    @State private var isLoading = true
    @State private var loadFailed = false

    @State private var selectedTypeID: String?
    @State private var selectedRecipientTypeID: String?
    @State private var selectedRecipients: Set<String> = []

    @State private var title = ""
    @State private var text = ""
    @State private var copyForClassTeacher = false
    @State private var copyForParent = false
    @State private var emailNotification = false
    @State private var requireConfirmation = false
    @State private var absenceFrom = Calendar.current.startOfDay(for: Date())
    @State private var absenceTo = Calendar.current.startOfDay(for: Date())

    @State private var isSending = false
    @State private var sendFailed = false
    @State private var showingDiscardConfirmation = false

    private var messageType: KomensMessageTypeOption? {
        types.first { $0.id == selectedTypeID }
    }

    private var recipientType: KomensRecipientType? {
        messageType?.recipientsTypes.first { $0.id == selectedRecipientTypeID }
    }

    private var hasTitle: Bool { messageType?.hasTitle ?? true }

    private var isAbsenceExcuse: Bool { messageType?.abbreviation.uppercased() == "OMLUVENKA" }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var hasRecipients: Bool {
        guard let recipientType else { return false }
        return recipientType.selection == .none || !selectedRecipients.isEmpty
    }

    private var canSend: Bool {
        messageType != nil && hasRecipients && !trimmedText.isEmpty
            && (!hasTitle || !trimmedTitle.isEmpty) && !isSending
    }

    private var isDirty: Bool {
        !trimmedTitle.isEmpty || !trimmedText.isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if loadFailed || types.isEmpty {
                    ContentUnavailableView {
                        Label("Nelze načíst příjemce", systemImage: "person.crop.circle.badge.exclamationmark")
                    } description: {
                        Text("Zkontrolujte připojení a zkuste to znovu.")
                    } actions: {
                        Button("Zkusit znovu") {
                            Task { await loadTypes() }
                        }
                    }
                } else {
                    form
                }
            }
            .navigationTitle("Nová zpráva")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zrušit", systemImage: "xmark") {
                        if isDirty {
                            showingDiscardConfirmation = true
                        } else {
                            dismiss()
                        }
                    }
                    .confirmationDialog("Zahodit zprávu?", isPresented: $showingDiscardConfirmation, titleVisibility: .visible) {
                        Button("Zahodit", role: .destructive) { dismiss() }
                        Button("Pokračovat v psaní", role: .cancel) {}
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView()
                    } else {
                        Button("Odeslat", systemImage: "arrow.up") {
                            Task { await send() }
                        }
                        .disabled(!canSend)
                    }
                }
            }
            .alert("Zprávu se nepodařilo odeslat", isPresented: $sendFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Zkuste to prosím znovu.")
            }
        }
        .interactiveDismissDisabled(isDirty)
        .duoPrefersToolbarCompression()
        .task { await loadTypes() }
    }

    private var form: some View {
        Form {
            Section {
                Picker(selection: $selectedTypeID) {
                    ForEach(types) { type in
                        Text(type.name).tag(Optional(type.id))
                    }
                } label: {
                    Label("Typ zprávy", systemImage: "tray.full")
                }

                if let messageType {
                    Picker(selection: $selectedRecipientTypeID) {
                        ForEach(messageType.recipientsTypes) { type in
                            Text(type.name.capitalizedFirst).tag(Optional(type.id))
                        }
                    } label: {
                        Label("Typ příjemce", systemImage: "person.2")
                    }
                }

                if let recipientType, recipientType.selection != .none {
                    NavigationLink {
                        RecipientPickerView(
                            recipientType: recipientType,
                            selection: $selectedRecipients
                        )
                    } label: {
                        LabeledContent {
                            Text(recipientSummary(for: recipientType))
                        } label: {
                            Label("Příjemce", systemImage: "paperplane")
                        }
                    }
                }
            }

            if isAbsenceExcuse {
                Section("Omlouvaná absence") {
                    DatePicker("Od", selection: $absenceFrom, displayedComponents: .date)
                    DatePicker("Do", selection: $absenceTo, in: absenceFrom..., displayedComponents: .date)
                }
                .onChange(of: absenceFrom) {
                    if absenceTo < absenceFrom { absenceTo = absenceFrom }
                }
            }

            Section {
                if hasTitle {
                    TextField("Předmět", text: $title)
                }
                TextField("Text zprávy", text: $text, axis: .vertical)
                    .lineLimit(8, reservesSpace: true)
            }

            if let recipientType, let messageType, hasOptions(messageType, recipientType) {
                Section("Možnosti") {
                    if recipientType.showCopyForClassTeacher == true {
                        Toggle("Kopie třídnímu učiteli", isOn: $copyForClassTeacher)
                    }
                    if recipientType.showCopyForParent == true {
                        Toggle("Kopie rodičům", isOn: $copyForParent)
                    }
                    if messageType.showEmailNotification == true {
                        Toggle("Upozornit e-mailem", isOn: $emailNotification)
                    }
                    if messageType.showConfirmation == true {
                        Toggle("Vyžadovat potvrzení", isOn: $requireConfirmation)
                    }
                }
            }
        }
        .onChange(of: selectedTypeID) {
            selectedRecipientTypeID = messageType?.recipientsTypes.first?.id
        }
        .onChange(of: selectedRecipientTypeID) {
            applyDefaultRecipients()
        }
    }

    private func hasOptions(_ messageType: KomensMessageTypeOption, _ recipientType: KomensRecipientType) -> Bool {
        recipientType.showCopyForClassTeacher == true || recipientType.showCopyForParent == true
            || messageType.showEmailNotification == true || messageType.showConfirmation == true
    }

    private func recipientSummary(for recipientType: KomensRecipientType) -> String {
        let chosen = recipientType.recipients.filter { selectedRecipients.contains($0.id) }
        switch chosen.count {
        case 0: return "Vybrat"
        case 1: return chosen[0].title
        default: return "\(chosen.count) příjemci"
        }
    }

    private func applyDefaultRecipients() {
        guard let recipientType else {
            selectedRecipients = []
            return
        }
        let defaults = recipientType.recipients.filter { $0.isDefault == true }.map(\.id)
        switch recipientType.selection {
        case .none:
            selectedRecipients = []
        case .single:
            selectedRecipients = Set(defaults.prefix(1))
        case .multiple:
            selectedRecipients = Set(defaults)
        }
    }

    private func loadTypes() async {
        isLoading = true
        loadFailed = false
        do {
            let response = try await BakiClient.shared.fetchMessageTypes()
            types = response.messageTypes
            if selectedTypeID == nil {
                selectedTypeID = types.first?.id
                selectedRecipientTypeID = types.first?.recipientsTypes.first?.id
                applyDefaultRecipients()
            }
        } catch {
            loadFailed = true
        }
        isLoading = false
    }

    private func send() async {
        guard let messageType, let recipientType else { return }
        isSending = true
        defer { isSending = false }

        let recipients = recipientType.selection == .none
            ? []
            : recipientType.recipients.map(\.id).filter(selectedRecipients.contains)

        let message = NewKomensMessage(
            messageType: messageType.abbreviation,
            title: hasTitle ? trimmedTitle : "",
            text: trimmedText,
            recipientType: recipientType.code,
            recipients: recipients,
            dateFrom: isAbsenceExcuse ? Self.isoFormatter.string(from: Calendar.current.startOfDay(for: absenceFrom)) : nil,
            dateTo: isAbsenceExcuse ? Self.isoFormatter.string(from: Self.endOfDay(absenceTo)) : nil,
            copyForClassTeacher: recipientType.showCopyForClassTeacher == true && copyForClassTeacher,
            copyForParent: recipientType.showCopyForParent == true && copyForParent,
            emailNotification: messageType.showEmailNotification == true && emailNotification,
            requireConfirmation: messageType.showConfirmation == true && requireConfirmation
        )

        do {
            try await BakiClient.shared.sendMessage(message)
            dismiss()
        } catch {
            sendFailed = true
        }
    }
}

extension ComposeMessageView {
    fileprivate static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current
        return formatter
    }()

    fileprivate static func endOfDay(_ date: Date) -> Date {
        let start = Calendar.current.startOfDay(for: date)
        return Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
    }
}

private struct RecipientPickerView: View {
    let recipientType: KomensRecipientType
    @Binding var selection: Set<String>

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filtered: [KomensRecipient] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return recipientType.recipients }
        return recipientType.recipients.filter { $0.title.localizedStandardContains(query) }
    }

    var body: some View {
        List(filtered) { recipient in
            Button {
                toggle(recipient)
            } label: {
                HStack {
                    Text(recipient.title)
                        .foregroundStyle(.primary)
                    Spacer()
                    if selection.contains(recipient.id) {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .overlay {
            if filtered.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .searchable(text: $searchText, prompt: "Hledat")
        .navigationTitle(recipientType.name.capitalizedFirst)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggle(_ recipient: KomensRecipient) {
        switch recipientType.selection {
        case .single:
            selection = [recipient.id]
            dismiss()
        case .multiple:
            if selection.contains(recipient.id) {
                selection.remove(recipient.id)
            } else {
                selection.insert(recipient.id)
            }
        case .none:
            break
        }
    }
}

private extension String {
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}

struct ReplyView: View {
    let message: KomensMessage
    let recipientName: String?

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isSending = false
    @State private var sendFailed = false

    private var subject: String {
        let original = message.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if original.isEmpty { return "Re: zpráva" }
        return original.lowercased().hasPrefix("re:") ? original : "Re: \(original)"
    }

    private var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Komu", value: recipientName ?? "Odesílatel")
                    LabeledContent("Předmět", value: subject)
                }
                Section {
                    TextField("Text odpovědi", text: $text, axis: .vertical)
                        .lineLimit(8, reservesSpace: true)
                }
            }
            .navigationTitle("Odpověď")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zrušit", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView()
                    } else {
                        Button("Odeslat", systemImage: "arrow.up") {
                            Task { await send() }
                        }
                        .disabled(trimmedText.isEmpty)
                    }
                }
            }
            .alert("Odpověď se nepodařilo odeslat", isPresented: $sendFailed) {
                Button("OK", role: .cancel) {}
            }
        }
        .interactiveDismissDisabled(!trimmedText.isEmpty)
        .duoInnerSheetPlacement(.leading)
        .duoPrefersToolbarCompression()
    }

    private func send() async {
        guard let sender = message.sender else { return }
        isSending = true
        defer { isSending = false }
        let recipientType = (sender.type?.isEmpty == false ? sender.type : nil) ?? "U"
        let reply = NewKomensMessage(
            messageType: "OBECNA",
            title: subject,
            text: trimmedText,
            recipientType: recipientType,
            recipients: [sender.id],
            previousMessageId: message.id
        )
        do {
            try await BakiClient.shared.sendMessage(reply)
            dismiss()
        } catch {
            sendFailed = true
        }
    }
}
