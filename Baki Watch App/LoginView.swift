import SwiftUI
import WidgetKit

struct SchoolSelectScreen: View {
    @State private var selectedSchool: School?
    @State private var baseURL: String = CredentialStorage.baseURL
    @State private var showingSchoolPicker: Bool = false
    @State private var showLogin: Bool = false

    private var effectiveURL: String {
        baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("Vyberte školu")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Button {
                    showingSchoolPicker = true
                } label: {
                    if let selectedSchool {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selectedSchool.name)
                                .font(.footnote)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text(selectedSchool.host)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    } else {
                        Label("Vybrat školu", systemImage: "building.columns")
                    }
                }
                .tint(.blue)
                .buttonBorderShape(selectedSchool == nil ? .capsule : .roundedRectangle(radius: 14))

                TextField("Nebo zadejte URL", text: $baseURL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: baseURL) { _, newValue in
                        if let selectedSchool, newValue != selectedSchool.schoolUrl {
                            self.selectedSchool = nil
                        }
                    }

                Button("Pokračovat") {
                    if !effectiveURL.isEmpty {
                        showLogin = true
                    }
                }
                .tint(.blue)
                .disabled(effectiveURL.isEmpty)
            }
            .padding(.horizontal)
        }
        .sheet(isPresented: $showingSchoolPicker) {
            SchoolPicker { school in
                selectedSchool = school
                baseURL = school.schoolUrl
            }
        }
        .navigationDestination(isPresented: $showLogin) {
            LoginView(schoolURL: effectiveURL)
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
