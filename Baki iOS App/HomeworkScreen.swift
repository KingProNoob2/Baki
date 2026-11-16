import SwiftUI

@Observable
final class HomeworkStore {
    var homeworks: [Homework] = []
    var isLoading = false
    var hasLoaded = false
    var loadFailed = false
    var toggleFailed = false

    func load() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let from = calendar.date(byAdding: .day, value: -60, to: today) ?? today
        let to = calendar.date(byAdding: .day, value: 60, to: today) ?? today
        do {
            homeworks = try await BakiClient.shared.fetchHomeworks(from: from, to: to)
            loadFailed = false
        } catch {
            if homeworks.isEmpty { loadFailed = true }
        }
    }

    func homework(id: String) -> Homework? {
        homeworks.first { $0.id == id }
    }

    func toggleDone(_ homework: Homework) async {
        guard !homework.isClosed, let index = homeworks.firstIndex(where: { $0.id == homework.id }) else { return }
        let newValue = !homework.isDone
        withAnimation { homeworks[index].done = newValue }
        do {
            try await BakiClient.shared.setHomeworkDone(homework, done: newValue)
        } catch {
            if let index = homeworks.firstIndex(where: { $0.id == homework.id }) {
                withAnimation { homeworks[index].done = !newValue }
            }
            toggleFailed = true
        }
    }
}

struct HomeworkScreen: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case current = "Aktuální"
        case all = "Vše"

        var id: Self { self }

        var systemImage: String {
            switch self {
            case .current: return "checklist.unchecked"
            case .all: return "checklist"
            }
        }
    }

    @State private var store = HomeworkStore()
    @State private var mode: Mode = SavedMode.load("homework", default: .current)

    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    private var pending: [Homework] {
        store.homeworks
            .filter { !$0.isDone && !$0.isClosed }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    private var overdue: [Homework] {
        pending.filter { ($0.dueDate ?? .distantFuture) < today }
    }

    private var upcoming: [Homework] {
        pending.filter { ($0.dueDate ?? .distantFuture) >= today }
    }

    private var finished: [Homework] {
        store.homeworks
            .filter { $0.isDone || $0.isClosed }
            .sorted { ($0.dueDate ?? .distantPast) > ($1.dueDate ?? .distantPast) }
    }

    var body: some View {
        Group {
            if !store.hasLoaded && store.homeworks.isEmpty {
                ProgressView()
            } else if store.homeworks.isEmpty && store.loadFailed {
                ContentUnavailableView {
                    Label("Úkoly se nepodařilo načíst", systemImage: "exclamationmark.triangle")
                } actions: {
                    Button("Zkusit znovu") { Task { await store.load() } }
                }
            } else if store.homeworks.isEmpty {
                ContentUnavailableView("Žádné úkoly", systemImage: "checklist")
            } else {
                list
            }
        }
        .navigationTitle("Úkoly")
        .onChange(of: mode) { SavedMode.save("homework", mode) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Zobrazení", selection: $mode) {
                        ForEach(Mode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.systemImage).tag(mode)
                        }
                    }
                } label: {
                    Label("Zobrazení", systemImage: mode.systemImage)
                }
            }
        }
        .alert("Úkol se nepodařilo změnit", isPresented: $store.toggleFailed) {
            Button("OK", role: .cancel) {}
        }
        .task {
            guard !store.hasLoaded else { return }
            await store.load()
        }
        .refreshable {
            await store.load()
        }
    }

    private var list: some View {
        GroupedList {
            if mode == .current && pending.isEmpty {
                ContentUnavailableView(
                    "Vše hotovo",
                    systemImage: "checkmark.circle",
                    description: Text("Nemáte žádné úkoly k odevzdání.")
                )
                .listRowBackground(Color.clear)
            }

            if !overdue.isEmpty {
                Section("Po termínu") {
                    rows(overdue)
                }
            }

            if !upcoming.isEmpty {
                Section("K odevzdání") {
                    rows(upcoming)
                }
            }

            if mode == .all && !finished.isEmpty {
                Section("Hotové") {
                    rows(finished)
                }
            }
        }
        .groupedList()
    }

    private func rows(_ homeworks: [Homework]) -> some View {
        ForEach(homeworks) { homework in
            NavigationLink {
                HomeworkDetailView(store: store, homeworkID: homework.id)
            } label: {
                HomeworkRow(homework: homework) {
                    Task { await store.toggleDone(homework) }
                }
            }
            .swipeActions(edge: .leading) {
                if !homework.isClosed {
                    Button {
                        Task { await store.toggleDone(homework) }
                    } label: {
                        if homework.isDone {
                            Label("Nehotovo", systemImage: "arrow.uturn.backward")
                        } else {
                            Label("Hotovo", systemImage: "checkmark")
                        }
                    }
                    .tint(homework.isDone ? .gray : .green)
                }
            }
        }
    }
}

