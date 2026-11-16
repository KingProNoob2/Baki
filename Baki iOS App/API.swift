import Foundation
import SwiftUI
#if os(iOS)
import WatchConnectivity
#endif
import WidgetKit
import KeychainSwift

extension Notification.Name {
    static let bakiDidSignIn = Notification.Name("bakiDidSignIn")
    static let bakiDidSignOut = Notification.Name("bakiDidSignOut")
    static let bakiKomensReadChanged = Notification.Name("bakiKomensReadChanged")
}

struct CredentialStorage {
    static let appGroupId = "group.com.kpn2.baki"
    private static let defaults = UserDefaults(suiteName: appGroupId)
    private static let keychain = KeychainSwift()

    static var baseURL: String {
        get { get("baseURL") }
        set { set(newValue, forKey: "baseURL") }
    }

    static var bearer: String {
        get { get("bearer") }
        set { set(newValue, forKey: "bearer") }
    }

    static var username: String {
        get { get("username") }
        set { set(newValue, forKey: "username") }
    }

    static var refreshToken: String {
        get { get("refreshToken") }
        set { set(newValue, forKey: "refreshToken") }
    }

    static var hasValidSession: Bool {
        !baseURL.isEmpty && (!bearer.isEmpty || !refreshToken.isEmpty)
    }

    static var cachedTimetable: TimetableResponse? {
        guard let data = defaults?.data(forKey: "cachedTimetable") else { return nil }
        return try? JSONDecoder().decode(TimetableResponse.self, from: data)
    }

    static func cacheTimetable(_ data: Data) {
        defaults?.set(data, forKey: "cachedTimetable")
    }

    static func get(_ key: String) -> String {
        if let val = defaults?.string(forKey: key), !val.isEmpty {
            return val
        }
        return keychain.get(key) ?? ""
    }

    static func set(_ value: String, forKey key: String) {
        defaults?.set(value, forKey: key)
        keychain.set(value, forKey: key)
    }

    static func clear() {
        defaults?.removeObject(forKey: "baseURL")
        defaults?.removeObject(forKey: "bearer")
        defaults?.removeObject(forKey: "refreshToken")
        defaults?.removeObject(forKey: "username")
        defaults?.removeObject(forKey: "cachedTimetable")
        keychain.delete("baseURL")
        keychain.delete("bearer")
        keychain.delete("refreshToken")
        keychain.delete("username")
    }

    static func signOut() {
        #if os(iOS)
        PushService.shared.disconnectOnSignOut()
        #endif
        clear()
        #if os(iOS)
        NotificationService.shared.clearState()
        #endif
        NotificationCenter.default.post(name: .bakiDidSignOut, object: nil)
    }
}

enum APIError: LocalizedError {
    case invalidURL
    case unauthorized
    case decodingError(Error)
    case serverError(Int)
    case noData

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Neplatná adresa školy"
        case .unauthorized:
            return "Neplatné přihlašovací údaje"
        case .decodingError(let err):
            return "Chyba zpracování dat: \(err.localizedDescription)"
        case .serverError(let code):
            return "Chyba serveru (\(code))"
        case .noData:
            return "Žádná data ze serveru"
        }
    }
}

@MainActor
final class BakiClient {
    static let shared = BakiClient()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    func login(schoolURL: String, username: String, password: String) async throws {
        var base = schoolURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !base.hasPrefix("http://") && !base.hasPrefix("https://") {
            base = "https://" + base
        }
        while base.hasSuffix("/") {
            base.removeLast()
        }

        guard let url = URL(string: base + "/api/login") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = [
            "client_id": "ANDR",
            "grant_type": "password",
            "username": username,
            "password": password
        ]
        request.httpBody = formBody(bodyParams)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.noData
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 400 || httpResponse.statusCode == 401 {
                throw APIError.unauthorized
            }
            throw APIError.serverError(httpResponse.statusCode)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let refreshToken = json["refresh_token"] as? String else {
            throw APIError.decodingError(
                NSError(domain: "BakiClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Nelze přečíst tokeny"])
            )
        }

