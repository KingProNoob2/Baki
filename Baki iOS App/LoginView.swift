import SwiftUI
import WidgetKit

/// One-screen sign-in shared by iOS and macOS: school address, username and password.
struct LoginScreen: View {
    private enum Field { case username, password }

    @State private var school: School?
    @State private var showingSchoolPicker = false
    @State private var username = ""
    @State private var password = ""
    @State private var isLoggingIn = false
    @State private var errorMessage: String?
    @FocusState private var focus: Field?

    private var canSubmit: Bool {
        school != nil
            && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header
                fields
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                Button {
                    Task { await login() }
                } label: {
                    Group {
                        if isLoggingIn {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Přihlásit se").fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canSubmit || isLoggingIn)

                Text("Neoficiální aplikace pro Bakaláře. Přihlašovací údaje zůstávají v klíčence tohoto zařízení.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 400)
            .padding(.horizontal, 24)
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .sheet(isPresented: $showingSchoolPicker) {
            SchoolPicker { school = $0 }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 38))
                .foregroundStyle(.white)
                .frame(width: 84, height: 84)
                .background(Color.accentColor.gradient, in: .rect(cornerRadius: 22, style: .continuous))
            Text("Baki")
                .font(.largeTitle.bold())
            Text("Přihlaste se do Bakalářů")
                .foregroundStyle(.secondary)
        }
    }

    private var fields: some View {
        VStack(spacing: 0) {
            Button {
                showingSchoolPicker = true
            } label: {
                field(icon: "building.columns") {
                    if let school {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(school.name)
                                .lineLimit(1)
                            Text(school.host)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Vyberte školu")
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Divider().padding(.leading, 44)
            field(icon: "person") {
                TextField("Uživatelské jméno", text: $username)
                    .focused($focus, equals: .username)
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
                    #if os(iOS)
                    .textContentType(.username)
                    #endif
            }
            Divider().padding(.leading, 44)
            field(icon: "lock") {
                SecureField("Heslo", text: $password)
                    .focused($focus, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { if canSubmit { Task { await login() } } }
                    #if os(iOS)
                    .textContentType(.password)
                    #endif
            }
        }
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 16, style: .continuous))
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .disabled(isLoggingIn)
    }

    private func field<Content: View>(icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            content()
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    private func login() async {
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let pass = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSubmit else { return }

        isLoggingIn = true
        errorMessage = nil
        focus = nil

        do {
            try await BakiClient.shared.login(schoolURL: school?.schoolUrl ?? "", username: user, password: pass)
            WidgetCenter.shared.reloadTimelines(ofKind: "BakiTimetableWidget")
            NotificationCenter.default.post(name: .bakiDidSignIn, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoggingIn = false
    }
}
