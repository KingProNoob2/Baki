#if os(macOS)
import SwiftUI

/// Sidebar destinations of the Mac app. Order matches the ⌘1–⌘9 shortcuts in the Přejít menu.
enum AppSection: String, CaseIterable, Identifiable {
    case marks, timetable, homework, komens, absence, certificate, noticeboard, predictor, themes

    static let lastKey = "lastSection"

    var id: Self { self }

    var title: String {
        switch self {
        case .marks: return "Známky"
        case .timetable: return "Rozvrh"
        case .homework: return "Úkoly"
        case .komens: return "Komens"
        case .absence: return "Absence"
        case .noticeboard: return "Nástěnka"
        case .predictor: return "Předvídač"
        case .certificate: return "Vysvědčení"
        case .themes: return "Témata"
        }
    }

    var systemImage: String {
        switch self {
        case .marks: return "list.number"
        case .timetable: return "calendar"
        case .homework: return "checklist"
        case .komens: return "envelope"
        case .absence: return "person.badge.clock"
        case .noticeboard: return "pin"
        case .predictor: return "wand.and.sparkles"
        case .certificate: return "graduationcap"
        case .themes: return "book.pages"
        }
    }

    @ViewBuilder
    var screen: some View {
        switch self {
        case .marks: MacMarksView()
        case .timetable: MacTimetableView()
        case .homework: MacHomeworkView()
        case .komens: MacMessagesView(type: .received)
        case .absence: MacAbsenceView()
        case .noticeboard: MacMessagesView(type: .noticeboard)
        case .predictor: MacPredictorView()
        case .certificate: MacCertificateView()
        case .themes: MacThemesView()
        }
    }
}

// MARK: - Menu command plumbing

/// Lets the Přejít menu switch the sidebar selection of the focused window.
struct SectionNavigator {
    let select: (AppSection) -> Void
}

/// Reloads the data of the screen currently shown in the focused window (⌘R).
struct RefreshAction {
    let perform: () -> Void
}

/// Week navigation of the timetable, driven from the Rozvrh menu.
struct TimetableCommands {
    let previousWeek: (() -> Void)?
    let nextWeek: (() -> Void)?
    let today: (() -> Void)?
}

extension FocusedValues {
    @Entry var sectionNavigator: SectionNavigator?
    @Entry var refreshAction: RefreshAction?
    @Entry var timetableCommands: TimetableCommands?
}

struct BakiCommands: Commands {
    @FocusedValue(\.sectionNavigator) private var navigator
    @FocusedValue(\.refreshAction) private var refresh
    @FocusedValue(\.timetableCommands) private var timetable

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Obnovit") { refresh?.perform() }
                .keyboardShortcut("r")
                .disabled(refresh == nil)
        }

        CommandMenu("Přejít") {
            ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { index, section in
                Button(section.title) { navigator?.select(section) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    .disabled(navigator == nil)
            }
        }

        CommandMenu("Rozvrh") {
            Button("Dnes") { timetable?.today?() }
                .keyboardShortcut("t")
                .disabled(timetable?.today == nil)
            Divider()
            Button("Předchozí týden") { timetable?.previousWeek?() }
                .keyboardShortcut("[")
                .disabled(timetable?.previousWeek == nil)
            Button("Další týden") { timetable?.nextWeek?() }
                .keyboardShortcut("]")
                .disabled(timetable?.nextWeek == nil)
        }
    }
}

// MARK: - Main window

/// Mail-style window: glass sidebar | list | detail. Screens fill the middle column and show the
/// selected item in the detail column through `MacDetailModel`.
struct MacMainView: View {
    @State private var unreadCount = 0
    @State private var user: UserInfo?
    @State private var detailModel = MacDetailModel()
    @State private var selection: AppSection?
    @AppStorage(AppSection.lastKey) private var lastSection = AppSection.marks.rawValue