        CredentialStorage.baseURL = base
        CredentialStorage.username = username
        CredentialStorage.bearer = accessToken
        CredentialStorage.refreshToken = refreshToken
    }

    private var refreshTask: Task<Bool, Never>?

    func refreshSession() async -> Bool {
        if let refreshTask {
            return await refreshTask.value
        }
        let task = Task { await performRefresh() }
        refreshTask = task
        let result = await task.value
        refreshTask = nil
        return result
    }

    private func performRefresh() async -> Bool {
        let base = CredentialStorage.baseURL
        let refreshToken = CredentialStorage.refreshToken
        guard !base.isEmpty, !refreshToken.isEmpty,
              let url = URL(string: base + "/api/login") else {
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = [
            "client_id": "ANDR",
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ]
        request.httpBody = formBody(bodyParams)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return false
            }
            if http.statusCode == 400 || http.statusCode == 401 {
                CredentialStorage.signOut()
                return false
            }
            guard http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let newAccess = json["access_token"] as? String else {
                return false
            }

            CredentialStorage.bearer = newAccess
            if let newRefresh = json["refresh_token"] as? String, !newRefresh.isEmpty {
                CredentialStorage.refreshToken = newRefresh
            }
            return true
        } catch {
            return false
        }
    }

    func fetchTimetable(date: Date? = nil, updatesCache: Bool = true, recordSnapshot: Bool = true) async throws -> TimetableResponse {
        let dateStr = BakiDate.string(from: date ?? Date())
        let path = "/api/3/timetable/actual?date=\(dateStr)"
        let data = try await performAuthorizedRequest(path: path, method: "GET")

        let response = try JSONDecoder().decode(TimetableResponse.self, from: data)

        if updatesCache {
            CredentialStorage.cacheTimetable(data)
            WidgetCenter.shared.reloadTimelines(ofKind: "BakiTimetableWidget")
        }

        #if os(iOS)
        if recordSnapshot {
            NotificationService.shared.recordTimetable(response)
        }
        #endif

        return response
    }

    func fetchMarks(recordSnapshot: Bool = true) async throws -> MarksResponse {
        let path = "/api/3/marks"
        let data = try await performAuthorizedRequest(path: path, method: "GET")
        let response = try JSONDecoder().decode(MarksResponse.self, from: data)
        #if os(iOS)
        if recordSnapshot {
            NotificationService.shared.recordMarks(response)
        }
        #endif
        return response
    }

    func fetchFinalMarks() async throws -> [CertificateTerm] {
        let path = "/api/3/marks/final"
        let data = try await performAuthorizedRequest(path: path, method: "GET")
        let response = try JSONDecoder().decode(FinalMarksResponse.self, from: data)
        return response.certificateTerms
    }

    func fetchSubjects() async throws -> [SubjectInfo] {
        let data = try await performAuthorizedRequest(path: "/api/3/subjects", method: "GET")
        let raw = try JSONDecoder().decode(SubjectsResponse.self, from: data).subjects
        var seen: [String: SubjectInfo] = [:]
        var order: [String] = []
        for item in raw where !item.subjectID.isEmpty {
            if let existing = seen[item.subjectID] {
                if let newTeacher = item.teacherName,
                   let existingTeacher = existing.teacherName,
                   !existingTeacher.localizedCaseInsensitiveContains(newTeacher) {
                    seen[item.subjectID] = SubjectInfo(
                        subjectID: existing.subjectID,
                        subjectName: existing.subjectName,
                        subjectAbbrev: existing.subjectAbbrev,
                        teacherID: existing.teacherID,
                        teacherName: "\(existingTeacher), \(newTeacher)",
                        teacherAbbrev: existing.teacherAbbrev
                    )
                }
            } else {
                seen[item.subjectID] = item
                order.append(item.subjectID)
            }
        }
        return order.compactMap { seen[$0] }
    }

    func fetchSubjectThemes(subjectId: String) async throws -> SubjectThemesResponse {
        let encodedId = subjectId.addingPercentEncoding(withAllowedCharacters: Self.formAllowedCharacters) ?? subjectId
        let data = try await performAuthorizedRequest(path: "/api/3/subjects/themes/\(encodedId)", method: "GET")
        return try JSONDecoder().decode(SubjectThemesResponse.self, from: data)
    }

    enum MessageType: String {
        case received = "received"
        case noticeboard = "noticeboard"
    }

    func fetchMessages(type: MessageType, recordSnapshot: Bool = true) async throws -> [KomensMessage] {
        let path = "/api/3/komens/messages/\(type.rawValue)"
        let data = try await performAuthorizedRequest(path: path, method: "POST")
        let response = try JSONDecoder().decode(KomensResponse.self, from: data)
        let messages = response.messages ?? []

        let sorted = messages
            .map { ($0, $0.parsedDate ?? .distantPast) }
            .sorted { $0.1 > $1.1 }
            .map(\.0)

        #if os(iOS)
        if recordSnapshot {
            NotificationService.shared.recordMessages(sorted, type: type)
        }
        #endif

        return sorted
    }

    func fetchUser() async throws -> UserInfo {
        let data = try await performAuthorizedRequest(path: "/api/3/user", method: "GET")
        return try JSONDecoder().decode(UserInfo.self, from: data)
    }

    func fetchAbsence() async throws -> AbsenceResponse {
        let data = try await performAuthorizedRequest(path: "/api/3/absence/student", method: "GET")
        return try JSONDecoder().decode(AbsenceResponse.self, from: data)
    }

    func fetchHomeworks(from: Date, to: Date) async throws -> [Homework] {
        let path = "/api/3/homeworks?from=\(BakiDate.string(from: from))&to=\(BakiDate.string(from: to))"
        let data = try await performAuthorizedRequest(path: path, method: "GET")
        return try JSONDecoder().decode(HomeworksResponse.self, from: data).homeworks ?? []
    }

    func setHomeworkDone(_ homework: Homework, done: Bool) async throws {
        let encodedId = homework.id.addingPercentEncoding(withAllowedCharacters: Self.formAllowedCharacters) ?? homework.id
        _ = try await performAuthorizedRequest(
            path: "/api/3/homeworks/\(encodedId)/student-done/\(done ? "true" : "false")",
            method: "PUT"
        )
    }

    func fetchMessageTypes() async throws -> KomensMessageTypesResponse {
        let data = try await performAuthorizedRequest(path: "/api/3/komens/message-types", method: "GET")
        return try JSONDecoder().decode(KomensMessageTypesResponse.self, from: data)
    }

    func sendMessage(_ message: NewKomensMessage) async throws {
        let body = try JSONEncoder().encode(message)
        _ = try await performAuthorizedRequest(
            path: "/api/3/komens/message",
            method: "POST",
            body: body,
            contentType: "application/json; charset=utf-8"
        )
    }

    func markMessageAsRead(_ message: KomensMessage) async throws {
        let encodedId = message.id.addingPercentEncoding(withAllowedCharacters: Self.formAllowedCharacters) ?? message.id
        _ = try await performAuthorizedRequest(path: "/api/3/komens/message/\(encodedId)/mark-as-read", method: "PUT")
    }

    func downloadAttachment(_ attachment: KomensAttachment) async throws -> URL {
        let encodedId = attachment.id.addingPercentEncoding(withAllowedCharacters: Self.formAllowedCharacters) ?? attachment.id
        let data = try await performAuthorizedRequest(path: "/api/3/komens/attachment/\(encodedId)", method: "GET")

        let folderName = encodedId.replacingOccurrences(of: "%", with: "_")
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Attachments", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let rawName = attachment.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fileName = (rawName.isEmpty ? "Příloha" : rawName).replacingOccurrences(of: "/", with: "_")
        let fileURL = folder.appendingPathComponent(fileName)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    private func performAuthorizedRequest(
        path: String,
        method: String,
        body: Data? = nil,
        contentType: String? = nil
    ) async throws -> Data {
        let base = CredentialStorage.baseURL
        guard let url = URL(string: base + path) else {
            throw APIError.invalidURL
        }

        func makeRequest() -> URLRequest {
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.setValue("Bearer \(CredentialStorage.bearer)", forHTTPHeaderField: "Authorization")
            if let contentType {
                request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            }
            request.httpBody = body
            return request
        }

        let (data, response) = try await session.data(for: makeRequest())
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            let refreshed = await refreshSession()
            guard refreshed else {
                throw APIError.unauthorized
            }
            let (retryData, retryResponse) = try await session.data(for: makeRequest())
            return try validated(retryData, retryResponse)
        }

        return try validated(data, response)
    }

    private func validated(_ data: Data, _ response: URLResponse) throws -> Data {
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 { throw APIError.unauthorized }
            guard (200..<300).contains(http.statusCode) else {
                throw APIError.serverError(http.statusCode)
            }
        }
        return data
    }

    private static let formAllowedCharacters: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return allowed
    }()

    private func formBody(_ params: [String: String]) -> Data? {
        let allowed = Self.formAllowedCharacters
        let string = params.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
        return string.data(using: .utf8)
    }
}

