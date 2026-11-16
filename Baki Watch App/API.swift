import Foundation
import SwiftUI
import WatchConnectivity
import WidgetKit
import KeychainSwift

extension Notification.Name {
    static let bakiDidSignIn = Notification.Name("bakiDidSignIn")
    static let bakiDidSignOut = Notification.Name("bakiDidSignOut")
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
        defaults?.removeObject(forKey: "cachedTimetable")
        keychain.delete("baseURL")
        keychain.delete("bearer")
        keychain.delete("refreshToken")
        WidgetCenter.shared.reloadTimelines(ofKind: "BakiTimetableWidget")
    }

    static func signOut() {
        clear()
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

    func fetchTimetable(date: Date? = nil, updatesCache: Bool = true) async throws -> TimetableResponse {
        let dateStr = BakiDate.string(from: date ?? Date())
        let path = "/api/3/timetable/actual?date=\(dateStr)"
        let data = try await performAuthorizedRequest(path: path, method: "GET")

        let response = try JSONDecoder().decode(TimetableResponse.self, from: data)

        if updatesCache {
            CredentialStorage.cacheTimetable(data)
            WidgetCenter.shared.reloadTimelines(ofKind: "BakiTimetableWidget")
        }

        return response
    }

    func fetchMarks() async throws -> MarksResponse {
        let path = "/api/3/marks"
        let data = try await performAuthorizedRequest(path: path, method: "GET")
        return try JSONDecoder().decode(MarksResponse.self, from: data)
    }

    enum MessageType: String {
        case received = "received"
        case noticeboard = "noticeboard"
    }

    func fetchMessages(type: MessageType) async throws -> [KomensMessage] {
        let path = "/api/3/komens/messages/\(type.rawValue)"
        let data = try await performAuthorizedRequest(path: path, method: "POST")
        let response = try JSONDecoder().decode(KomensResponse.self, from: data)
        let messages = response.messages ?? []

        return messages
            .map { ($0, $0.parsedDate ?? .distantPast) }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
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

    func markMessageAsRead(_ message: KomensMessage) async throws {
        let encodedId = message.id.addingPercentEncoding(withAllowedCharacters: Self.formAllowedCharacters) ?? message.id
        _ = try await performAuthorizedRequest(path: "/api/3/komens/message/\(encodedId)/mark-as-read", method: "PUT")
    }

    private func performAuthorizedRequest(path: String, method: String) async throws -> Data {
        let base = CredentialStorage.baseURL
        guard let url = URL(string: base + path) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(CredentialStorage.bearer)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            let refreshed = await refreshSession()
            guard refreshed else {
                throw APIError.unauthorized
            }
            var retryRequest = URLRequest(url: url)
            retryRequest.httpMethod = method
            retryRequest.setValue("Bearer \(CredentialStorage.bearer)", forHTTPHeaderField: "Authorization")
            let (retryData, retryResponse) = try await session.data(for: retryRequest)
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

struct InfoRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .bold()

                if let subtitle = subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct BakiHeaderModifier: ViewModifier {
    let title: String
    var blurred: Bool = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                Text(title)
                    .font(.title3)
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                    .background(blurred ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(.clear))
                    .allowsHitTesting(false)
            }
            .ignoresSafeArea(edges: .top)
    }
}

extension View {
    func bakiHeader(_ title: String, blurred: Bool = false) -> some View {
        modifier(BakiHeaderModifier(title: title, blurred: blurred))
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
}