    init() {
        let defaults = UserDefaults.standard
        let restore = defaults.bool(forKey: AppTab.restoreKey)
        let saved = defaults.string(forKey: AppSection.lastKey).flatMap(AppSection.init(rawValue:))
        _selection = State(initialValue: restore ? saved ?? .marks : .marks)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    sidebarRow(.marks)
                    sidebarRow(.timetable)
                    sidebarRow(.homework)
                    sidebarRow(.komens)
                }
                Section("Další") {
                    sidebarRow(.absence)
                    sidebarRow(.certificate)
                    sidebarRow(.noticeboard)
                    sidebarRow(.predictor)
                    sidebarRow(.themes)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
            .safeAreaInset(edge: .bottom, spacing: 0) { accountFooter }
        } content: {
            let section = selection ?? .marks
            NavigationStack {
                section.screen
            }
            // A fresh stack per section, so a pushed screen doesn't survive switching sidebar items.
            .id(section)
            .navigationSplitViewColumnWidth(min: 340, ideal: 420, max: 560)
        } detail: {
            MacDetailPane(model: detailModel)
        }
        .environment(detailModel)
        .focusedSceneValue(\.sectionNavigator, SectionNavigator { selection = $0 })
        .onChange(of: selection) {
            detailModel.reset()
            if let selection { lastSection = selection.rawValue }
        }
        .task { await refreshUnreadCount() }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .bakiKomensReadChanged) {
                await refreshUnreadCount()
            }
        }
        .task {
            for await notification in NotificationCenter.default.notifications(named: .bakiKomensUnreadCountDidChange) {
                if let count = notification.userInfo?["count"] as? Int {
                    unreadCount = count
                }
            }
        }
    }

    private func sidebarRow(_ section: AppSection) -> some View {
        // The tag must be applied after the badge, or the row can't be selected (Komens has a badge).
        Label {
            Text(section.title)
        } icon: {
            Image(systemName: section.systemImage)
                .foregroundStyle(.blue)
        }
        .badge(section == .komens ? unreadCount : 0)
        .tag(section)
    }

    /// Signed-in account at the bottom of the sidebar, with a shortcut to Settings.
    private var accountFooter: some View {
        let name = user?.displayName ?? ""
        let details = [user?.className, user?.userTypeText].compactMap { $0 }.joined(separator: " · ")

        return HStack(spacing: 10) {
            SenderAvatar(name: name.isEmpty ? nil : name)
                .scaleEffect(0.75)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text(name.isEmpty ? "Účet" : name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                if !details.isEmpty {
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Nastavení")
        }
        .padding(10)
        .glassEffect(.regular, in: .rect(cornerRadius: 16, style: .continuous))
        .padding(10)
        .task {
            guard user == nil else { return }
            user = try? await BakiClient.shared.fetchUser()
        }
    }

    private func refreshUnreadCount() async {
        if let messages = try? await BakiClient.shared.fetchMessages(type: .received) {
            unreadCount = messages.filter(\.isUnread).count
        }
    }
}

// MARK: - Settings window (⌘,)

struct MacSettingsView: View {
    @AppStorage(AppTab.restoreKey) private var restoreLastTab = false
    @State private var showingSignOutConfirmation = false

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
        Form {
            Section("Účet") {
                LabeledContent("Škola", value: schoolHost)
                Button("Odhlásit se…", role: .destructive) {
                    showingSignOutConfirmation = true
                }
            }

            Section {
                Toggle("Pamatovat si poslední stav", isOn: $restoreLastTab)
            } header: {
                Text("Aplikace")
            } footer: {
                Text("Po spuštění se otevře poslední sekce a v každé obrazovce poslední zvolené zobrazení. Jinak se vždy otevřou Známky ve výchozím zobrazení.")
            }

            Section("O aplikaci") {
                LabeledContent("Verze", value: appVersion)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .confirmationDialog("Odhlásit se?", isPresented: $showingSignOutConfirmation, titleVisibility: .visible) {
            Button("Odhlásit se", role: .destructive) {
                CredentialStorage.signOut()
            }
            Button("Zrušit", role: .cancel) {}
        }
    }
}
#endif
