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

    private struct Guess: Identifiable, Equatable {
        let id = UUID()
        var text = "1"
        var weight: Int
    }

    private static let gradeOptions = ["1", "1-", "2", "2-", "3", "3-", "4", "4-", "5"]

    @State private var guesses: [Guess] = []
    @State private var newMarkWeight: Int

    init(item: SubjectMarks) {
        self.item = item
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

    private var existingMarks: [Mark] {
        MarksScreen.sortedNewestFirst(item).marks
    }

    /// Returns the segmented weight options sorted in numerical order, placing any custom weight before 10.
    private func weightOptions(for currentWeight: Int) -> [Int] {
        var base = [1, 2, 3, 4, 5, 10]
        if !base.contains(currentWeight) && currentWeight >= 1 && currentWeight <= 10 {
            base.append(currentWeight)
            base.sort()
        }
        return base
    }

    var body: some View {
        Form {
            heroSection
            quickAddSection
            guessesSection
            existingMarksSection
        }
        .formStyle(.grouped)
        .navigationTitle(subjectName)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private var heroSection: some View {
        Section {
            VStack(spacing: 10) {
                HStack(alignment: .center, spacing: 0) {
                    VStack(spacing: 2) {
                        Text("Aktuální průměr")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        if let current = currentAverage {
                            Text("Ø \(current)")
                                .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(MarkColor.forAverage(current))
                        } else {
                            Text("–")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Image(systemName: "arrow.right")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)

                    VStack(spacing: 2) {
                        Text("Nový průměr")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        if let pred = predicted {
                            Text("Ø \(pred)")
                                .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(MarkColor.forAverage(pred))
                        } else {
                            Text(currentAverage.map { "Ø \($0)" } ?? "–")
                                .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(currentAverage.map { MarkColor.forAverage($0) } ?? .secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                if let change = changeText {
                    HStack(spacing: 6) {
                        Image(systemName: change.delta < 0 ? "arrow.down.right" : (change.delta > 0 ? "arrow.up.right" : "equal"))
                            .font(.caption.weight(.bold))
                        Text(change.text)
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                        if abs(change.delta) >= 0.005 {
                            Text(change.delta < 0 ? "(zlepšení)" : "(zhoršení)")
                                .font(.caption)
                        }
                    }
                    .foregroundStyle(change.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(change.color.opacity(0.12), in: Capsule())
                } else if guesses.isEmpty {
                    Text("Přidejte hypotetické známky níže pro výpočet nového průměru.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
        }
    }

    private var quickAddSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                // Weight selector for new marks
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "scalemass")
                        Text("Váha")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize()

                    Spacer()

                    Text("Váha \(newMarkWeight)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .fixedSize()
                }

                HStack(spacing: 8) {
                    Picker("Váha nové známky", selection: $newMarkWeight) {
                        ForEach(weightOptions(for: newMarkWeight), id: \.self) { w in
                            Text("\(w)").tag(w)
                        }
                    }
                    .pickerStyle(.segmented)

                    Menu {
                        ForEach(1...10, id: \.self) { w in
                            Button {
                                newMarkWeight = w
                            } label: {
                                if newMarkWeight == w {
                                    Label("Váha \(w)", systemImage: "checkmark")
                                } else {
                                    Text("Váha \(w)")
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                }

                Divider()
                    .padding(.vertical, 2)

                // Grade buttons
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Self.gradeOptions, id: \.self) { grade in
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    guesses.append(Guess(text: grade, weight: newMarkWeight))
                                }
                            } label: {
                                Text(grade)
                                    .font(.headline.weight(.bold).monospacedDigit())
                                    .foregroundStyle(MarkColor.foreground(for: MarkColor.forMark(grade)))
                                    .frame(width: 42, height: 42)
                                    .background(
                                        MarkColor.forMark(grade).gradient,
                                        in: .rect(cornerRadius: 12, style: .continuous)
                                    )
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 1)
                }
            }
            .padding(.vertical, 2)
        } header: {
            Text("Přidat známku")
        }
    }

    private var guessesSection: some View {
        Section {
            if guesses.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "wand.and.sparkles")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Zatím žádné hypotetické známky")
                            .font(.subheadline.weight(.medium))
                        Text("Vyberte váhu a klepněte na známku výše.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    Spacer()
                }
            } else {
                ForEach($guesses) { $guess in
                    hypotheticalMarkRow($guess)
                }
                .onDelete { indexSet in
                    withAnimation {
                        guesses.remove(atOffsets: indexSet)
                    }
                }
            }
        } header: {
            HStack {
                Text(guesses.isEmpty ? "Hypotetické známky" : "Hypotetické známky (\(guesses.count))")
                Spacer()
                if !guesses.isEmpty {
                    Button("Smazat vše", role: .destructive) {
                        withAnimation {
                            guesses.removeAll()
                        }
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.red)
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private func hypotheticalMarkRow(_ guess: Binding<Guess>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            MarkBadge(text: guess.wrappedValue.text)

            VStack(alignment: .leading, spacing: 3) {
                Text("Známka \(guess.wrappedValue.text)")
                    .font(.body.weight(.semibold))

                Text("Váha \(guess.wrappedValue.weight)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(role: .destructive) {
                withAnimation {
                    guesses.removeAll { $0.id == guess.wrappedValue.id }
                }
            } label: {
                Image(systemName: "trash")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Odebrat známku")
        }
        .padding(.vertical, 3)
    }

    private var existingMarksSection: some View {
        Section {
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
        } header: {
            Text("Stávající známky (\(existingMarks.count))")
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
                HStack(spacing: 8) {
                    if let dateStr = mark.markDate {
                        Text(BakiDate.formatCzechDate(dateStr))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                    if let weight = mark.weight {
                        Text("Váha \(weight)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                            .fixedSize()
                    }
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

    // MARK: - Calculation Helpers

    /// Predicted minus current average; lower is better in the Czech grading scale.
    private var changeText: (text: String, color: Color, delta: Double)? {
        guard let predicted, let current = currentAverage,
              let new = Self.number(predicted), let old = Self.number(current) else { return nil }
        let delta = new - old
        guard abs(delta) >= 0.005 else { return ("beze změny", .secondary, 0) }
        let text = delta.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always()))
        return (text, delta < 0 ? .green : .red, delta)
    }

    /// Weighted average of the existing marks plus the hypothetical ones, formatted like the server's
    /// (two decimals, decimal comma). Nil until a guess is added or when no mark is numeric.
    private var predicted: String? {
        guard !guesses.isEmpty else { return nil }
        let entries = item.marks.map { (Self.grade($0.displayText), $0.weight ?? 1) }
            + guesses.map { (Self.grade($0.text), $0.weight) }
        let weighted = entries.compactMap { grade, weight in grade.map { ($0, Double(weight)) } }
        let totalWeight = weighted.reduce(0) { $0 + $1.1 }
        guard totalWeight > 0 else { return nil }
        let average = weighted.reduce(0) { $0 + $1.0 * $1.1 } / totalWeight
        return average.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "cs_CZ")))
    }

    /// Numeric value of a grade; a trailing minus counts as half a grade worse ("2-" = 2.5).
    private static func grade(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.hasSuffix("-") ? String(trimmed.dropLast()) : trimmed
        guard let value = Double(base), (1...5).contains(value) else { return nil }
        return trimmed.hasSuffix("-") ? value + 0.5 : value
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
