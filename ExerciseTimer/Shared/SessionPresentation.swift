import Foundation

// MARK: - Shared wording
//
// Every label that describes "where am I / what's next" is derived here from the engine, so the
// iPhone, Mac and Apple Watch can never disagree (they used to compute Up Next independently).

enum PhaseStyle: Equatable {
    case timedWork, manualWork, rest, finished
}

extension SessionEngine {
    func phaseStyle() -> PhaseStyle {
        guard let step = currentStep else { return .finished }
        if step.isRest { return .rest }
        return step.duration == nil ? .manualWork : .timedWork
    }

    func displayName(ofExercise index: Int, kind: SessionKind) -> String {
        guard exercises.indices.contains(index) else { return kind.itemName }
        let name = exercises[index].name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "\(kind.itemName) \(index + 1)" : name
    }

    /// The headline exercise. During a rest it's the exercise coming up next, which is what
    /// you're actually preparing for (the old UI kept showing the one you just finished).
    func headlineExerciseIndex() -> Int? {
        guard let step = currentStep else { return nil }
        if step.isRest { return nextWorkStep?.exerciseIndex ?? step.exerciseIndex }
        return step.exerciseIndex
    }

    /// "Set 2 of 4" or "Round 2 of 3", for the step the headline refers to.
    func progressLabel(kind: SessionKind) -> String {
        guard let step = currentStep else { return "" }
        let target = step.isRest ? (nextWorkStep ?? step) : step
        if plan.blocks[target.block].isSuperset {
            return "Round \(target.round) of \(target.roundCount)"
        }
        return "\(kind.setUnitSingular) \(target.round) of \(target.roundCount)"
    }

    /// Position of the headline exercise within its superset, e.g. "A2" style "2 of 3 in superset".
    func supersetPositionLabel(kind: SessionKind) -> String? {
        guard let index = headlineExerciseIndex(), let step = currentStep else { return nil }
        let block = plan.blocks[(step.isRest ? (nextWorkStep ?? step) : step).block]
        guard block.isSuperset, block.exerciseRange.contains(index) else { return nil }
        let position = index - block.exerciseRange.lowerBound + 1
        return "\(kind.supersetActionLabel) · \(position) of \(block.exerciseRange.count)"
    }

    func phaseLabel(kind: SessionKind) -> String {
        switch phaseStyle() {
        case .timedWork: return kind.activePhaseLabel
        case .manualWork: return kind.manualPhaseLabel
        case .rest: return kind.restPhaseLabel
        case .finished: return kind.upNextCompleteLabel
        }
    }

    func upNextText(kind: SessionKind, now: Date) -> String {
        guard let step = currentStep else { return "" }
        if step.isRest {
            // The headline already shows what's coming; Up Next looks one step further.
            guard let upcoming = nextWorkStep else { return "Up Next: \(kind.upNextCompleteLabel)" }
            return "Then: " + describeAfter(stepIndex: plan.steps.firstIndex(of: upcoming) ?? state.stepIndex, kind: kind, now: now)
        }
        return "Up Next: " + describeAfter(stepIndex: state.stepIndex, kind: kind, now: now)
    }

    private func describeAfter(stepIndex: Int, kind: SessionKind, now: Date) -> String {
        let i = stepIndex + 1
        guard plan.steps.indices.contains(i) else { return kind.upNextCompleteLabel }
        let next = plan.steps[i]
        switch next.kind {
        case .rest:
            return "\(kind == .workout ? "Rest" : "Break") (\(SessionFormat.time(next.duration ?? 0)))"
        case .budgetRest:
            if let w = next.window, let deadline = state.windowDeadlines[w] {
                let left = max(0, deadline.timeIntervalSince(state.pausedAt ?? now))
                return left > 0 ? "\(kind == .workout ? "Rest" : "Break") (\(SessionFormat.time(left)) left over)" : describeAfter(stepIndex: i, kind: kind, now: now)
            }
            return kind == .workout ? "Rest (leftover time)" : "Break (leftover time)"
        case .work:
            var text = displayName(ofExercise: next.exerciseIndex, kind: kind)
            let current = plan.steps[stepIndex]
            if plan.blocks[next.block].isSuperset && next.round != current.round && next.block == current.block {
                text += " – Round \(next.round)"
            }
            let summary = exercises[next.exerciseIndex].quickSummary
            return summary.isEmpty ? text : "\(text) · \(summary)"
        }
    }
}

enum SessionFormat {
    static func time(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.up))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func weight(_ weight: Double?, unit: WeightUnit) -> String {
        guard let weight, weight > 0 else { return "Bodyweight" }
        let n = weight.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(weight)) : String(format: "%.1f", weight)
        return "\(n) \(unit.rawValue)"
    }

    static func reps(_ reps: Int?, max: Int?) -> String {
        guard let reps else { return "AMRAP" }
        if let max, max != reps { return "\(reps)–\(max) reps" }
        return "\(reps) reps"
    }
}

// MARK: - Watch sync payload

/// Everything the watch needs to mirror the phone exactly: the (possibly edited) exercise list and
/// the engine state. The watch compiles the same `WorkoutPlan` locally, so it derives the same
/// labels. Sent whole on every change — a few KB — so a dropped message self-heals on the next one.
struct SessionSync: Codable, Equatable {
    var workoutID: UUID
    var revision: Int
    var exercises: [Exercise]
    /// Engine state, with the set log trimmed to the last record to keep the payload small.
    var state: SessionState
    /// Counts from the full set log, for the watch's recap.
    var setsCompleted: Int
    var exercisesPerformed: Int
}

extension SessionSync {
    init(workoutID: UUID, revision: Int, engine: SessionEngine) {
        var trimmed = engine.state
        trimmed.records = engine.lastRecord.map { [$0] } ?? []
        let done = engine.state.records.filter { !$0.skipped }
        self.init(workoutID: workoutID, revision: revision, exercises: engine.exercises, state: trimmed,
                  setsCompleted: done.count, exercisesPerformed: Set(done.map(\.exerciseIndex)).count)
    }
}
