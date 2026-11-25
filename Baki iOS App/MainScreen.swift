import SwiftUI
import UserNotifications

#if os(iOS)
import UIKit
#endif

struct RootView<Main: View>: View {
    enum AuthState {
        case checking
        case authenticated
        case unauthenticated
    }

    @State private var authState: AuthState = .checking
    /// The signed-in app: tabs on iOS, the sidebar window on the Mac.
    @ViewBuilder let main: () -> Main

    var body: some View {
        Group {
            switch authState {
            case .checking:
                ProgressView()
                    .task {
                        await checkAuth()
                    }

            case .authenticated:
                main()

            case .unauthenticated:
                NavigationStack {
                    LoginScreen()
                }
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
                #if os(iOS)
                NotificationService.shared.scheduleBackgroundRefresh()
                NotificationService.shared.startForegroundPolling()
                #endif
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

enum AppTab: String {
    case marks, timetable, homework, komens, more

    static let restoreKey = "restoreLastTab"
    static let lastKey = "lastTab"
}

enum SavedMode {
    static func load<T: RawRepresentable>(_ key: String, default fallback: T) -> T where T.RawValue == String {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: AppTab.restoreKey),
              let raw = defaults.string(forKey: "mode.\(key)"),
              let mode = T(rawValue: raw) else { return fallback }
        return mode
    }

    static func save<T: RawRepresentable>(_ key: String, _ mode: T) where T.RawValue == String {
        UserDefaults.standard.set(mode.rawValue, forKey: "mode.\(key)")
    }
}

private enum MoreDestination: Hashable {
    case noticeboard
}

#if os(iOS)
private enum MoreSection: String, CaseIterable, Identifiable, Hashable {
    case absence
    case certificate
    case noticeboard
    case predictor
    case themes
    case settings

    var id: Self { self }
}
#endif

struct MainTabView: View {
    @State private var unreadCount = 0
    @State private var selection: AppTab
    @State private var morePath: [MoreDestination] = []
    #if os(iOS)
    @State private var moreSplitSelection: MoreSection? = .absence
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif
    @State private var notificationService = NotificationService.shared
    @AppStorage(AppTab.lastKey) private var lastTab = AppTab.marks.rawValue

    init() {
        let defaults = UserDefaults.standard
        let restore = defaults.bool(forKey: AppTab.restoreKey)
        let saved = defaults.string(forKey: AppTab.lastKey).flatMap(AppTab.init(rawValue:))
        _selection = State(initialValue: restore ? saved ?? .marks : .marks)
    }

    #if os(iOS)
    private var isDuoInnerDisplay: Bool {
        DuoEnvironment.isInnerDisplay(
            horizontalSizeClass: horizontalSizeClass,
            verticalSizeClass: verticalSizeClass
        )
    }
    #endif

    var body: some View {
        TabView(selection: $selection) {
            Tab("Známky", systemImage: "list.number", value: AppTab.marks) {
                NavigationStack { MarksScreen() }
            }
            Tab("Rozvrh", systemImage: "calendar", value: AppTab.timetable) {
                NavigationStack { TimetableScreen() }
            }
            Tab("Úkoly", systemImage: "checklist", value: AppTab.homework) {
                NavigationStack { HomeworkScreen() }
            }
            Tab("Komens", systemImage: "envelope", value: AppTab.komens) {
                NavigationStack { KomensScreen() }
            }
            .badge(unreadCount)
            Tab("Více", systemImage: "ellipsis", value: AppTab.more) {
                #if os(iOS)
                if isDuoInnerDisplay {
                    MoreSplitScreen(selection: $moreSplitSelection)
                } else {
                    compactMoreTab
                }
                #else
                compactMoreTab
                #endif
            }
        }
        .duoPrefersTabBarCompression()
        .onChange(of: selection) {
            lastTab = selection.rawValue
        }
        .onAppear {
            consumePendingNotificationRoute()
        }
        .onChange(of: notificationService.pendingRoute) {
            consumePendingNotificationRoute()
        }
        .task { await refreshUnreadCount() }
        .task {
            #if os(iOS)
            await notificationService.requestInitialPermissionIfNeeded()
            #endif
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .bakiKomensReadChanged) {
                await refreshUnreadCount()
            }
        }
    }

    private func consumePendingNotificationRoute() {
        guard let route = notificationService.pendingRoute else { return }
        notificationService.pendingRoute = nil
        switch route {
        case .marks:
            selection = .marks
        case .timetable:
            selection = .timetable
        case .komens:
            selection = .komens
        case .noticeboard:
            selection = .more
            #if os(iOS)
            moreSplitSelection = .noticeboard
            if !isDuoInnerDisplay && morePath.last != .noticeboard {
                morePath = [.noticeboard]
            }
            #else
            if morePath.last != .noticeboard {
                morePath = [.noticeboard]
            }
            #endif
        }
    }

    private var compactMoreTab: some View {
        NavigationStack(path: $morePath) {
            MoreScreen()
                .navigationDestination(for: MoreDestination.self) { destination in
                    switch destination {
                    case .noticeboard:
                        NoticeboardScreen()
                    }
                }
        }
    }

    private func refreshUnreadCount() async {
        if let messages = try? await BakiClient.shared.fetchMessages(type: .received) {
            unreadCount = messages.filter(\.isUnread).count
        }
    }
}

struct MoreScreen: View {
    @State private var user: UserInfo?

    var body: some View {
        GroupedList {
            Section {
                accountRow
            }

            Section {
                NavigationLink {
                    AbsenceScreen()
                } label: {
                    Label("Absence", systemImage: "person.badge.clock")
                }
                NavigationLink {
                    CertificateScreen()
                } label: {
                    Label("Vysvědčení", systemImage: "graduationcap")
                }
                NavigationLink {
                    NoticeboardScreen()
                } label: {
                    Label("Nástěnka", systemImage: "pin")
                }
                NavigationLink {
                    PredictorScreen()
                } label: {
                    Label("Předvídač", systemImage: "wand.and.sparkles")
                }
                NavigationLink {
                    ThemesScreen()
                } label: {
                    Label("Témata", systemImage: "book.pages")
                }
            }

            Section {
                NavigationLink {
                    SettingsScreen()
                } label: {
                    Label("Nastavení", systemImage: "gearshape")
                }
            }
        }
        .navigationTitle("Více")
        .task {
            guard user == nil else { return }
            user = try? await BakiClient.shared.fetchUser()
        }
    }

    private var accountRow: some View {
        MoreAccountRow(user: user)
    }
}

private struct MoreAccountRow: View {
    let user: UserInfo?

    var body: some View {
        let name = user?.displayName ?? ""
        let details = [user?.className, user?.userTypeText].compactMap { $0 }.joined(separator: " · ")
        let school = user?.schoolName ?? (user == nil ? URL(string: CredentialStorage.baseURL)?.host() ?? "" : "")

        return HStack(spacing: 14) {
            SenderAvatar(name: name.isEmpty ? nil : name)
                .scaleEffect(1.25)
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 2) {
                Text(name.isEmpty ? "Účet" : name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                if !details.isEmpty {
                    Text(details)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !school.isEmpty {
                    Text(school)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

#if os(iOS)
private struct MoreSplitScreen: View {
    @Binding var selection: MoreSection?
    @State private var user: UserInfo?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    MoreAccountRow(user: user)
                }

                Section {
                    NavigationLink(value: MoreSection.absence) {
                        Label("Absence", systemImage: "person.badge.clock")
                    }
                    NavigationLink(value: MoreSection.certificate) {
                        Label("Vysvědčení", systemImage: "graduationcap")
                    }
                    NavigationLink(value: MoreSection.noticeboard) {
                        Label("Nástěnka", systemImage: "pin")
                    }
                    NavigationLink(value: MoreSection.predictor) {
                        Label("Předvídač", systemImage: "wand.and.sparkles")
                    }
                    NavigationLink(value: MoreSection.themes) {
                        Label("Témata", systemImage: "book.pages")
                    }
                }

                Section {
                    NavigationLink(value: MoreSection.settings) {
                        Label("Nastavení", systemImage: "gearshape")
                    }
                }
            }
            .navigationTitle("Více")
        } detail: {
            NavigationStack {
                detailContent
            }
            // Prevent nested splits inside More's detail column.
            .environment(\.allowsDuoSplit, false)
        }
        .task {
            guard user == nil else { return }
            user = try? await BakiClient.shared.fetchUser()
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection ?? .absence {
        case .absence:
            AbsenceScreen()
        case .certificate:
            CertificateScreen()
        case .noticeboard:
            NoticeboardScreen()
        case .predictor:
            PredictorScreen()
        case .themes:
            ThemesScreen()
        case .settings:
            SettingsScreen()
        }
    }
}
#endif

struct SettingsScreen: View {
    @State private var showingSignOutConfirmation = false
    @State private var notificationService = NotificationService.shared
    @AppStorage(AppTab.restoreKey) private var restoreLastTab = false

    private var schoolHost: String {
        let url = CredentialStorage.baseURL
        return URL(string: url)?.host() ?? url
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(version) (\(build))"
    }

    var body: some View {
        GroupedList {
            Section("Účet") {
                LabeledContent {
                    Text(schoolHost)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } label: {
                    Label("Škola", systemImage: "building.columns")
                }

                Button(role: .destructive) {
                    showingSignOutConfirmation = true
                } label: {
                    Label("Odhlásit se", systemImage: "rectangle.portrait.and.arrow.right")
                        .foregroundStyle(.red)
                }
            }

            #if os(iOS)
            notificationsSection
            PushServerSection()
            #endif

            Section {
                Toggle(isOn: $restoreLastTab) {
                    Label("Pamatovat si poslední stav", systemImage: "arrow.uturn.backward.circle")
                }
            } header: {
                Text("Aplikace")
            } footer: {
                Text("Po spuštění se otevře poslední záložka a v každé obrazovce poslední zvolené zobrazení (např. u rozvrhu, známek, úkolů a absence). Jinak se vždy otevřou Známky ve výchozím zobrazení.")
            }

            Section("O aplikaci") {
                LabeledContent {
                    Text(appVersion)
                } label: {
                    Label("Verze", systemImage: "info.circle")
                }
            }
        }
        .navigationTitle("Nastavení")
        .task {
            await notificationService.refreshAuthorizationStatus()
        }
        #if os(iOS)
        .onChange(of: [notificationService.marksEnabled, notificationService.komensEnabled,
                       notificationService.noticeboardEnabled, notificationService.timetableEnabled]) {
            Task { try? await PushService.shared.syncPreferences() }
        }
        #endif
        .confirmationDialog(
            "Odhlásit se?",
            isPresented: $showingSignOutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Odhlásit se", role: .destructive) {
                CredentialStorage.signOut()
            }
            Button("Zrušit", role: .cancel) {}
        }
    }

    #if os(iOS)
    @ViewBuilder
    private var notificationsSection: some View {
        Section {
            switch notificationService.authorizationStatus {
            case .notDetermined:
                Button {
                    Task { await notificationService.requestAuthorization() }
                } label: {
                    Label("Povolit oznámení", systemImage: "bell.badge")
                }

            case .denied:
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Oznámení zakázána · Otevřít Nastavení", systemImage: "bell.slash")
                }

            default:
                Toggle(isOn: Binding(
                    get: { notificationService.marksEnabled },
                    set: { notificationService.marksEnabled = $0 }
                )) {
                    Label("Nové známky", systemImage: "list.number")
                }

                Toggle(isOn: Binding(
                    get: { notificationService.komensEnabled },
                    set: { notificationService.komensEnabled = $0 }
                )) {
                    Label("Zprávy Komens", systemImage: "envelope")
                }

                Toggle(isOn: Binding(
                    get: { notificationService.noticeboardEnabled },
                    set: { notificationService.noticeboardEnabled = $0 }
                )) {
                    Label("Nástěnka", systemImage: "pin")
                }

                Toggle(isOn: Binding(
                    get: { notificationService.timetableEnabled },
                    set: { notificationService.timetableEnabled = $0 }
                )) {
                    Label("Změny v rozvrhu", systemImage: "calendar")
                }

                if !notificationService.isBackgroundRefreshAvailable {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Obnovení na pozadí je vypnuto · Otevřít Nastavení", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }

                Button {
                    Task { await notificationService.checkForUpdates(notify: true) }
                } label: {
                    HStack {
                        Label("Zkontrolovat nyní", systemImage: "arrow.clockwise")
                        Spacer()
                        if notificationService.isChecking {
                            ProgressView()
                        }
                    }
                }
                .disabled(notificationService.isChecking || !notificationService.anyCategoryEnabled)
            }
        } header: {
            Text("Oznámení")
        } footer: {
            if let lastCheck = notificationService.lastCheckDate {
                Text("Změny se kontrolují automaticky na pozadí přes Obnovení na pozadí v iOS. Poslední kontrola: \(lastCheck.formatted(date: .omitted, time: .shortened)).")
            } else {
                Text("Změny se kontrolují automaticky na pozadí přes Obnovení na pozadí v iOS.")
            }
        }
    }
    #endif
}
