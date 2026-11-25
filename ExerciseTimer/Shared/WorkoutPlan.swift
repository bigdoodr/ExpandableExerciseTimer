import Foundation

// MARK: - WorkoutPlan
//
// The routine editor stores exercises the way people think about them: a flat list where some
// entries are "linked" to the one before (supersets / circuits), with round counts and optional
// time budgets living on the first member of each chain.
//
// That shape is great for editing but awkward to *run*: the old session code walked it with a
// handful of interlocking flags (`currentSet`, `isResting`, `restAdvancesWithinGroup`,
// `currentRestDurationOverride`, `groupRoundEndDate`, ...) and re-derived "what happens next"
// separately for the phone timer, the phone's Up Next label, and the watch's Up Next label.
// Every new superset feature had to be threaded through all of them, and they drifted.
//
// `WorkoutPlan` compiles the list ONCE into a linear timeline of steps. Running a workout is then
// just "move to the next step" — and every device and label reads the same timeline.

/// One unit of the timeline: perform an exercise, or rest.
struct PlanStep: Codable, Equatable, Hashable {
    enum Kind: String, Codable {
        /// Perform `exerciseIndex` once (one set / one round's worth).
        case work
        /// A fixed-length rest after `exerciseIndex`.
        case rest
        /// A Timed Superset's leftover-time rest: whatever is left of the budget window when the
        /// window's work is done. Its length is only known at runtime.
        case budgetRest
    }

    var kind: Kind
    /// For `.work`, the exercise performed. For rests, the exercise the rest follows.
    var exerciseIndex: Int
    /// 1-based round (or set, for a lone exercise) this step belongs to.
    var round: Int
    var roundCount: Int
    /// Index into `WorkoutPlan.blocks`.
    var block: Int
    /// Countdown length. `nil` for manual-advance (rep/prompt-based) work and for `.budgetRest`.
    var duration: TimeInterval?
    /// Index into `WorkoutPlan.windows` when this step runs under a Timed Superset budget.
    var window: Int?

    var isRest: Bool { kind != .work }
}

/// A run of linked exercises (or a single exercise) that repeats as a unit.
struct PlanBlock: Codable, Equatable, Hashable {
    var exerciseRange: ClosedRange<Int>
    var roundCount: Int
    /// First step of this block, and one past its last step.
    var firstStep: Int
    var endStep: Int
    var isSuperset: Bool { exerciseRange.count > 1 }
}

/// A Timed Superset budget: a deadline armed when `firstStep` begins.
struct BudgetWindow: Codable, Equatable, Hashable {
    var block: Int
    var duration: TimeInterval
    /// `wholeChain` budgets are hard caps: when time runs out the chain ends wherever it is.
    /// `perRound` budgets just turn leftover time into rest (an over-time round runs to completion).
    var isHardCap: Bool
    var firstStep: Int
    /// One past the window's last step (including its trailing `.budgetRest`, if any).
    var endStep: Int
}

struct WorkoutPlan: Codable, Equatable {
    var steps: [PlanStep]
    var blocks: [PlanBlock]
    var windows: [BudgetWindow]

