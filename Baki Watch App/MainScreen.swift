import SwiftUI

struct RootView: View {
    enum AuthState {
        case checking
        case authenticated
        case unauthenticated
    }

    @State private var authState: AuthState = .checking

    var body: some View {
        Group {
            switch authState {
            case .checking:
                OverviewSkeleton()
                    .task {
                        await checkAuth()
                    }

            case .authenticated:
                Overview()

            case .unauthenticated:
                SchoolSelectScreen()
            }
        }
        .id(authState)
        .task {
            for await _ in NotificationCenter.default.notifications(named: .bakiDidSignOut) {
                authState = .unauthenticated
            }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .bakiDidSignIn) {
                authState = .authenticated
            }
        }
    }

    private func checkAuth() async {
        guard CredentialStorage.hasValidSession else {
            authState = .unauthenticated
            return
        }

        let success = await BakiClient.shared.refreshSession()
        if success || CredentialStorage.hasValidSession {
            authState = .authenticated
        } else {
            authState = .unauthenticated
        }
    }
}

struct MainScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingSignOutConfirmation = false

    private let columns = [GridItem(.adaptive(minimum: 120))]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 5) {
                NavigationLink("Známky") {
                    MarksScreen()
                } .tint(.blue)
                NavigationLink("Rozvrh") {
                    TimetableScreen()
                } .tint(.orange)
                NavigationLink("Komens") {
                    KomensScreen()
                } .tint(.red)
                NavigationLink("Úkoly") {
                    HomeworkScreen()
                } .tint(.green)
            }
            .padding(.top, 60)

            Button(role: .destructive) {
                showingSignOutConfirmation = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("Odhlásit se")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 20)
        }
        .bakiHeader("Menu")
        .confirmationDialog(
            "Odhlásit se?",
            isPresented: $showingSignOutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Odhlásit se", role: .destructive) {
                signOut()
            }
            Button("Zrušit", role: .cancel) {}
        }
    }

    private func signOut() {
        CredentialStorage.signOut()
        dismiss()
    }
}

#Preview {
    NavigationStack {
        MainScreen()
    }
}
