import SwiftUI

extension SubjectMarks {
    /// The server only predicts for subjects that allow it and use grades, not points.
    var canPredict: Bool {
        markPredictionEnabled != false && pointsOnly != true
    }
}

/// Předvídač for one subject: add hypothetical marks and see the resulting average, calculated
/// locally as a weighted average of the existing and hypothetical marks. Shown pushed (iOS) or in the detail column (Mac).
struct MarkPredictorView: View {
    let item: SubjectMarks
    var isEmbeddedInSplit: Bool = false

    private struct Guess: Identifiable, Equatable {
        let id = UUID()
        var text = "1"
        var weight: Int
    }

    private static let gradeOptions = ["1", "1-", "2", "2-", "3", "3-", "4", "4-", "5"]

    @State private var guesses: [Guess] = []
    @State private var selectedGrade: String = "1"
    @State private var newMarkWeight: Int

    init(item: SubjectMarks, isEmbeddedInSplit: Bool = false) {
        self.item = item
        self.isEmbeddedInSplit = isEmbeddedInSplit
        let counts = Dictionary(grouping: item.marks.compactMap(\.weight), by: { $0 }).mapValues(\.count)
        let initialWeight = counts.max { $0.value < $1.value }?.key ?? 1
        _newMarkWeight = State(initialValue: max(1, min(initialWeight, 10)))
    }

    private var subjectName: String {
        item.subject.name.isEmpty ? item.subject.abbrev : item.subject.name
    }

    private var currentAverage: String? {
        let text = item.averageText?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }

    private var displayedAverage: String? {
        predicted ?? currentAverage
    }

    private var existingMarks: [Mark] {
        MarksScreen.sortedNewestFirst(item).marks
    }