enum BakiDate {
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoStandard: ISO8601DateFormatter = ISO8601DateFormatter()

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let czechDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.dateFormat = "d. M. yyyy"
        return f
    }()

    private static let czechDateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.dateFormat = "d. M. yyyy HH:mm"
        return f
    }()

    private static let czechWeekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.dateFormat = "EEEE"
        return f
    }()

    static func parse(_ dateString: String?) -> Date? {
        guard let s = dateString, !s.isEmpty else { return nil }
        if let d = isoFractional.date(from: s) { return d }
        if let d = isoStandard.date(from: s) { return d }
        if let part = s.split(separator: "T").first, part.count == 10 {
            return dayFormatter.date(from: String(part))
        }
        return nil
    }

    static func string(from date: Date = Date()) -> String {
        dayFormatter.string(from: date)
    }

    static func formatCzechDate(_ dateString: String) -> String {
        guard let date = parse(dateString) else { return dateString }
        return czechDateFormatter.string(from: date)
    }

    static func formatDisplayDate(_ dateString: String) -> String {
        guard let date = parse(dateString) else { return dateString }
        let cal = Calendar.current
        let hasTime = cal.component(.hour, from: date) != 0 || cal.component(.minute, from: date) != 0
        return (hasTime ? czechDateTimeFormatter : czechDateFormatter).string(from: date)
    }

    static func weekdayName(dayOfWeek: Int, date: Date?) -> String {
        if let date {
            return czechWeekdayFormatter.string(from: date).capitalized
        }
        let fallback = [1: "Pondělí", 2: "Úterý", 3: "Středa", 4: "Čtvrtek", 5: "Pátek", 6: "Sobota", 7: "Neděle"]
        return fallback[dayOfWeek] ?? ""
    }
}

