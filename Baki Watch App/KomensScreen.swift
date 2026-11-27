import SwiftUI

/// Komens and the noticeboard in one list, each message tagged with where it came from.
struct KomensScreen: View {
    private struct Entry: Identifiable {
        var message: KomensMessage
        let isNotice: Bool
        var id: String { (isNotice ? "n-" : "k-") + message.id }
    }

    @State private var entries: [Entry] = []
    @State private var isLoading: Bool = false
    @State private var loaded: Bool = false
    @State private var loadFailed: Bool = false

    var body: some View {
        Group {
            if entries.isEmpty && (!loaded || isLoading) {
                MessagesSkeleton()
            } else if entries.isEmpty && loadFailed {
                VStack(spacing: 8) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Zprávy se nepodařilo načíst")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                    Button("Zkusit znovu") {
                        Task { await loadMessages() }
                    }
                    .tint(.blue)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty {
                Text("Žádné zprávy")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(entries) { entry in
                    NavigationLink {
                        MessageDetailView(message: entry.message)
                            .task { await markAsRead(entry) }
                    } label: {
                        messageRow(entry)
                    }
                }
                .padding(.top, 60)
            }
        }
        .bakiHeader("Komens")
        .onAppear {
            PhoneLinkManager.shared.stopHandoff()
        }
        .task {
            await loadMessages()
        }
        .refreshable {
            await loadMessages()
        }
    }

    private func messageRow(_ entry: Entry) -> some View {
        let message = entry.message
        let tint: Color = entry.isNotice ? .orange : .blue
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if let sender = message.sender?.name ?? message.relevantName, !sender.isEmpty {
                    Text(sender)
                        .font(.headline)
                        .lineLimit(1)
                }
                Spacer(minLength: 2)
                Text(entry.isNotice ? "Nástěnka" : "Komens")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(tint.opacity(0.2), in: Capsule())
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

    private func markAsRead(_ entry: Entry) async {
        let message = entry.message
        guard message.read == false, let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].message.read = true
        do {
            try await BakiClient.shared.markMessageAsRead(message)
        } catch {
            if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                entries[index].message.read = false
            }
        }
    }

    private func loadMessages() async {
        isLoading = true
        defer {
            isLoading = false
            loaded = true
        }
        async let received = try? BakiClient.shared.fetchMessages(type: .received)
        async let notices = try? BakiClient.shared.fetchMessages(type: .noticeboard)
        let (komens, board) = await (received, notices)
        if komens != nil || board != nil {
            entries = ((komens ?? []).map { Entry(message: $0, isNotice: false) }
                + (board ?? []).map { Entry(message: $0, isNotice: true) })
                .sorted { ($0.message.parsedDate ?? .distantPast) > ($1.message.parsedDate ?? .distantPast) }
            loadFailed = false
        } else if entries.isEmpty {
            loadFailed = true
        }
    }
}

struct MessagesSkeleton: View {
    var body: some View {
        List {
            ForEach(0..<4, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("Mgr. Jan Novák")
                            .font(.headline)
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        Text("Komens")
                            .font(.system(size: 10, weight: .semibold))
                            .fixedSize()
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.2), in: Capsule())
                    }

                    Text("Informace k organizaci výuky")
                        .font(.subheadline)
                        .lineLimit(1)

                    Text("7. 10. 2026")
                        .font(.caption2)
                }
            }
        }
        .padding(.top, 60)
        .skeletonPulse()
    }
}

struct MessageDetailView: View {
    let message: KomensMessage

    @State private var tappedURL: URL?
    @State private var showOpenAlert: Bool = false
    @State private var openingOnWatch: Bool = false
    @Environment(\.openURL) private var systemOpenURL

    var body: some View {
        let plainText = message.plainText
        let markdownText = breakSentences(cleanHTML(message.text ?? "", preserveLinks: true))

        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    if let title = message.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                        Text(title)
                            .font(.headline)
                            .bold()
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let sender = message.sender?.name ?? message.relevantName, !sender.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: "person.circle.fill")
                                .foregroundStyle(.blue)
                            Text(sender)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    if let dateStr = message.effectiveDateString {
                        HStack(spacing: 5) {
                            Image(systemName: "calendar")
                                .foregroundStyle(.secondary)
                            Text(BakiDate.formatDisplayDate(dateStr))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                if !plainText.isEmpty {
                    Text((try? AttributedString(
                        markdown: markdownText,
                        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                    )) ?? AttributedString(breakSentences(plainText)))
                        .font(.body)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Zpráva nemá žádný text")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 12)
        }
        .environment(\.openURL, OpenURLAction { url in
            if openingOnWatch {
                return .systemAction
            }
            handleURL(url)
            return .handled
        })
        .alert("Odkaz zprávy", isPresented: $showOpenAlert) {
            Button("Otevřít na hodinkách") {
                if let url = tappedURL {
                    openingOnWatch = true
                    systemOpenURL(url)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        openingOnWatch = false
                    }
                }
                stopHandoff()
            }
            Button("Zavřít", role: .cancel) {
                stopHandoff()
            }
        } message: {
            if let url = tappedURL {
                Text("\(url.host ?? url.absoluteString)\n\nPro otevření na iPhonu otevřete přepínač aplikací (přejetím zdola nahoru) a dole klepněte na Safari banner.")
            } else {
                Text("Pro otevření na iPhonu otevřete přepínač aplikací a dole klepněte na Safari banner.")
            }
        }
        .onChange(of: showOpenAlert) { _, isPresented in
            if !isPresented {
                stopHandoff()
            }
        }
        .onDisappear {
            stopHandoff()
        }
    }

