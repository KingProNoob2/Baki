#if os(macOS)
import SwiftUI

/// Úkoly: pending homework first, then (optionally) finished ones; the selected task in the detail
/// column.
struct MacHomeworkView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case current = "Aktuální"
        case all = "Vše"

        var id: Self { self }
    }

    @Environment(MacDetailModel.self) private var detail
    @State private var store = HomeworkStore()
    @State private var mode: Mode = SavedMode.load("homework", default: .current)
    @State private var selection: String?

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

    private var subtitle: String {
        switch pending.count {
        case 0: return "Vše hotovo"
        case 1: return "1 úkol k odevzdání"
        case 2...4: return "\(pending.count) úkoly k odevzdání"
        default: return "\(pending.count) úkolů k odevzdání"
        }
    }

    var body: some View {
        Group {
            if !store.hasLoaded && store.homeworks.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .macScreen(title: "Úkoly") {
            MacScreenHeader(title: "Úkoly", subtitle: store.homeworks.isEmpty ? nil : subtitle)
        }
        .toolbar {
            ToolbarItem {
                Picker("Zobrazení", selection: $mode) {
                    ForEach(Mode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .onChange(of: mode) { SavedMode.save("homework", mode) }
        .onChange(of: selection) {
            guard let id = selection else { return }
            detail.show(id: id, content: AnyView(MacHomeworkDetail(store: store, homeworkID: id)))
        }
        .alert("Úkol se nepodařilo změnit", isPresented: $store.toggleFailed) {
            Button("OK", role: .cancel) {}
        }
        .focusedSceneValue(\.refreshAction, RefreshAction { Task { await store.load() } })
        .task {
            guard !store.hasLoaded else { return }
            await store.load()
        }
    }

    private var list: some View {
        List(selection: $selection) {
            if mode == .current && pending.isEmpty {
                ContentUnavailableView(
                    "Vše hotovo",
                    systemImage: "checkmark.circle",
                    description: Text("Nemáte žádné úkoly k odevzdání.")
                )
                .listRowSeparator(.hidden)
            }
            if !overdue.isEmpty {
                Section("Po termínu") { rows(overdue) }
            }
            if !upcoming.isEmpty {
                Section("K odevzdání") { rows(upcoming) }
            }
            if mode == .all && !finished.isEmpty {
                Section("Hotové") { rows(finished) }
            }
        }
        .macList()
    }

    private func rows(_ homeworks: [Homework]) -> some View {
        ForEach(homeworks) { homework in
            row(homework)
                .tag(homework.id)
        }
    }

    private func row(_ homework: Homework) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                Task { await store.toggleDone(homework) }
            } label: {
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
        .padding(.vertical, 6)
        .opacity(homework.isDone || homework.isClosed ? 0.6 : 1)
    }
}

/// Detail column for a single task.
struct MacHomeworkDetail: View {
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

        return MacDetailForm {
            Section {
                MacHero(title: homework.subjectName) {
                    MacTile(tint: homework.isDone ? .green : .blue) {
                        Image(systemName: homework.isDone ? "checkmark" : "checklist")
                            .font(.system(size: 40, weight: .semibold))
                    }
                }
                DueLabel(homework: homework)
                    .frame(maxWidth: .infinity)
                    .macPlainRow()
            }

            Section("Zadání") {
                if text.isEmpty {
                    Text("Bez textu")
                        .foregroundStyle(.secondary)
                } else {
                    Text(HomeworkDetailView.linkified(text))
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
                }
            }

            Section {
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
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .macPlainRow()
                }
            }
        }
        .navigationTitle(homework.subjectName)
    }
}
#endif