private struct HomeworkRow: View {
    let homework: Homework
    let toggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: toggle) {
                Image(systemName: homework.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(homework.isDone ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .disabled(homework.isClosed)
            .accessibilityLabel(homework.isDone ? "Označit jako nehotové" : "Označit jako hotové")

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(homework.subjectName)
                        .font(.headline)
                        .lineLimit(1)
                    if homework.attachments?.isEmpty == false {
                        Image(systemName: "paperclip")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Obsahuje přílohu")
                    }
                }

                let text = homework.contentText
                if !text.isEmpty {
                    Text(text.replacingOccurrences(of: "\n", with: " "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                DueLabel(homework: homework)
            }
        }
        .padding(.vertical, 2)
        .opacity(homework.isDone || homework.isClosed ? 0.6 : 1)
    }
}

struct DueLabel: View {
    let homework: Homework

    var body: some View {
        if let due = homework.dueDate {
            let info = Self.describe(due, isPending: !homework.isDone && !homework.isClosed)
            Label(info.text, systemImage: "calendar")
                .font(.footnote.weight(.medium))
                .foregroundStyle(info.color)
        }
    }

    static func describe(_ due: Date, isPending: Bool) -> (text: String, color: Color) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let day = calendar.startOfDay(for: due)
        let days = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        let date = due.formatted(.dateTime.day().month(.defaultDigits).locale(Locale(identifier: "cs_CZ")))

        guard isPending else { return ("Do \(date)", .secondary) }
        switch days {
        case ..<0: return ("Po termínu · \(date)", .red)
        case 0: return ("Dnes", .orange)
        case 1: return ("Zítra", .orange)
        case 2...6:
            let weekday = due.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "cs_CZ")))
            return (weekday.prefix(1).uppercased() + weekday.dropFirst(), .secondary)
        default: return ("Do \(date)", .secondary)
        }
    }
}

struct HomeworkDetailView: View {
    let store: HomeworkStore
    let homeworkID: String

    var body: some View {
        if let homework = store.homework(id: homeworkID) {
            content(homework)
        } else {
            ContentUnavailableView("Úkol nenalezen", systemImage: "checklist")
        }
    }

    private func content(_ homework: Homework) -> some View {
        let text = homework.contentText

        return GroupedList {
            Section("Zadání") {
                if text.isEmpty {
                    Text("Bez textu")
                        .foregroundStyle(.secondary)
                } else {
                    Text(Self.linkified(text))
                        .textSelection(.enabled)
                }
            }

            if let notice = homework.notice?.trimmingCharacters(in: .whitespacesAndNewlines), !notice.isEmpty {
                Section("Poznámka") {
                    Text(notice)
                        .textSelection(.enabled)
                }
            }

            Section("Podrobnosti") {
                if let due = homework.dueDate {
                    let info = DueLabel.describe(due, isPending: !homework.isDone && !homework.isClosed)
                    LabeledContent {
                        Text(info.text)
                            .foregroundStyle(info.color)
                    } label: {
                        Label("Termín", systemImage: "calendar")
                    }
                }
                if let start = homework.dateStart {
                    LabeledContent {
                        Text(BakiDate.formatCzechDate(start))
                    } label: {
                        Label("Zadáno", systemImage: "calendar.badge.plus")
                    }
                }
                if let end = homework.dateEnd {
                    LabeledContent {
                        Text(BakiDate.formatCzechDate(end))
                    } label: {
                        Label("Odevzdat do", systemImage: "calendar.badge.clock")
                    }
                }
                if let teacher = homework.teacher?.name, !teacher.isEmpty {
                    LabeledContent {
                        Text(teacher)
                    } label: {
                        Label("Vyučující", systemImage: "person")
                    }
                }
                if let hour = homework.hour, hour > 0 {
                    LabeledContent {
                        Text("\(hour).")
                    } label: {
                        Label("Hodina", systemImage: "clock")
                    }
                }
                if let group = homework.group?.name, !group.isEmpty, group != homework.subjectName {
                    LabeledContent {
                        Text(group)
                    } label: {
                        Label("Skupina", systemImage: "person.3")
                    }
                }
                if homework.electronic == true {
                    Label("Odevzdává se elektronicky", systemImage: "icloud.and.arrow.up")
                }
            }

            if let attachments = homework.attachments, !attachments.isEmpty {
                Section {
                    AttachmentsSection(attachments: attachments)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            Section {
                // The action sits directly on the page on macOS, not inside a glass card.
                Group {
                    if homework.isClosed {
                        Label("Úkol byl uzavřen vyučujícím", systemImage: "lock")
                            .foregroundStyle(.secondary)
                    } else {
                        Button {
                            Task { await store.toggleDone(homework) }
                        } label: {
                            Label(
                                homework.isDone ? "Označit jako nehotové" : "Označit jako hotové",
                                systemImage: homework.isDone ? "arrow.uturn.backward.circle" : "checkmark.circle"
                            )
                        }
                    }
                }
                .plainGroupedRow()
            }
        }
        .groupedList()
        .navigationTitle(homework.subjectName)
        .navigationBarTitleDisplayMode(.large)
    }

    static func linkified(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return attributed
        }
        let range = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, range: range) {
            guard let url = match.url,
                  let stringRange = Range(match.range, in: text),
                  let attributedRange = Range(stringRange, in: attributed) else { continue }
            attributed[attributedRange].link = url
        }
        return attributed
    }
}