struct SkeletonPulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .redacted(reason: .placeholder)
            .opacity(isPulsing ? 0.45 : 0.95)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}

extension View {
    func skeletonPulse() -> some View {
        modifier(SkeletonPulseModifier())
    }
}

#if os(iOS)
@MainActor
final class PhoneLinkManager: NSObject, WCSessionDelegate {
    static let shared = PhoneLinkManager()

    private var currentActivity: NSUserActivity?

    override init() {
        super.init()
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }

    func openOnPhone(_ url: URL) {
        stopHandoff()

        let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        activity.webpageURL = url
        activity.title = url.host ?? url.absoluteString
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch = false
        activity.isEligibleForPublicIndexing = false
        activity.becomeCurrent()
        self.currentActivity = activity

        if WCSession.isSupported() {
            let session = WCSession.default
            if session.activationState != .activated {
                session.activate()
            }
            let payload: [String: Any] = [
                "action": "openURL",
                "url": url.absoluteString
            ]
            if session.isReachable {
                session.sendMessage(payload, replyHandler: nil) { [weak session] _ in
                    session?.transferUserInfo(payload)
                }
            } else if session.activationState == .activated {
                session.transferUserInfo(payload)
            }
        }
    }

    func stopHandoff() {
        currentActivity?.resignCurrent()
        currentActivity?.invalidate()
        currentActivity = nil
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
#endif

extension ContainerValues {
    @Entry var plainGroupedRow: Bool = false
}

extension View {
    /// Marks a row that draws its own cards, so macOS GroupedList doesn't wrap it in a glass card.
    func plainGroupedRow() -> some View {
        containerValue(\.plainGroupedRow, true)
    }
}

/// Inset grouped List on iOS. On macOS every Section becomes one Liquid Glass card with uniform
/// padding, built by hand because a Form/List there applies its own uneven row insets.
struct GroupedList<Content: View>: View {
    @ViewBuilder let content: Content

    #if os(macOS)
    private static var padding: CGFloat { 20 }
    #endif

    var body: some View {
        #if os(macOS)
        ScrollView {
            VStack(spacing: 20) {
                Group(sections: content) { sections in
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            if !section.header.isEmpty {
                                section.header
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, 6)
                            }

                            Group(subviews: section.content) { rows in
                                let stack = VStack(alignment: .leading, spacing: 12) {
                                    ForEach(rows.indices, id: \.self) { index in
                                        // Plain style stops NavigationLink/Button rows drawing a grey bordered box.
                                        rows[index]
                                            .buttonStyle(.plain)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .contentShape(.rect)
                                        if index < rows.count - 1 {
                                            Divider()
                                        }
                                    }
                                }

                                // A section that draws its own cards opts out of the outer glass card.
                                if rows.count == 1, rows[0].containerValues.plainGroupedRow {
                                    stack
                                } else {
                                    stack
                                        .padding(Self.padding)
                                        .glassEffect(.regular, in: .rect(cornerRadius: 24, style: .continuous))
                                }
                            }

                            if !section.footer.isEmpty {
                                section.footer
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 4)
                            }
                        }
                    }
                }
            }
            .padding(Self.padding)
        }
        #else
        List { content }
        #endif
    }
}