    var body: some View {
        GroupedList {
            heroSection
            addMarkSection
            addButtonSection
            if !guesses.isEmpty {
                guessesSection
            }
            existingMarksSection
        }
        .groupedList()
        .duoDetailNavigationTitle(subjectName, isEmbeddedInSplit: isEmbeddedInSplit)
        .toolbar {
            if !guesses.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) {
                        withAnimation {
                            guesses.removeAll()
                        }
                    } label: {
                        Label("Smazat vše", systemImage: "trash")
                    }
                }
            }
        }
    }

    // MARK: - Sections

    private var heroSection: some View {
        Section {
            VStack(spacing: 8) {
                if isEmbeddedInSplit {
                    Text(subjectName)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                if let displayed = displayedAverage {
                    let color = MarkColor.forAverage(displayed)
                    Text("Ø \(displayed)")
                        .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(color)
                        .contentTransition(.numericText())
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(color.opacity(0.18), in: Capsule())
                } else {
                    Text("–")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                }

                Text(guesses.isEmpty ? "Aktuální průměr" : "Předpokládaný průměr")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let change = changeText, let current = currentAverage {
                    HStack(spacing: 6) {
                        Text("Ø \(current)")
                            .foregroundStyle(.secondary)
                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                        Text(change.text)
                            .foregroundStyle(change.color)
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline.monospacedDigit())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .plainGroupedRow()
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private var addMarkSection: some View {
        Section {
            Picker(selection: $selectedGrade) {
                ForEach(Self.gradeOptions, id: \.self) { grade in
                    Text(grade).tag(grade)
                }
            } label: {
                Label("Známka", systemImage: "graduationcap")
            }

            Stepper(value: $newMarkWeight, in: 1...10) {
                HStack {
                    Label("Váha", systemImage: "scalemass")
                    Spacer()
                    Text("\(newMarkWeight)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Přidat známku")
        } footer: {
            if guesses.isEmpty {
                Text("Zvolte známku a váhu pro výpočet nového průměru.")
            }
        }
    }

    private var addButtonSection: some View {
        Section {
            Button {
                withAnimation {
                    guesses.append(Guess(text: selectedGrade, weight: newMarkWeight))
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Přidat známku \(selectedGrade)")
                }
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .plainGroupedRow()
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        }
    }

    private var guessesSection: some View {
        Section("Hypotetické známky (\(guesses.count))") {
            ForEach($guesses) { $guess in
                hypotheticalMarkRow($guess)
            }
            .onDelete { indexSet in
                withAnimation {
                    guesses.remove(atOffsets: indexSet)
                }
            }
        }
    }

    private func hypotheticalMarkRow(_ guess: Binding<Guess>) -> some View {
        HStack(spacing: 12) {
            MarkBadge(text: guess.wrappedValue.text)

            VStack(alignment: .leading, spacing: 2) {
                Text("Známka \(guess.wrappedValue.text)")
                    .font(.body.weight(.medium))
                Text("Váha \(guess.wrappedValue.weight)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Menu {
                Picker("Známka", selection: guess.text) {
                    ForEach(Self.gradeOptions, id: \.self) { grade in
                        Text(grade).tag(grade)
                    }
                }
                Picker("Váha", selection: guess.weight) {
                    ForEach(1...10, id: \.self) { weight in
                        Text("Váha \(weight)").tag(weight)
                    }
                }
                Divider()
                Button(role: .destructive) {
                    withAnimation {
                        guesses.removeAll { $0.id == guess.wrappedValue.id }
                    }
                } label: {
                    Label("Odebrat", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Upravit hypotetickou známku")
        }
        .padding(.vertical, 2)
    }

    private var existingMarksSection: some View {
        Section("Stávající známky (\(existingMarks.count))") {
            if existingMarks.isEmpty {
                Text("Žádné stávající známky")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(existingMarks) { mark in
                    NavigationLink {
                        MarkDetailView(
                            mark: mark,
                            subject: item.subject,
                            averageText: item.averageText,
                            subjectNote: item.subjectNote
                        )
                    } label: {
                        existingMarkRow(mark)
                    }
                }
            }
        }
    }

    private func existingMarkRow(_ mark: Mark) -> some View {
        let caption = mark.caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let theme = mark.theme?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return HStack(spacing: 12) {
            MarkBadge(text: mark.displayText)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(caption.isEmpty ? "Známka" : caption)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if mark.isNew == true {
                        NewMarkDot()
                    }
                }
                if !theme.isEmpty && theme != caption {
                    Text(theme)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                let metadata = existingMarkMetadata(mark)
                if !metadata.isEmpty {
                    Text(metadata)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            if let calc = mark.calculatedMarkText?.trimmingCharacters(in: .whitespacesAndNewlines),
               !calc.isEmpty, calc != mark.displayText {
                Text(calc)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
        .padding(.vertical, 2)
    }

    private func existingMarkMetadata(_ mark: Mark) -> String {
        var parts: [String] = []
        if let dateStr = mark.markDate {
            parts.append(BakiDate.formatCzechDate(dateStr))
        }
        if let weight = mark.weight {
            parts.append("Váha \(weight)")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Calculation Helpers

    /// Predicted minus current average; lower is better in the Czech grading scale.
    private var changeText: (text: String, color: Color, delta: Double)? {
        guard let predicted, let current = currentAverage,
              let new = Self.number(predicted), let old = Self.number(current) else { return nil }
        let delta = new - old
        guard abs(delta) >= 0.005 else { return ("beze změny", .secondary, 0) }
        let text = delta.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always()).locale(Locale(identifier: "cs_CZ")))
        return (text, delta < 0 ? .green : .red, delta)
    }

    /// Weighted average of the existing marks plus the hypothetical ones, formatted like the server's
    /// (two decimals, decimal comma). Nil until a guess is added or when no mark is numeric.
    private var predicted: String? {
        guard !guesses.isEmpty else { return nil }
        let entries = item.marks.map { (Self.markGrade($0), $0.weight ?? 1) }
            + guesses.map { (Self.grade($0.text), $0.weight) }
        let weighted = entries.compactMap { grade, weight in grade.map { ($0, Double(weight)) } }
        let totalWeight = weighted.reduce(0) { $0 + $1.1 }
        guard totalWeight > 0 else { return nil }
        let average = weighted.reduce(0) { $0 + $1.0 * $1.1 } / totalWeight
        return average.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "cs_CZ")))
    }

    private static func markGrade(_ mark: Mark) -> Double? {
        if let direct = grade(mark.displayText) {
            return direct
        }
        if let calc = mark.calculatedMarkText {
            return grade(calc)
        }
        return nil
    }

    /// Numeric value of a grade; a trailing minus counts as half a grade worse ("2-" = 2.5),
    /// and modifiers like "*", "+", "!" map to the base grade.
    private static func grade(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasSuffix("-") {
            guard let value = Double(trimmed.dropLast()), (1...5).contains(value) else { return nil }
            return min(5, value + 0.5)
        }
        if let last = trimmed.last, "+*!".contains(last) {
            guard let value = Double(trimmed.dropLast()), (1...5).contains(value) else { return nil }
            return value
        }
        guard let value = Double(trimmed), (1...5).contains(value) else { return nil }
        return value
    }

    private static func number(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        if let direct = Double(cleaned) {
            return direct
        }
        let pattern = #"[0-9]+(\.[0-9]+)?"#
        if let match = cleaned.range(of: pattern, options: .regularExpression) {
            return Double(cleaned[match])
        }
        return nil
    }
}
