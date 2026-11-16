#if os(iOS)
import SwiftUI
import UIKit

/// Connects the app to a self-hosted baki-notify server (see /server) so new marks, messages and
/// timetable changes arrive as real pushes instead of waiting for iOS to schedule a background refresh.
@Observable
@MainActor
final class PushService {
    static let shared = PushService()

    private enum Key {
        static let serverURL = "push.serverURL"
        static let apiKey = "push.apiKey"
        static let connected = "push.connected"
        static let deviceToken = "push.deviceToken"
    }

    private(set) var isConnected: Bool
    private(set) var deviceToken: String?

    var serverURL: String {
        get { CredentialStorage.get(Key.serverURL) }
        set { CredentialStorage.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.serverURL) }
    }

    var apiKey: String {
        get { CredentialStorage.get(Key.apiKey) }
        set { CredentialStorage.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.apiKey) }
    }

    private init() {
        isConnected = UserDefaults.standard.bool(forKey: Key.connected)
        deviceToken = UserDefaults.standard.string(forKey: Key.deviceToken)
    }

    enum PushError: LocalizedError {
        case invalidServer
        case noDeviceToken
        case badKey
        case loginFailed
        case failed(Int)

        var errorDescription: String? {
            switch self {
            case .invalidServer: return "Neplatná adresa serveru"
            case .noDeviceToken: return "Zařízení zatím nemá push token. Povolte oznámení a zkuste to znovu."
            case .badKey: return "Nesprávný API klíč"
            case .loginFailed: return "Server se nepodařilo přihlásit do Bakalářů. Zkontrolujte heslo."
            case .failed(let code): return "Chyba serveru (\(code))"
            }
        }
    }

    // MARK: - Device token

    func registerForPush() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    func didReceiveDeviceToken(_ data: Data) {
        let token = data.map { String(format: "%02x", $0) }.joined()
        let changed = token != deviceToken
        deviceToken = token
        UserDefaults.standard.set(token, forKey: Key.deviceToken)
        if changed && isConnected {
            Task { try? await syncPreferences() }
        }
    }

    /// Apple uses a separate server for builds signed with the development push entitlement
    /// (anything run from Xcode), read here from the embedded provisioning profile.
    private var usesSandbox: Bool {
        guard let path = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision"),
              let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .isoLatin1),
              let range = text.range(of: #"aps-environment</key>\s*<string>\w+"#, options: .regularExpression)
        else { return false }
        return text[range].hasSuffix("development")
    }

    // MARK: - Server calls

    private func post(_ path: String, body: [String: Any]) async throws {
        guard let url = URL(string: serverURL + path), serverURL.hasPrefix("http") else {
            throw PushError.invalidServer
        }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PushError.failed(0) }
        switch http.statusCode {
        case 200..<300: return
        case 401: throw PushError.badKey
        case 403: throw PushError.loginFailed
        default: throw PushError.failed(http.statusCode)
        }
    }

    private func body(password: String? = nil) throws -> [String: Any] {
        guard let deviceToken else { throw PushError.noDeviceToken }
        let notifications = NotificationService.shared
        var body: [String: Any] = [
            "school_url": CredentialStorage.baseURL,
            "username": CredentialStorage.username,
            "device_token": deviceToken,
            "sandbox": usesSandbox,
            "marks": notifications.marksEnabled,
            "komens": notifications.komensEnabled,
            "noticeboard": notifications.noticeboardEnabled,
            "timetable": notifications.timetableEnabled
        ]
        if let password { body["password"] = password }
        return body
    }

    /// Registers this device and the account with the server. The password is sent once so the
    /// server can poll Bakaláři; the app doesn't store it.
    func connect(password: String) async throws {
        try await post("/v1/register", body: body(password: password))
        isConnected = true
        UserDefaults.standard.set(true, forKey: Key.connected)
        // The server takes over, so the app stops polling by itself.
        NotificationService.shared.scheduleBackgroundRefresh()
    }

    /// Sends changed notification categories (or a new device token) to the server.
    func syncPreferences() async throws {
        guard isConnected else { return }
        try await post("/v1/update", body: body())
    }

    func disconnect() async {
        if let body = try? body() {
            try? await post("/v1/unregister", body: body)
        }
        markDisconnected()
    }

    /// Called while signing out, before the credentials are wiped.
    func disconnectOnSignOut() {
        guard isConnected, let body = try? body() else {
            markDisconnected()
            return
        }
        markDisconnected()
        let serverURL = serverURL, apiKey = apiKey
        Task.detached {
            guard let url = URL(string: serverURL + "/v1/unregister") else { return }
            var request = URLRequest(url: url, timeoutInterval: 10)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            _ = try? await URLSession.shared.data(for: request)
        }
    }

    private func markDisconnected() {
        isConnected = false
        UserDefaults.standard.set(false, forKey: Key.connected)
        NotificationService.shared.scheduleBackgroundRefresh()
    }
}

/// Settings section for connecting to the push server.
struct PushServerSection: View {
    @State private var push = PushService.shared
    @State private var serverURL = PushService.shared.serverURL
    @State private var apiKey = PushService.shared.apiKey
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        Section {
            if push.isConnected {
                Label("Připojeno k serveru", systemImage: "checkmark.icloud")
                    .foregroundStyle(.green)
                Button(role: .destructive) {
                    Task {
                        isWorking = true
                        await push.disconnect()
                        isWorking = false
                    }
                } label: {
                    Label("Odpojit", systemImage: "icloud.slash")
                }
                .disabled(isWorking)
            } else {
                TextField("Adresa serveru (https://…)", text: $serverURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                SecureField("API klíč", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Heslo do Bakalářů", text: $password)
                Button {
                    Task { await connect() }
                } label: {
                    HStack {
                        Label("Připojit", systemImage: "icloud.and.arrow.up")
                        Spacer()
                        if isWorking { ProgressView() }
                    }
                }
                .disabled(isWorking || serverURL.isEmpty || apiKey.isEmpty || password.isEmpty)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Push server")
        } footer: {
            Text(push.isConnected
                 ? "Nové známky, zprávy a změny rozvrhu posílá váš server. Aplikace už je sama na pozadí nekontroluje."
                 : "Volitelné. Vlastní server kontroluje Bakaláře každé dvě minuty a pošle upozornění hned. Heslo se odešle jen na váš server a aplikace si ho nepamatuje.")
        }
    }

    private func connect() async {
        isWorking = true
        errorMessage = nil
        push.serverURL = serverURL
        push.apiKey = apiKey
        do {
            try await push.connect(password: password)
            password = ""
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }
}
#endif