    init(exercises: [Exercise]) {
        var steps: [PlanStep] = []
        var blocks: [PlanBlock] = []
        var windows: [BudgetWindow] = []

        var index = 0
        while index < exercises.count {
            let range = exercises.supersetGroupRange(containing: index)
            let head = exercises[range.lowerBound]
            let isSuperset = range.count > 1
            let rounds = max(1, isSuperset ? head.chainRepeatCount : head.sets)
            let blockIndex = blocks.count
            let isLastBlock = range.upperBound == exercises.count - 1
            let blockStart = steps.count

            // Budgets only apply to real chains. A stale `groupTimeBudget` left on an exercise
            // that was later unlinked is ignored rather than silently changing how it runs.
            let budget: TimeInterval? = isSuperset ? head.groupTimeBudget.flatMap { $0 > 0 ? $0 : nil } : nil
            let scope = head.groupTimeBudgetScope

            func work(_ exerciseIndex: Int, round: Int, window: Int?) -> PlanStep {
                let exercise = exercises[exerciseIndex]
                return PlanStep(kind: .work, exerciseIndex: exerciseIndex, round: round, roundCount: rounds,
                                block: blockIndex,
                                duration: exercise.isTimeBased ? max(1, exercise.exerciseDuration) : nil,
                                window: window)
            }
            func rest(after exerciseIndex: Int, round: Int, duration: TimeInterval) -> PlanStep {
                PlanStep(kind: .rest, exerciseIndex: exerciseIndex, round: round, roundCount: rounds,
                         block: blockIndex, duration: duration, window: nil)
            }

            if let budget, scope == .wholeChain {
                // One window over every round; members run back-to-back; leftover becomes rest.
                let w = windows.count
                windows.append(BudgetWindow(block: blockIndex, duration: budget, isHardCap: true, firstStep: steps.count, endStep: 0))
                for round in 1...rounds {
                    for i in range { steps.append(work(i, round: round, window: w)) }
                }
                if !isLastBlock {
                    steps.append(PlanStep(kind: .budgetRest, exerciseIndex: range.upperBound, round: rounds,
                                          roundCount: rounds, block: blockIndex, duration: nil, window: w))
                }
                windows[w].endStep = steps.count
            } else if let budget {
                // A fresh window every round.
                for round in 1...rounds {
                    let w = windows.count
                    windows.append(BudgetWindow(block: blockIndex, duration: budget, isHardCap: false, firstStep: steps.count, endStep: 0))
                    for i in range { steps.append(work(i, round: round, window: w)) }
                    let isVeryLast = isLastBlock && round == rounds
                    if !isVeryLast {
                        steps.append(PlanStep(kind: .budgetRest, exerciseIndex: range.upperBound, round: round,
                                              roundCount: rounds, block: blockIndex, duration: nil, window: w))
                    }
                    windows[w].endStep = steps.count
                }
            } else {
                for round in 1...rounds {
                    for i in range {
                        steps.append(work(i, round: round, window: nil))
                        let restDuration = exercises[i].restDuration
                        let isVeryLast = isLastBlock && round == rounds && i == range.upperBound
                        // Each member's own rest is honored between linked exercises and between
                        // rounds. No pointless rest after the final step of the whole workout.
                        if restDuration > 0 && !isVeryLast {
                            steps.append(rest(after: i, round: round, duration: restDuration))
                        }
                    }
                }
            }

            blocks.append(PlanBlock(exerciseRange: range, roundCount: rounds, firstStep: blockStart, endStep: steps.count))
            index = range.upperBound + 1
        }

        self.steps = steps
        self.blocks = blocks
        self.windows = windows
    }

    var workStepCount: Int { steps.lazy.filter { $0.kind == .work }.count }

    /// Rough total length, counting manual-advance work as `assumedManualDuration` and budget
    /// windows as their full budget. Used for the pre-workout overview ("about 35 min").
    func estimatedDuration(assumedManualDuration: TimeInterval = 45) -> TimeInterval {
        var total: TimeInterval = 0
        var countedWindows = Set<Int>()
        for step in steps {
            if let w = step.window {
                if countedWindows.insert(w).inserted { total += windows[w].duration }
                continue
            }
            switch step.kind {
            case .work: total += step.duration ?? assumedManualDuration
            case .rest: total += step.duration ?? 0
            case .budgetRest: break
            }
        }
        return total
    }

    /// The step index matching `key` in this plan, used to keep your place after the plan is
    /// recompiled mid-session (e.g. after adding a set).
    func stepIndex(matching key: StepKey) -> Int? {
        steps.firstIndex { $0.kind == key.kind && $0.exerciseIndex == key.exerciseIndex && $0.round == key.round }
    }
}

/// Identifies a step independent of its position, so it survives a plan recompile.
struct StepKey: Codable, Equatable, Hashable {
    var kind: PlanStep.Kind
    var exerciseIndex: Int
    var round: Int
    init(_ step: PlanStep) {
        kind = step.kind
        exerciseIndex = step.exerciseIndex
        round = step.round
    }
}
