import Foundation
import Observation
import UserNotifications

#if os(iOS)
import BackgroundTasks
import UIKit
#endif

enum NotificationRoute: String, Hashable, Sendable {
    case marks
    case timetable
    case komens
    case noticeboard
}

enum NotificationPreferenceKey {
    static let marks = "notifications.marks"
    static let komens = "notifications.komens"
    static let noticeboard = "notifications.noticeboard"
    static let timetable = "notifications.timetable"
    static let lastCheckDate = "notifications.lastCheckDate"
    static let didRequestInitialPermission = "notifications.didRequestInitialPermission"
}

@Observable
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()
    static let refreshTaskIdentifier = "com.kpn2.Baki.refresh"

    var pendingRoute: NotificationRoute?
    var authorizationStatus: UNAuthorizationStatus = .notDetermined
    var isChecking = false
    var marksEnabled: Bool {
        didSet {
            UserDefaults.standard.set(marksEnabled, forKey: NotificationPreferenceKey.marks)
            if marksEnabled {
                Task { await seedCategoryIfNeeded(.marks) }
            }
        }
    }
    var komensEnabled: Bool {
        didSet {
            UserDefaults.standard.set(komensEnabled, forKey: NotificationPreferenceKey.komens)
            if komensEnabled {
                Task { await seedCategoryIfNeeded(.komens) }
            }
        }
    }
    var noticeboardEnabled: Bool {
        didSet {
            UserDefaults.standard.set(noticeboardEnabled, forKey: NotificationPreferenceKey.noticeboard)
            if noticeboardEnabled {
                Task { await seedCategoryIfNeeded(.noticeboard) }
            }
        }
    }
    var timetableEnabled: Bool {
        didSet {
            UserDefaults.standard.set(timetableEnabled, forKey: NotificationPreferenceKey.timetable)
            if timetableEnabled {
                Task { await seedCategoryIfNeeded(.timetable) }
            }
        }
    }
    var lastCheckDate: Date?

    private static let snapshotStorageKey = "notifications.snapshot.v1"

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let shortCzechDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.dateFormat = "E d. M."
        return f
    }()

    private override init() {
        UserDefaults.standard.register(defaults: [
            NotificationPreferenceKey.marks: true,
            NotificationPreferenceKey.komens: true,
            NotificationPreferenceKey.noticeboard: true,
            NotificationPreferenceKey.timetable: true
        ])
        let defaults = UserDefaults.standard
        self.marksEnabled = defaults.bool(forKey: NotificationPreferenceKey.marks)
        self.komensEnabled = defaults.bool(forKey: NotificationPreferenceKey.komens)
        self.noticeboardEnabled = defaults.bool(forKey: NotificationPreferenceKey.noticeboard)
        self.timetableEnabled = defaults.bool(forKey: NotificationPreferenceKey.timetable)
        let ts = defaults.double(forKey: NotificationPreferenceKey.lastCheckDate)
        self.lastCheckDate = ts > 0 ? Date(timeIntervalSince1970: ts) : nil
        super.init()
    }

    var anyCategoryEnabled: Bool {
        marksEnabled || komensEnabled || noticeboardEnabled || timetableEnabled
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional
    }

    // MARK: - Setup & Permissions

    func configure() {
        UNUserNotificationCenter.current().delegate = self
        Task { await refreshAuthorizationStatus() }
        #if os(iOS)
        registerBackgroundTask()
        #endif
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        UserDefaults.standard.set(true, forKey: NotificationPreferenceKey.didRequestInitialPermission)
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorizationStatus()
            if granted {
                await seedBaselineIfNeeded()
                scheduleBackgroundRefresh()
            }
            return granted
        } catch {
            await refreshAuthorizationStatus()
            return false
        }
    }

    func requestInitialPermissionIfNeeded() async {
        await refreshAuthorizationStatus()
        guard authorizationStatus == .notDetermined else {
            if isAuthorized {
                await seedBaselineIfNeeded()
                scheduleBackgroundRefresh()
            }
            return
        }
        guard !UserDefaults.standard.bool(forKey: NotificationPreferenceKey.didRequestInitialPermission) else {
            return
        }
        _ = await requestAuthorization()
    }

    // MARK: - Background Task Scheduling

    #if os(iOS)
    private var didRegisterBackgroundTask = false

    private func registerBackgroundTask() {
        guard !didRegisterBackgroundTask else { return }
        didRegisterBackgroundTask = true

        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTaskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                await NotificationService.shared.handleAppRefresh(task: refreshTask)
            }
        }
    }

    func scheduleBackgroundRefresh() {
        // With a push server connected, it does the checking instead.
        guard CredentialStorage.hasValidSession, anyCategoryEnabled, !PushService.shared.isConnected else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.refreshTaskIdentifier)
            return
        }

        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 5 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Ignored on simulator or when Background App Refresh is disabled in Settings.
        }
    }

    private func handleAppRefresh(task: BGAppRefreshTask) async {
        scheduleBackgroundRefresh()

        let workTask = Task { @MainActor in
            await self.checkForUpdates(notify: true)
        }

        task.expirationHandler = {
            workTask.cancel()
        }

        let success = await workTask.value
        task.setTaskCompleted(success: success)
    }
    #else
    func scheduleBackgroundRefresh() {}
    #endif

    // MARK: - Session & Snapshot Lifecycle

    func clearState() {
        UserDefaults.standard.removeObject(forKey: Self.snapshotStorageKey)
        UserDefaults.standard.removeObject(forKey: NotificationPreferenceKey.lastCheckDate)
        lastCheckDate = nil
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().setBadgeCount(0)
        #if os(iOS)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.refreshTaskIdentifier)
        #endif
    }

    func updateBadgeCount(_ count: Int) {
        #if os(iOS)
        UNUserNotificationCenter.current().setBadgeCount(max(0, count))
        #endif
    }

    // MARK: - Foreground Recording (prevents duplicate alerts for items already viewed in-app)

    func recordMarks(_ response: MarksResponse) {
        var snapshot = loadSnapshot()
        let ids = response.subjects.flatMap { $0.marks.map(\.id) }
        var set = snapshot.seenMarkIds ?? []
        set.formUnion(ids)
        snapshot.seenMarkIds = set
        saveSnapshot(snapshot)
    }

    func recordMessages(_ messages: [KomensMessage], type: BakiClient.MessageType) {
        var snapshot = loadSnapshot()
        let ids = messages.map(\.id)
        switch type {
        case .received:
            var set = snapshot.seenKomensIds ?? []
            set.formUnion(ids)
            snapshot.seenKomensIds = set
            updateBadgeCount(messages.filter(\.isUnread).count)
        case .noticeboard:
            var set = snapshot.seenNoticeboardIds ?? []
            set.formUnion(ids)
            snapshot.seenNoticeboardIds = set
        }
        saveSnapshot(snapshot)
    }

    func recordTimetable(_ response: TimetableResponse) {
        var snapshot = loadSnapshot()
        let todayKey = Self.dayKey(for: Date())
        let yesterdayKey = Self.dayKey(for: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())

        var days = snapshot.timetableDays ?? [:]
        var changeKeys = snapshot.notifiedChangeKeys

        for day in response.days {
            guard let key = Self.normalizedDayKey(day.date), key >= todayKey else { continue }
            let daySnap = Self.makeDaySnapshot(day: day, in: response)
            days[key] = daySnap
            for atom in daySnap.atoms where !atom.changeType.isEmpty || !atom.changeDescription.isEmpty || !atom.changeTypeName.isEmpty {
                changeKeys.insert(Self.changeKey(dayKey: key, atom: atom))
            }
        }

        snapshot.timetableDays = Self.prunedDays(days, minDayKey: yesterdayKey)
        snapshot.notifiedChangeKeys = Self.prunedChangeKeys(changeKeys, minDayKey: yesterdayKey)
        saveSnapshot(snapshot)
    }

    // MARK: - Baseline Seeding & Update Checking

    private enum Category {
        case marks, komens, noticeboard, timetable
    }

    func seedBaselineIfNeeded() async {
        guard CredentialStorage.hasValidSession else { return }
        let snapshot = loadSnapshot()

        let needMarks = marksEnabled && snapshot.seenMarkIds == nil
        let needKomens = komensEnabled && snapshot.seenKomensIds == nil
        let needNoticeboard = noticeboardEnabled && snapshot.seenNoticeboardIds == nil
        let needTimetable = timetableEnabled && snapshot.timetableDays == nil

        guard needMarks || needKomens || needNoticeboard || needTimetable else { return }
        _ = await checkForUpdates(notify: false)
    }

    private func seedCategoryIfNeeded(_ category: Category) async {
        guard CredentialStorage.hasValidSession else { return }
        let snapshot = loadSnapshot()

        switch category {
        case .marks:
            guard snapshot.seenMarkIds == nil else { return }
            if let response = try? await BakiClient.shared.fetchMarks(recordSnapshot: false) {
                recordMarks(response)
            }
        case .komens:
            guard snapshot.seenKomensIds == nil else { return }
            if let messages = try? await BakiClient.shared.fetchMessages(type: .received, recordSnapshot: false) {
                recordMessages(messages, type: .received)
            }
        case .noticeboard:
            guard snapshot.seenNoticeboardIds == nil else { return }
            if let messages = try? await BakiClient.shared.fetchMessages(type: .noticeboard, recordSnapshot: false) {
                recordMessages(messages, type: .noticeboard)
            }
        case .timetable:
            guard snapshot.timetableDays == nil else { return }
            if let week1 = try? await BakiClient.shared.fetchTimetable(date: Date(), updatesCache: true, recordSnapshot: false) {
                recordTimetable(week1)
            }
            if let nextWeekDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()),
               let week2 = try? await BakiClient.shared.fetchTimetable(date: nextWeekDate, updatesCache: false, recordSnapshot: false) {
                recordTimetable(week2)
            }
        }
    }

    /// Background refreshes are scheduled by iOS and can be hours apart, so also check when the app
    /// comes to the foreground if the last check is older than a few minutes.
    func checkOnForegroundIfStale() async {
        #if os(iOS)
        let pushConnected = PushService.shared.isConnected
        #else
        let pushConnected = false
        #endif
        guard anyCategoryEnabled, isAuthorized, !pushConnected else { return }
        if let lastCheckDate, Date().timeIntervalSince(lastCheckDate) < 5 * 60 { return }
        await checkForUpdates(notify: true)
    }

    @discardableResult
    func checkForUpdates(notify: Bool) async -> Bool {
        guard !isChecking else { return false }
        guard CredentialStorage.hasValidSession else { return false }

        isChecking = true
        defer { isChecking = false }

        await refreshAuthorizationStatus()
        let canDeliverAlerts = notify && isAuthorized

        let checkMarks = marksEnabled
        let checkKomens = komensEnabled
        let checkNoticeboard = noticeboardEnabled
        let checkTimetable = timetableEnabled

        guard checkMarks || checkKomens || checkNoticeboard || checkTimetable else {
            return true
        }

        async let marksResult: MarksResponse? = checkMarks ? (try? await BakiClient.shared.fetchMarks(recordSnapshot: false)) : nil
        async let komensResult: [KomensMessage]? = checkKomens ? (try? await BakiClient.shared.fetchMessages(type: .received, recordSnapshot: false)) : nil
        async let noticeboardResult: [KomensMessage]? = checkNoticeboard ? (try? await BakiClient.shared.fetchMessages(type: .noticeboard, recordSnapshot: false)) : nil
        async let thisWeekResult: TimetableResponse? = checkTimetable ? (try? await BakiClient.shared.fetchTimetable(date: Date(), updatesCache: true, recordSnapshot: false)) : nil
        async let nextWeekResult: TimetableResponse? = {
            guard checkTimetable,
                  let nextDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) else { return nil }
            return try? await BakiClient.shared.fetchTimetable(date: nextDate, updatesCache: false, recordSnapshot: false)
        }()

        let marks = await marksResult
        let komens = await komensResult
        let noticeboard = await noticeboardResult
        let week1 = await thisWeekResult
        let week2 = await nextWeekResult

        var snapshot = loadSnapshot()
        var anyFetchSucceeded = false

        if let marks {
            anyFetchSucceeded = true
            processMarks(marks, snapshot: &snapshot, notify: canDeliverAlerts)
        }

        if let komens {
            anyFetchSucceeded = true
            updateBadgeCount(komens.filter(\.isUnread).count)
            processKomens(komens, snapshot: &snapshot, notify: canDeliverAlerts)
        }

        if let noticeboard {
            anyFetchSucceeded = true
            processNoticeboard(noticeboard, snapshot: &snapshot, notify: canDeliverAlerts)
        }

        let timetableResponses = [week1, week2].compactMap { $0 }
        if !timetableResponses.isEmpty {
            anyFetchSucceeded = true
            processTimetable(timetableResponses, snapshot: &snapshot, notify: canDeliverAlerts)
        }

        saveSnapshot(snapshot)
        if anyFetchSucceeded {
            let now = Date()
            lastCheckDate = now
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: NotificationPreferenceKey.lastCheckDate)
        }
        return anyFetchSucceeded
    }

    // MARK: - Diff Processors

    private func processMarks(_ response: MarksResponse, snapshot: inout NotificationSnapshot, notify: Bool) {
        let allPairs: [(subject: Subject, mark: Mark)] = response.subjects.flatMap { subjectMarks in
            subjectMarks.marks.map { (subjectMarks.subject, $0) }
        }
        let allIds = Set(allPairs.map { $0.mark.id })

        guard let existing = snapshot.seenMarkIds else {
            snapshot.seenMarkIds = allIds
            return
        }

        let newPairs = allPairs.filter { !existing.contains($0.mark.id) }
        snapshot.seenMarkIds = existing.union(allIds)

        guard notify, !newPairs.isEmpty else { return }

        if newPairs.count <= 3 {
            for (subject, mark) in newPairs {
                let subjectName = subject.name.isEmpty ? subject.displayName : subject.name
                let title = "Nová známka · \(subjectName)"
                var parts: [String] = []
                if !mark.displayText.isEmpty {
                    parts.append(mark.displayText)
                }
                if let caption = mark.caption?.trimmingCharacters(in: .whitespacesAndNewlines), !caption.isEmpty {
                    parts.append(caption)
                } else if let theme = mark.theme?.trimmingCharacters(in: .whitespacesAndNewlines), !theme.isEmpty {
                    parts.append(theme)
                }
                var body = parts.joined(separator: " · ")
                if let weight = mark.weight, weight > 0 {
                    body += body.isEmpty ? "Váha \(weight)" : " (váha \(weight))"
                }
                if body.isEmpty {
                    body = "Byla zapsána nová známka."
                }

                postNotification(
                    identifier: "baki.mark.\(mark.id)",
                    title: title,
                    body: body,
                    threadIdentifier: "marks",
                    route: .marks
                )
            }
        } else {
            let previewItems = newPairs.prefix(4).map { pair in
                "\(pair.subject.displayName): \(pair.mark.displayText)"
            }
            let remaining = newPairs.count - previewItems.count
            var body = previewItems.joined(separator: ", ")
            if remaining > 0 {
                body += " a \(remaining) další"
            }
            postNotification(
                identifier: "baki.marks.batch.\(Int(Date().timeIntervalSince1970))",
                title: "Nové známky (\(newPairs.count))",
                body: body,
                threadIdentifier: "marks",
                route: .marks
            )
        }
    }

    private func processKomens(_ messages: [KomensMessage], snapshot: inout NotificationSnapshot, notify: Bool) {
        let allIds = Set(messages.map(\.id))
        guard let existing = snapshot.seenKomensIds else {
            snapshot.seenKomensIds = allIds
            return
        }

        let newMessages = messages.filter { !existing.contains($0.id) && $0.read != true }
        snapshot.seenKomensIds = existing.union(allIds)

        guard notify, !newMessages.isEmpty else { return }

        if newMessages.count <= 3 {
            for message in newMessages {
                let sender = message.sender?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? message.relevantName?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? ""
                let title = sender.isEmpty ? "Nová zpráva Komens" : "Komens · \(sender)"
                let subtitle = message.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let preview = Self.previewText(fromHTML: message.text)
                let body = preview.isEmpty ? (subtitle.isEmpty ? "Máte novou zprávu v Komens." : subtitle) : preview

                postNotification(
                    identifier: "baki.komens.\(message.id)",
                    title: title,
                    subtitle: preview.isEmpty ? nil : (subtitle.isEmpty ? nil : subtitle),
                    body: body,
                    threadIdentifier: "komens",
                    route: .komens
                )
            }
        } else {
            let senders = Array(Set(newMessages.compactMap { $0.sender?.name ?? $0.relevantName })).prefix(3)
            let body = senders.isEmpty
                ? "Máte \(newMessages.count) nových zpráv v Komens."
                : "Od: \(senders.joined(separator: ", "))"
            postNotification(
                identifier: "baki.komens.batch.\(Int(Date().timeIntervalSince1970))",
                title: "Nové zprávy Komens (\(newMessages.count))",
                body: body,
                threadIdentifier: "komens",
                route: .komens
            )
        }
    }

    private func processNoticeboard(_ messages: [KomensMessage], snapshot: inout NotificationSnapshot, notify: Bool) {
        let allIds = Set(messages.map(\.id))
        guard let existing = snapshot.seenNoticeboardIds else {
            snapshot.seenNoticeboardIds = allIds
            return
        }

        let newMessages = messages.filter { !existing.contains($0.id) }
        snapshot.seenNoticeboardIds = existing.union(allIds)

        guard notify, !newMessages.isEmpty else { return }

        if newMessages.count <= 3 {
            for message in newMessages {
                let sender = message.sender?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? message.relevantName?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? ""
                let title = sender.isEmpty ? "Nový příspěvek na nástěnce" : "Nástěnka · \(sender)"
                let subtitle = message.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let preview = Self.previewText(fromHTML: message.text)
                let body = preview.isEmpty ? (subtitle.isEmpty ? "Na nástěnce přibyla nová zpráva." : subtitle) : preview

                postNotification(
                    identifier: "baki.noticeboard.\(message.id)",
                    title: title,
                    subtitle: preview.isEmpty ? nil : (subtitle.isEmpty ? nil : subtitle),
                    body: body,
                    threadIdentifier: "noticeboard",
                    route: .noticeboard
                )
            }
        } else {
            postNotification(
                identifier: "baki.noticeboard.batch.\(Int(Date().timeIntervalSince1970))",
                title: "Nástěnka (\(newMessages.count) nových)",
                body: "Na nástěnce přibyly nové příspěvky.",
                threadIdentifier: "noticeboard",
                route: .noticeboard
            )
        }
    }

    private func processTimetable(_ responses: [TimetableResponse], snapshot: inout NotificationSnapshot, notify: Bool) {
        let todayKey = Self.dayKey(for: Date())
        let yesterdayKey = Self.dayKey(for: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())

        var latestDays: [String: TimetableDaySnapshot] = [:]
        for response in responses {
            for day in response.days {
                guard let key = Self.normalizedDayKey(day.date), key >= todayKey else { continue }
                latestDays[key] = Self.makeDaySnapshot(day: day, in: response)
            }
        }

        guard let previousDays = snapshot.timetableDays else {
            var initialDays: [String: TimetableDaySnapshot] = [:]
            var changeKeys = snapshot.notifiedChangeKeys
            for (key, daySnap) in latestDays {
                initialDays[key] = daySnap
                for atom in daySnap.atoms where atom.hasChange {
                    changeKeys.insert(Self.changeKey(dayKey: key, atom: atom))
                }
            }
            snapshot.timetableDays = Self.prunedDays(initialDays, minDayKey: yesterdayKey)
            snapshot.notifiedChangeKeys = Self.prunedChangeKeys(changeKeys, minDayKey: yesterdayKey)
            return
        }

        var mergedDays = previousDays
        var changeKeys = snapshot.notifiedChangeKeys
        var changedNotifications: [(dayKey: String, summary: String)] = []

        for key in latestDays.keys.sorted() {
            guard let newDay = latestDays[key] else { continue }

            if let oldDay = previousDays[key] {
                if oldDay != newDay {
                    for atom in newDay.atoms where atom.hasChange {
                        changeKeys.insert(Self.changeKey(dayKey: key, atom: atom))
                    }
                    let summary = Self.describeTimetableDiff(old: oldDay, new: newDay)
                    changedNotifications.append((key, summary))
                }
            } else {
                // Day newly entered the 2-week window: only notify if it already carries an unseen Change.
                let unseenChangedAtoms = newDay.atoms.filter { atom in
                    atom.hasChange && !changeKeys.contains(Self.changeKey(dayKey: key, atom: atom))
                }
                for atom in unseenChangedAtoms {
                    changeKeys.insert(Self.changeKey(dayKey: key, atom: atom))
                }
                if !unseenChangedAtoms.isEmpty {
                    let summary = Self.describeChangedAtoms(unseenChangedAtoms)
                    changedNotifications.append((key, summary))
                }
            }

            mergedDays[key] = newDay
        }

        snapshot.timetableDays = Self.prunedDays(mergedDays, minDayKey: yesterdayKey)
        snapshot.notifiedChangeKeys = Self.prunedChangeKeys(changeKeys, minDayKey: yesterdayKey)

        guard notify, !changedNotifications.isEmpty else { return }

        if changedNotifications.count <= 3 {
            for item in changedNotifications {
                let dateLabel = Self.formattedDayLabel(forDayKey: item.dayKey)
                postNotification(
                    identifier: "baki.timetable.\(item.dayKey).\(Int(Date().timeIntervalSince1970))",
                    title: "Změna v rozvrhu · \(dateLabel)",
                    body: item.summary,
                    threadIdentifier: "timetable",
                    route: .timetable
                )
            }
        } else {
            let labels = changedNotifications.prefix(3).map { Self.formattedDayLabel(forDayKey: $0.dayKey) }
            postNotification(
                identifier: "baki.timetable.batch.\(Int(Date().timeIntervalSince1970))",
                title: "Změny v rozvrhu (\(changedNotifications.count) dnů)",
                body: "Aktualizovány dny: \(labels.joined(separator: ", "))",
                threadIdentifier: "timetable",
                route: .timetable
            )
        }
    }

    // MARK: - UNUserNotificationCenter Posting & Delegate

    private func postNotification(
        identifier: String,
        title: String,
        subtitle: String? = nil,
        body: String,
        threadIdentifier: String,
        route: NotificationRoute
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        if let subtitle, !subtitle.isEmpty {
            content.subtitle = subtitle
        }
        content.body = body
        content.sound = .default
        content.threadIdentifier = threadIdentifier
        content.userInfo = ["route": route.rawValue]

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let rawRoute = response.notification.request.content.userInfo["route"] as? String
        guard let rawRoute, let route = NotificationRoute(rawValue: rawRoute) else { return }
        await MainActor.run {
            NotificationService.shared.pendingRoute = route
        }
    }

    // MARK: - Snapshot Persistence & Formatting Helpers

    private func loadSnapshot() -> NotificationSnapshot {
        guard let data = UserDefaults.standard.data(forKey: Self.snapshotStorageKey),
              let decoded = try? JSONDecoder().decode(NotificationSnapshot.self, from: data) else {
            return NotificationSnapshot()
        }
        return decoded
    }

    private func saveSnapshot(_ snapshot: NotificationSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: Self.snapshotStorageKey)
    }

    private static func previewText(fromHTML html: String?) -> String {
        let cleaned = cleanHTML(html ?? "")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard cleaned.count > 160 else { return cleaned }
        let idx = cleaned.index(cleaned.startIndex, offsetBy: 157)
        return String(cleaned[..<idx]) + "…"
    }

    private static func dayKey(for date: Date) -> String {
        dayFormatter.string(from: date)
    }

    private static func normalizedDayKey(_ raw: String) -> String? {
        if let prefix = raw.split(separator: "T").first, prefix.count == 10 {
            return String(prefix)
        }
        if let parsed = BakiDate.parse(raw) {
            return dayFormatter.string(from: parsed)
        }
        return nil
    }

    private static func formattedDayLabel(forDayKey key: String) -> String {
        guard let date = dayFormatter.date(from: key) else { return key }
        return shortCzechDateFormatter.string(from: date).capitalized
    }

    private static func makeDaySnapshot(day: Day, in response: TimetableResponse) -> TimetableDaySnapshot {
        let atoms = day.atoms.map { atom -> TimetableAtomSnapshot in
            let hour = response.hour(id: atom.hourId)
            let subject = response.subject(id: atom.subjectId)
            let room = response.room(id: atom.roomId)
            return TimetableAtomSnapshot(
                hourId: atom.hourId,
                hourCaption: hour?.caption ?? "\(atom.hourId)",
                subjectId: atom.subjectId ?? "",
                subjectName: subject?.displayName ?? "",
                teacherId: atom.teacherId ?? "",
                roomId: atom.roomId ?? "",
                roomName: room?.displayName ?? "",
                changeType: atom.change?.changeType ?? "",
                changeDescription: atom.change?.description ?? "",
                changeTypeName: atom.change?.typeName ?? ""
            )
        }
        .sorted()

        return TimetableDaySnapshot(
            dayType: day.dayType ?? "",
            dayDescription: day.dayDescription ?? "",
            atoms: atoms
        )
    }

    private static func changeKey(dayKey: String, atom: TimetableAtomSnapshot) -> String {
        "\(dayKey)|\(atom.hourId)|\(atom.changeType)|\(atom.changeDescription)|\(atom.changeTypeName)"
    }

    private static func prunedDays(_ days: [String: TimetableDaySnapshot], minDayKey: String) -> [String: TimetableDaySnapshot] {
        days.filter { $0.key >= minDayKey }
    }

    private static func prunedChangeKeys(_ keys: Set<String>, minDayKey: String) -> Set<String> {
        keys.filter { key in
            guard let dayPart = key.split(separator: "|").first else { return false }
            return String(dayPart) >= minDayKey
        }
    }

    private static func describeChangedAtoms(_ atoms: [TimetableAtomSnapshot]) -> String {
        let parts = atoms.prefix(3).map { atom -> String in
            let desc = !atom.changeDescription.isEmpty ? atom.changeDescription
                : (!atom.changeTypeName.isEmpty ? atom.changeTypeName : atom.changeType)
            let subjectPart = atom.subjectName.isEmpty ? "" : " (\(atom.subjectName))"
            return "\(atom.hourCaption). hod\(subjectPart): \(desc)"
        }
        var result = parts.joined(separator: " · ")
        if atoms.count > 3 {
            result += " (+\(atoms.count - 3) další)"
        }
        return result
    }

    private static func describeTimetableDiff(old: TimetableDaySnapshot, new: TimetableDaySnapshot) -> String {
        if old.dayType != new.dayType || old.dayDescription != new.dayDescription {
            if !new.dayDescription.isEmpty {
                return new.dayDescription
            }
            if new.dayType != "WorkDay", !new.dayType.isEmpty {
                return "Změna typu dne (\(new.dayType))"
            }
        }

        let oldSet = Set(old.atoms)
        let changedAtoms = new.atoms.filter { !oldSet.contains($0) && $0.hasChange }
        if !changedAtoms.isEmpty {
            return describeChangedAtoms(changedAtoms)
        }

        let addedOrModified = new.atoms.filter { !oldSet.contains($0) }
        if !addedOrModified.isEmpty {
            let parts = addedOrModified.prefix(3).map { atom -> String in
                let subject = atom.subjectName.isEmpty ? "hodina" : atom.subjectName
                let room = atom.roomName.isEmpty ? "" : " (\(atom.roomName))"
                return "\(atom.hourCaption). hod: \(subject)\(room)"
            }
            var result = parts.joined(separator: " · ")
            if addedOrModified.count > 3 {
                result += " (+\(addedOrModified.count - 3) další)"
            }
            return result
        }

        let newSet = Set(new.atoms)
        let removed = old.atoms.filter { !newSet.contains($0) }
        if !removed.isEmpty {
            let parts = removed.prefix(3).map { atom -> String in
                let subject = atom.subjectName.isEmpty ? "" : " (\(atom.subjectName))"
                return "\(atom.hourCaption). hod\(subject) odebrána"
            }
            return parts.joined(separator: " · ")
        }

        return "Rozvrh pro tento den byl aktualizován."
    }
}