    private func stopHandoff() {
        tappedURL = nil
        PhoneLinkManager.shared.stopHandoff()
    }

    private func handleURL(_ url: URL) {
        tappedURL = url
        PhoneLinkManager.shared.openOnPhone(url)
        showOpenAlert = true
    }
}

private enum HTMLCleaner {
    static let anchorRegex = try? NSRegularExpression(
        pattern: "<a\\s+[^>]*href=[\"']([^\"']*)[\"'][^>]*>(.*?)</a>",
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )

    static let replacements: [(regex: NSRegularExpression, template: String)] = [
        ("(?i)<br\\s*/?>", "\n"),
        ("(?i)</p>|</div>|</tr>", "\n\n"),
        ("(?i)<li[^>]*>", "\n• "),
        ("<[^>]+>", "")
    ].compactMap { pattern, template in
        (try? NSRegularExpression(pattern: pattern)).map { ($0, template) }
    }

    static let excessNewlines = try? NSRegularExpression(pattern: "\n{3,}")
    static let numericEntity = try? NSRegularExpression(pattern: "&#(x[0-9a-fA-F]+|[0-9]+);")

    static let entities: [(String, String)] = [
        ("&nbsp;", " "), ("&shy;", ""), ("&lt;", "<"), ("&gt;", ">"),
        ("&quot;", "\""), ("&apos;", "'"), ("&#39;", "'"),
        ("&bdquo;", "„"), ("&ldquo;", "“"), ("&rdquo;", "”"),
        ("&lsquo;", "‘"), ("&rsquo;", "’"), ("&laquo;", "«"), ("&raquo;", "»"),
        ("&ndash;", "–"), ("&mdash;", "—"), ("&hellip;", "…"),
        ("&bull;", "•"), ("&copy;", "©"), ("&euro;", "€"),
        ("&amp;", "&")
    ]

    static let sentenceBreak = try? NSRegularExpression(
        pattern: "(?<!\\b(?:Mgr|Ing|Bc|Dr|Prof|MUDr|JUDr|PhDr|RNDr|Ph|tzv|apod|atd|př|tj|např|resp))(?<!\\b\\d{1,2})([.!?…])[ \\t]+(?=\\p{Lu})"
    )

    static func replace(_ regex: NSRegularExpression?, in text: String, with template: String) -> String {
        guard let regex else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }

    static func decodeEntities(_ input: String) -> String {
        guard input.contains("&") else { return input }
        var text = input
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        if let regex = numericEntity, text.contains("&#") {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches.reversed() {
                guard let fullRange = Range(match.range, in: text),
                      let codeRange = Range(match.range(at: 1), in: text) else { continue }
                let token = text[codeRange]
                let codePoint: UInt32?
                if token.first == "x" || token.first == "X" {
                    codePoint = UInt32(token.dropFirst(), radix: 16)
                } else {
                    codePoint = UInt32(token, radix: 10)
                }
                if let cp = codePoint, let scalar = UnicodeScalar(cp) {
                    text.replaceSubrange(fullRange, with: String(scalar))
                }
            }
        }
        return text
    }

    static func convertAnchors(_ html: String, preserveLinks: Bool) -> String {
        guard let regex = anchorRegex, html.range(of: "<a", options: .caseInsensitive) != nil else {
            return html
        }
        var result = html
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let hrefRange = Range(match.range(at: 1), in: result),
                  let bodyRange = Range(match.range(at: 2), in: result) else { continue }
            let rawHref = decodeEntities(String(result[hrefRange])).trimmingCharacters(in: .whitespacesAndNewlines)
            var label = String(result[bodyRange])
            for (tagRegex, template) in replacements {
                label = replace(tagRegex, in: label, with: template)
            }
            label = decodeEntities(label)
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if preserveLinks, !rawHref.isEmpty {
                let safeLabel = (label.isEmpty ? rawHref : label)
                    .replacingOccurrences(of: "[", with: "\\[")
                    .replacingOccurrences(of: "]", with: "\\]")
                result.replaceSubrange(fullRange, with: "[\(safeLabel)](<\(rawHref)>)")
            } else {
                result.replaceSubrange(fullRange, with: label.isEmpty ? rawHref : label)
            }
        }
        return result
    }
}

func cleanHTML(_ html: String, preserveLinks: Bool = false) -> String {
    guard !html.isEmpty else { return "" }
    var text = HTMLCleaner.convertAnchors(html, preserveLinks: preserveLinks)

    for (regex, template) in HTMLCleaner.replacements {
        text = HTMLCleaner.replace(regex, in: text, with: template)
    }

    text = HTMLCleaner.decodeEntities(text)
    text = HTMLCleaner.replace(HTMLCleaner.excessNewlines, in: text, with: "\n\n")

    return text.trimmingCharacters(in: .whitespacesAndNewlines)
}

func breakSentences(_ text: String) -> String {
    HTMLCleaner.replace(HTMLCleaner.sentenceBreak, in: text, with: "$1\n\n")
}
