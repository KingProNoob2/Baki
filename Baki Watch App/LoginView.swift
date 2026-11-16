import SwiftUI
import WidgetKit

struct SchoolSelectScreen: View {
    @State private var baseURL: String = CredentialStorage.baseURL
    @State private var showLogin: Bool = false

    var body: some View {
        VStack(spacing: 8) {
            Text("Enter your school URL")
                .font(.headline)
                .multilineTextAlignment(.center)

            TextField("URL", text: $baseURL)
                .padding()
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            Button("Continue") {
                let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    showLogin = true
                }
            }
            .tint(.blue)
        }
        .navigationDestination(isPresented: $showLogin) {
            LoginView(schoolURL: baseURL)
        }
    }
}

struct LoginView: View {
    let schoolURL: String
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var isLoggingIn: Bool = false
    @State private var errorMessage: String? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("Username and Password")
                    .font(.headline)

                TextField("Username", text: $username)
                    .padding()
                    .tint(.blue)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                SecureField("Password", text: $password)
                    .padding()
                    .tint(.blue)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 2)
                }

                Button("Login") {
                    Task {
                        await login()
                    }
                }
                .tint(.blue)
                .disabled(isLoggingIn)
                .opacity(isLoggingIn ? 0.6 : 1.0)
            }
            .padding()
        }
    }

    private func login() async {
        let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPass = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUser.isEmpty, !trimmedPass.isEmpty else {
            errorMessage = "Zadejte jméno a heslo"
            return
        }

        isLoggingIn = true
        errorMessage = nil

        do {
            try await BakiClient.shared.login(schoolURL: schoolURL, username: trimmedUser, password: trimmedPass)
            WidgetCenter.shared.reloadTimelines(ofKind: "BakiTimetableWidget")
            NotificationCenter.default.post(name: .bakiDidSignIn, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoggingIn = false
    }
}
