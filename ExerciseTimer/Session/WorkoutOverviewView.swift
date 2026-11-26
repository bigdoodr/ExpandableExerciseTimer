import SwiftUI

/// A Fitness+-style preview of the whole session: blocks in order, supersets grouped into one
/// card, each exercise's target and (for workouts) what you did last time. Shown from the builder
/// before starting, and as a sheet mid-session with your position marked.
struct WorkoutOverviewView: View {
    let kind: SessionKind
    let exercises: [Exercise]
    /// When set, the overview marks finished and in-progress blocks.
    var engine: SessionEngine? = nil
    var history: WorkoutHistoryStore? = nil

    private var plan: WorkoutPlan { engine?.plan ?? WorkoutPlan(exercises: exercises) }

    var body: some View {
        List {
            Section {
                HStack(spacing: 0) {
                    summaryStat(approxMinutes, "Est. Time")
                    Divider()
                    summaryStat("\(exercises.count)", kind.itemNamePlural)
                    Divider()
                    summaryStat("\(plan.workStepCount)", kind.recapSetsLabel)
                }
                .padding(.vertical, 4)
            }

            ForEach(plan.blocks.indices, id: \.self) { b in
                let block = plan.blocks[b]
                Section {
                    ForEach(Array(block.exerciseRange), id: \.self) { i in
                        exerciseRow(i, block: block)
                    }
                } header: {
                    HStack {
                        Text(blockTitle(block, index: b))
                        Spacer()
                        status(for: b)
                    }
                }
            }
        }
        .captureID("overview.list")
        .navigationTitle(kind == .workout ? "Workout Plan" : "Timer Plan")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
#endif
    }

    private var approxMinutes: String {
        let minutes = Int((plan.estimatedDuration() / 60).rounded())
        return minutes < 1 ? "<1 min" : "~\(minutes) min"
    }

    private func summaryStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func blockTitle(_ block: PlanBlock, index: Int) -> String {
        guard block.isSuperset else {
            return "\(block.roundCount) \(block.roundCount == 1 ? kind.setUnitSingular : kind.recapSetsLabel)"
        }
        let head = exercises[block.exerciseRange.lowerBound]
        var title = "\(kind.supersetActionLabel) · \(block.roundCount) round\(block.roundCount == 1 ? "" : "s")"
        if let budget = head.groupTimeBudget, budget > 0 {
            title += head.groupTimeBudgetScope == .wholeChain ? " in \(SessionFormat.time(budget))" : " · \(SessionFormat.time(budget)) each"
        }
        return title
    }

    @ViewBuilder
    private func status(for blockIndex: Int) -> some View {
        if let engine {
            let current = engine.currentStep?.block ?? plan.blocks.count
            if blockIndex < current {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else if blockIndex == current {
                Text("NOW").font(.caption.bold()).foregroundStyle(Color.accentColor)
            }
        }
    }

    private func exerciseRow(_ i: Int, block: PlanBlock) -> some View {
        let e = exercises[i]
        let name = e.name.trimmingCharacters(in: .whitespaces).isEmpty ? "\(kind.itemName) \(i + 1)" : e.name
        let isCurrent = engine?.headlineExerciseIndex() == i
        return HStack(alignment: .top, spacing: 12) {
            if block.isSuperset {
                Text(String(Character(UnicodeScalar(UInt8(65 + min(25, i - block.exerciseRange.lowerBound))))))
                    .font(.caption.bold())
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.purple.opacity(0.2)))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.body.weight(isCurrent ? .bold : .regular))
                Text(target(e, block: block)).font(.subheadline).foregroundStyle(.secondary)
                if kind == .workout, let last = (history ?? WorkoutHistoryStore.shared).lastPerformance(of: e), !last.summary.isEmpty {
                    Text("Last: \(last.summary)").font(.caption).foregroundStyle(.secondary)
                }
                if let notes = e.notes, !notes.isEmpty {
                    Text(notes).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer()
            if let engine {
                let done = engine.records(forExercise: i).filter { !$0.skipped }.count
                if done > 0 { Text("\(done)/\(block.roundCount)").font(.caption).foregroundStyle(.secondary).monospacedDigit() }
            }
        }
    }

    private func target(_ e: Exercise, block: PlanBlock) -> String {
        var parts: [String] = []
        let count = block.isSuperset ? "" : "\(block.roundCount) × "
        if e.isTimeBased {
            parts.append(count + SessionFormat.time(e.exerciseDuration))
        } else {
            parts.append(count + SessionFormat.reps(e.targetReps, max: e.targetRepsMax))
        }
        if kind == .workout, let w = e.weight, w > 0 { parts.append(SessionFormat.weight(w, unit: e.weightUnit)) }
        let hasBudget = block.isSuperset && (exercises[block.exerciseRange.lowerBound].groupTimeBudget ?? 0) > 0
        if e.restDuration > 0 && !hasBudget { parts.append("\(SessionFormat.time(e.restDuration)) \(kind == .workout ? "rest" : "break")") }
        return parts.joined(separator: " · ")
    }
}