#if os(macOS)
import AppKit

// macOS shims for iOS-only SwiftUI/UIKit APIs used by the shared screens.
extension ToolbarItemPlacement {
    static var topBarTrailing: ToolbarItemPlacement { .automatic }
}

enum TitleDisplayModeShim {
    case automatic, inline, large
}

enum ListSectionSpacingShim {
    case `default`, compact
}

enum SearchToolbarBehaviorShim {
    case minimize
}

enum AutocapitalizationShim {
    case never, words, sentences, characters
}

extension View {
    func navigationBarTitleDisplayMode(_ mode: TitleDisplayModeShim) -> some View {
        toolbarTitleDisplayMode(mode == .inline ? .inline : .automatic)
    }
    // No macOS equivalent for section spacing or autocapitalization.
    func listSectionSpacing(_ spacing: ListSectionSpacingShim) -> some View { self }
    func listSectionSpacing(_ spacing: CGFloat) -> some View { self }
    // The iOS screens are compiled on the Mac too but never shown there.
    func searchToolbarBehavior(_ behavior: SearchToolbarBehaviorShim) -> some View { self }
    func textInputAutocapitalization(_ style: AutocapitalizationShim?) -> some View { self }

    /// GroupedList is already a grouped Form on macOS.
    func groupedList() -> some View { self }

    /// Liquid Glass card on macOS.
    func cardBackground(grouped: Bool = false) -> some View {
        glassEffect(.regular, in: .rect(cornerRadius: 14, style: .continuous))
    }
}
#else
extension View {
    func groupedList() -> some View {
        listStyle(.insetGrouped)
    }

    /// System secondary background card on iOS.
    func cardBackground(grouped: Bool = false) -> some View {
        background(
            Color(grouped ? UIColor.secondarySystemGroupedBackground : UIColor.secondarySystemBackground),
            in: .rect(cornerRadius: 14, style: .continuous)
        )
    }
}
#endif