private struct NotificationSnapshot: Codable {
    var seenMarkIds: Set<String>?
    var seenKomensIds: Set<String>?
    var seenNoticeboardIds: Set<String>?
    var timetableDays: [String: TimetableDaySnapshot]?
    var notifiedChangeKeys: Set<String> = []
}

private struct TimetableDaySnapshot: Codable, Equatable {
    let dayType: String
    let dayDescription: String
    let atoms: [TimetableAtomSnapshot]
}

private struct TimetableAtomSnapshot: Codable, Hashable, Comparable {
    let hourId: Int
    let hourCaption: String
    let subjectId: String
    let subjectName: String
    let teacherId: String
    let roomId: String
    let roomName: String
    let changeType: String
    let changeDescription: String
    let changeTypeName: String

    var hasChange: Bool {
        !changeType.isEmpty || !changeDescription.isEmpty || !changeTypeName.isEmpty
    }

    static func == (lhs: TimetableAtomSnapshot, rhs: TimetableAtomSnapshot) -> Bool {
        lhs.hourId == rhs.hourId &&
        lhs.subjectId == rhs.subjectId &&
        lhs.teacherId == rhs.teacherId &&
        lhs.roomId == rhs.roomId &&
        lhs.changeType == rhs.changeType &&
        lhs.changeDescription == rhs.changeDescription &&
        lhs.changeTypeName == rhs.changeTypeName
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(hourId)
        hasher.combine(subjectId)
        hasher.combine(teacherId)
        hasher.combine(roomId)
        hasher.combine(changeType)
        hasher.combine(changeDescription)
        hasher.combine(changeTypeName)
    }

    static func < (lhs: TimetableAtomSnapshot, rhs: TimetableAtomSnapshot) -> Bool {
        (lhs.hourId, lhs.subjectId, lhs.teacherId, lhs.roomId, lhs.changeType, lhs.changeDescription)
        < (rhs.hourId, rhs.subjectId, rhs.teacherId, rhs.roomId, rhs.changeType, rhs.changeDescription)
    }
}
