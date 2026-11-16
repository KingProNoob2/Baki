import SwiftUI

@Observable
final class HomeworkStore {
    var homeworks: [Homework] = []
    var isLoading = false
    var hasLoaded = false

    func load() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let from = calendar.date(byAdding: .day, value: -30, to: today) ?? today
        let to = calendar.date(byAdding: .day, value: 60, to: today) ?? today
        if let fetched = try? await BakiClient.shared.fetchHomeworks(from: from, to: to) {
            homeworks = fetched
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
        }
    }
}

struct HomeworkScreen: View {
    @State private var store = HomeworkStore()

    private var pending: [Homework] {
        store.homeworks
            .filter { !$0.isDone && !$0.isClosed }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    private var recentlyDone: [Homework] {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return store.homeworks
            .filter { $0.isDone && !$0.isClosed && ($0.dueDate ?? .distantPast) >= weekAgo }
            .sorted { ($0.dueDate ?? .distantPast) > ($1.dueDate ?? .distantPast) }
    }

    var body: some View {
        Group {
            if !store.hasLoaded && store.homeworks.isEmpty {
                HomeworkSkeleton()
            } else if pending.isEmpty && recentlyDone.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .font(.title2)
                        .foregroundStyle(.green)
                        .padding(10)
                    Text("Vše hotovo")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(pending) { homework in
                        row(homework)
                    }

                    if !recentlyDone.isEmpty {
                        Section("Hotové") {
                            ForEach(recentlyDone) { homework in
                                row(homework)
                            }
                        }
                    }
                }
                .padding(.top, 60)
            }
        }
        .bakiHeader("Úkoly")
        .task {
            guard !store.hasLoaded else { return }
            await store.load()
        }
        .refreshable {
            await store.load()
        }
    }

    private func row(_ homework: Homework) -> some View {
        NavigationLink {
            HomeworkDetailView(store: store, homeworkID: homework.id)
        } label: {
            HomeworkRow(homework: homework)
        }
        .swipeActions(edge: .leading) {
            if !homework.isClosed {
                Button {
                    Task { await store.toggleDone(homework) }
                } label: {
                    Image(systemName: homework.isDone ? "arrow.uturn.backward" : "checkmark")
                }
                .tint(homework.isDone ? .gray : .green)
            }
        }
    }
}

private struct HomeworkRow: View {
    let homework: Homework

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if homework.isDone {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Text(homework.subjectName)
                    .font(.headline)
                    .lineLimit(1)
            }

            DueText(homework: homework)

            let text = homework.contentText
            if !text.isEmpty {
                Text(text.replacingOccurrences(of: "\n", with: " "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .opacity(homework.isDone ? 0.6 : 1)
    }
}

private struct DueText: View {
    let homework: Homework

    var body: some View {
        if let due = homework.dueDate {
            let info = Self.describe(due, isPending: !homework.isDone && !homework.isClosed)
            Text(info.text)
                .font(.caption2)
                .bold()
                .foregroundStyle(info.color)
        }
    }

    static func describe(_ due: Date, isPending: Bool) -> (text: String, color: Color) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: due)).day ?? 0
        let date = due.formatted(.dateTime.day().month(.defaultDigits).locale(Locale(identifier: "cs_CZ")))

        guard isPending else { return ("Do \(date)", .secondary) }
        switch days {
        case ..<0: return ("Po termínu · \(date)", .red)
        case 0: return ("Dnes", .orange)
        case 1: return ("Zítra", .orange)
        case 2...6:
            let weekday = due.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "cs_CZ")))
            return (weekday.prefix(1).uppercased() + weekday.dropFirst(), .purple)
        default: return ("Do \(date)", .purple)
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
            Text("Úkol nenalezen")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func content(_ homework: Homework) -> some View {
        let text = homework.contentText

        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(homework.subjectName)
                    .font(.headline)
                    .bold()
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 4) {
                    DueText(homework: homework)
                    Text(text.isEmpty ? "Bez textu" : text)
                        .font(.body)
                        .foregroundStyle(text.isEmpty ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.purple.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                if homework.isClosed {
                    Label("Uzavřeno", systemImage: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        Task { await store.toggleDone(homework) }
                    } label: {
                        Label(
                            homework.isDone ? "Nehotovo" : "Hotovo",
                            systemImage: homework.isDone ? "arrow.uturn.backward" : "checkmark"
                        )
                    }
                    .tint(homework.isDone ? .gray : .green)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    if let start = homework.dateStart {
                        InfoRow(icon: "calendar.badge.plus", iconColor: .orange, title: "Zadáno", subtitle: BakiDate.formatCzechDate(start))
                    }
                    if let end = homework.dateEnd {
                        InfoRow(icon: "calendar.badge.clock", iconColor: .red, title: "Odevzdat do", subtitle: BakiDate.formatCzechDate(end))
                    }
                    if let teacher = homework.teacher?.name, !teacher.isEmpty {
                        InfoRow(icon: "person.fill", iconColor: .green, title: "Vyučující", subtitle: teacher)
                    }
                    if let count = homework.attachments?.count, count > 0 {
                        InfoRow(icon: "paperclip", iconColor: .blue, title: "Přílohy", subtitle: "\(count) – otevřete na iPhonu")
                    }
                }

                if let notice = homework.notice?.trimmingCharacters(in: .whitespacesAndNewlines), !notice.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Image(systemName: "info.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("Poznámka")
                                .font(.caption2)
                                .bold()
                                .foregroundStyle(.secondary)
                        }
                        Text(notice)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 12)
        }
    }
}

struct HomeworkSkeleton: View {
    var body: some View {
        List {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 2) {
                    Text("Matematika")
                        .font(.headline)
                    Text("Zítra")
                        .font(.caption2)
                    Text("Pracovní list str. 12")
                        .font(.caption2)
                }
            }
        }
        .padding(.top, 60)
        .skeletonPulse()
    }
}
