import Foundation

// MARK: - SessionEngine
//
// A pure, deterministic state machine for a running workout. No timers, no SwiftUI, no audio:
// every mutating call takes `now`, so the whole thing is unit-testable and behaves the same on
// iPhone, Mac and (as a mirror) Apple Watch.
//
// Key properties that the previous view-embedded logic didn't have:
// - Catch-up: `tick(now:)` advances through *every* phase that ended while the app was suspended,
//   chaining each phase from the previous phase's end time instead of from "now".
// - Pause freezes Timed Superset budgets too (the old code let the budget drain while paused).
// - Undo restores a full snapshot, so it works for any action (rep-based, skips, timed) and can't
//   leave stray flags behind.
// - The recap is derived from a log of what actually happened, not reconstructed from indices.

/// What happened to one performed (or skipped) set.
struct SetRecord: Codable, Equatable, Identifiable {
    var id = UUID()
    var exerciseID: UUID
    var exerciseIndex: Int
    var exerciseName: String
    var round: Int
    /// Actual reps logged (defaults to the target). `nil` for timed work.
    var reps: Int?
    var weight: Double?
    var weightUnit: WeightUnit
    var activeDuration: TimeInterval
    var skipped: Bool
    var completedAt: Date
}

struct SessionState: Codable, Equatable {
    var stepIndex: Int = 0
    var phaseStart: Date
    /// When the current countdown hits zero. `nil` for manual-advance work.
    var phaseEnd: Date?
    var pausedAt: Date?
    /// Pause time accumulated inside the current phase, excluded from recorded durations.
    var phasePausedTotal: TimeInterval = 0
    /// Deadlines of armed Timed Superset windows, keyed by window index.
    var windowDeadlines: [Int: Date] = [:]
    var isFinished = false
    var endedEarly = false
    var startedAt: Date
    var finishedAt: Date?
    var totalPaused: TimeInterval = 0

    var records: [SetRecord] = []
    var restTime: TimeInterval = 0
    var restSkipped: TimeInterval = 0
    /// Time spent in a set that was cut short by ending the workout.
    var partialActiveTime: TimeInterval = 0

    var isPaused: Bool { pausedAt != nil }
}

/// Things a host might react to (sound, haptics, watch sync). Coalesced per call.
struct EngineEvents: OptionSet {
    let rawValue: Int
    static let phaseChanged = EngineEvents(rawValue: 1 << 0)
    static let finished = EngineEvents(rawValue: 1 << 1)
    static let budgetExpired = EngineEvents(rawValue: 1 << 2)
    static let planChanged = EngineEvents(rawValue: 1 << 3)
}

struct SessionEngine: Equatable {
    private(set) var exercises: [Exercise]
    private(set) var plan: WorkoutPlan
    private(set) var state: SessionState
    /// Snapshots for undo, newest last. Only user actions push here, not timers running out.
    private var undoStack: [UndoSnapshot] = []
    private static let undoLimit = 25

    private struct UndoSnapshot: Equatable {
        var exercises: [Exercise]
        var state: SessionState
    }

    init(exercises: [Exercise], now: Date) {
        var exercises = exercises
        exercises.normalizeSupersets()
        self.exercises = exercises
        self.plan = WorkoutPlan(exercises: exercises)
        self.state = SessionState(phaseStart: now, startedAt: now)
        if plan.steps.isEmpty {
            state.isFinished = true
            state.finishedAt = now
        } else {
            beginStep(0, at: now)
        }
    }

    /// Rebuild a mirror (watch) from a synced snapshot.
    init(exercises: [Exercise], state: SessionState) {
        self.exercises = exercises
        self.plan = WorkoutPlan(exercises: exercises)
        self.state = state
    }

    // MARK: Read-only views

    var currentStep: PlanStep? {
        guard !state.isFinished, plan.steps.indices.contains(state.stepIndex) else { return nil }
        return plan.steps[state.stepIndex]
    }

    var currentExercise: Exercise? {
        currentStep.map { exercises[$0.exerciseIndex] }
    }

    var nextStep: PlanStep? {
        let i = state.stepIndex + 1
        return plan.steps.indices.contains(i) && !state.isFinished ? plan.steps[i] : nil
    }

    /// The next *work* step after the current one (skipping rests) — what "Up Next" names.
    var nextWorkStep: PlanStep? {
        guard !state.isFinished else { return nil }
        return plan.steps[(state.stepIndex + 1)...].first { $0.kind == .work }
    }

    func timeRemaining(at now: Date) -> TimeInterval? {
        guard let end = state.phaseEnd else { return nil }
        let reference = state.pausedAt ?? now
        return max(0, end.timeIntervalSince(reference))
    }

    /// Time left in the Timed Superset window the current step belongs to, if any.
    func windowTimeRemaining(at now: Date) -> TimeInterval? {
        guard let w = currentStep?.window, let deadline = state.windowDeadlines[w] else { return nil }
        let reference = state.pausedAt ?? now
        return max(0, deadline.timeIntervalSince(reference))
    }

    var currentWindow: BudgetWindow? { currentStep?.window.map { plan.windows[$0] } }

    var canUndo: Bool { !undoStack.isEmpty }

    /// The most recent record, for the "log this set" card during the following rest.
    var lastRecord: SetRecord? { state.records.last }

    func records(forExercise index: Int) -> [SetRecord] {
        state.records.filter { $0.exerciseIndex == index }
    }

    // MARK: Time

    /// Advance through every phase whose countdown (or budget) has run out by `now`.
    @discardableResult
    mutating func tick(now: Date) -> EngineEvents {
        var events: EngineEvents = []
        var guardCounter = 0
        while !state.isFinished, !state.isPaused, guardCounter < 10_000 {
            guardCounter += 1
            guard let step = currentStep else { break }

            // Hard-cap budget windows end the chain wherever it is.
            if step.kind == .work, let w = step.window, plan.windows[w].isHardCap,
               let deadline = state.windowDeadlines[w], deadline <= now,
               state.phaseEnd.map({ deadline <= $0 }) ?? true {
                // The set in progress was cut off by the cap, so it doesn't count as completed.
                finishPhase(at: deadline, skipped: true, log: nil)
                events.insert(.budgetExpired)
                jump(to: plan.windows[w].endStep, at: deadline, markSkipped: true)
                events.insert(.phaseChanged)
                continue
            }

            guard let end = state.phaseEnd, end <= now else { break }
            finishPhase(at: end, skipped: false, log: nil)
            beginStep(state.stepIndex + 1, at: end)
            events.insert(.phaseChanged)
        }
        if state.isFinished { events.insert(.finished) }
        return events
    }

    mutating func pause(now: Date) {
        guard !state.isFinished, !state.isPaused else { return }
        state.pausedAt = now
    }

    mutating func resume(now: Date) {
        guard let pausedAt = state.pausedAt else { return }
        let delta = max(0, now.timeIntervalSince(pausedAt))
        state.pausedAt = nil
        state.phaseEnd = state.phaseEnd?.addingTimeInterval(delta)
        // Budgets freeze while paused, too.
        for (k, v) in state.windowDeadlines { state.windowDeadlines[k] = v.addingTimeInterval(delta) }
        state.phasePausedTotal += delta
        state.totalPaused += delta
    }

    // MARK: User actions

    /// Finish the current work step (the "Reps Complete" / "Done" button) and log what was done.
    /// `reps`/`weight` default to the exercise's targets.
    @discardableResult
    mutating func completeSet(now: Date, reps: Int? = nil, weight: Double? = nil) -> EngineEvents {
        guard let step = currentStep, step.kind == .work else { return [] }
        if state.isPaused { resume(now: now) }
        pushUndo()
        finishPhase(at: now, skipped: false, log: SetLog(reps: reps, weight: weight))
        beginStep(state.stepIndex + 1, at: now)
        return tick(now: now).union(.phaseChanged)
    }

    /// Skip the current phase (a set or a rest).
    @discardableResult
    mutating func skip(now: Date) -> EngineEvents {
        guard currentStep != nil else { return [] }
        if state.isPaused { resume(now: now) }
        pushUndo()
        finishPhase(at: now, skipped: true, log: nil)
        beginStep(state.stepIndex + 1, at: now)
        return tick(now: now).union(.phaseChanged)
    }

    /// Skip the rest of the current exercise / superset (every remaining set or round) — e.g.
    /// the equipment is taken, or something doesn't feel right today.
    @discardableResult
    mutating func skipBlock(now: Date) -> EngineEvents {
        guard let step = currentStep else { return [] }
        if state.isPaused { resume(now: now) }
        pushUndo()
        finishPhase(at: now, skipped: true, log: nil)
        jump(to: plan.blocks[step.block].endStep, at: now, markSkipped: true)
        return tick(now: now).union(.phaseChanged)
    }

    /// Add one more set (lone exercise) or round (superset) to the current block.
    @discardableResult
    mutating func addSetToCurrentBlock(now: Date) -> EngineEvents {
        guard let step = currentStep else { return [] }
        pushUndo()
        let head = plan.blocks[step.block].exerciseRange.lowerBound
        if plan.blocks[step.block].isSuperset {
            exercises[head].chainRepeatCount += 1
        } else {
            exercises[head].sets += 1
        }
        recompile(keeping: step)
        // If we were sitting in the final rest-less spot, the new set may need a rest before it:
        // recompiling handles that because rests are derived from the plan.
        return [.planChanged]
    }

    /// Edit an exercise mid-session (weight, reps, name for a swap). Structural fields like sets
    /// and linking go through the dedicated actions above so your place is preserved.
    @discardableResult
    mutating func updateExercise(at index: Int, _ change: (inout Exercise) -> Void) -> EngineEvents {
        guard exercises.indices.contains(index) else { return [] }
        let before = exercises[index]
        change(&exercises[index])
        // Keep structure stable.
        exercises[index].id = before.id
        exercises[index].isSupersetContinuation = before.isSupersetContinuation
        exercises[index].sets = before.sets
        exercises[index].chainRepeatCount = before.chainRepeatCount
        exercises[index].groupTimeBudget = before.groupTimeBudget
        exercises[index].groupTimeBudgetScope = before.groupTimeBudgetScope
        exercises[index].isTimeBased = before.isTimeBased
        if let step = currentStep { recompile(keeping: step) } else { plan = WorkoutPlan(exercises: exercises) }
        return [.planChanged]
    }

    /// Correct the reps/weight logged for a finished set (e.g. from the card shown during rest).
    mutating func amendRecord(id: UUID, reps: Int?, weight: Double?) {
        guard let i = state.records.firstIndex(where: { $0.id == id }) else { return }
        state.records[i].reps = reps
        state.records[i].weight = weight
    }

    @discardableResult
    mutating func undo(now: Date) -> Bool {
        guard let snapshot = undoStack.popLast() else { return false }
        exercises = snapshot.exercises
        plan = WorkoutPlan(exercises: exercises)
        let deadlines = snapshot.state.windowDeadlines
        let totalPaused = state.totalPaused
        state = snapshot.state
        state.totalPaused = totalPaused
        // Re-run the restored phase from now: its countdown restarts, but budget deadlines keep
        // their wall-clock times (that time really did pass).
        state.isFinished = false
        state.finishedAt = nil
        state.pausedAt = nil
        state.windowDeadlines = deadlines
        beginStep(state.stepIndex, at: now, armWindow: false)
        return true
    }

    /// End early (Cancel / End Workout).
    mutating func end(now: Date) {
        guard !state.isFinished else { return }
        if state.isPaused { resume(now: now) }
        finishPhase(at: now, skipped: false, log: nil, endingEarly: true)
        state.isFinished = true
        state.endedEarly = true
        state.finishedAt = now
        state.phaseEnd = nil
    }

    // MARK: Internals

    private mutating func pushUndo() {
        undoStack.append(UndoSnapshot(exercises: exercises, state: state))
        if undoStack.count > Self.undoLimit { undoStack.removeFirst() }
    }

    private mutating func recompile(keeping step: PlanStep) {
        plan = WorkoutPlan(exercises: exercises)
        if let i = plan.stepIndex(matching: StepKey(step)) {
            state.stepIndex = i
        }
        // Window indices may have shifted; drop deadlines that no longer map to the same block.
        state.windowDeadlines = state.windowDeadlines.filter { plan.windows.indices.contains($0.key) }
    }

    /// Records the phase that's ending. `endingEarly` counts partial time without logging a set.
    private struct SetLog { var reps: Int?; var weight: Double? }

    private mutating func finishPhase(at time: Date, skipped: Bool, log: SetLog?, endingEarly: Bool = false) {
        guard let step = currentStep else { return }
        let elapsed = max(0, time.timeIntervalSince(state.phaseStart) - state.phasePausedTotal)
        switch step.kind {
        case .work:
            if endingEarly {
                // Partial set: the time counts, but it isn't a completed (or skipped) set.
                state.partialActiveTime += elapsed
                return
            }
            let exercise = exercises[step.exerciseIndex]
            var reps: Int? = nil
            var weight: Double? = exercise.weight
            if !exercise.isTimeBased && !skipped { reps = log?.reps ?? exercise.targetReps }
            if let w = log?.weight { weight = w }
            appendRecord(step: step, at: time, elapsed: elapsed, skipped: skipped, reps: reps, weight: weight)
        case .rest, .budgetRest:
            state.restTime += elapsed
            if skipped || endingEarly, let end = state.phaseEnd {
                state.restSkipped += max(0, end.timeIntervalSince(time))
            }
        }
    }

    private mutating func appendRecord(step: PlanStep, at time: Date, elapsed: TimeInterval, skipped: Bool, reps: Int?, weight: Double?) {
        let exercise = exercises[step.exerciseIndex]
        state.records.append(SetRecord(
            exerciseID: exercise.id, exerciseIndex: step.exerciseIndex, exerciseName: exercise.name,
            round: step.round, reps: reps, weight: weight, weightUnit: exercise.weightUnit,
            activeDuration: elapsed, skipped: skipped, completedAt: time))
    }

    /// Jump to `target`, logging every work step passed over as skipped.
    private mutating func jump(to target: Int, at time: Date, markSkipped: Bool) {
        if markSkipped {
            var i = state.stepIndex + 1
            while i < min(target, plan.steps.count) {
                let s = plan.steps[i]
                if s.kind == .work {
                    appendRecord(step: s, at: time, elapsed: 0, skipped: true, reps: nil, weight: nil)
                }
                i += 1
            }
        }
        beginStep(target, at: time)
    }

    private mutating func beginStep(_ index: Int, at time: Date, armWindow: Bool = true) {
        state.phasePausedTotal = 0
        guard index < plan.steps.count else {
            state.stepIndex = plan.steps.count
            state.isFinished = true
            state.finishedAt = time
            state.phaseEnd = nil
            state.phaseStart = time
            return
        }
        state.stepIndex = index
        state.phaseStart = time
        let step = plan.steps[index]

        if armWindow, let w = step.window, state.windowDeadlines[w] == nil {
            state.windowDeadlines[w] = time.addingTimeInterval(plan.windows[w].duration)
        }

        switch step.kind {
        case .work, .rest:
            state.phaseEnd = step.duration.map { time.addingTimeInterval($0) }
        case .budgetRest:
            let deadline = step.window.flatMap { state.windowDeadlines[$0] } ?? time
            if deadline <= time {
                // No time left over: go straight on.
                beginStep(index + 1, at: time)
            } else {
                state.phaseEnd = deadline
            }
        }
    }
}

extension SessionEngine {
    /// When the engine will next change on its own: the current countdown, or a hard-cap
    /// budget that runs out first. `nil` while waiting on the person (or paused).
    var nextEventDate: Date? {
        guard !state.isPaused, let step = currentStep else { return nil }
        var candidates: [Date] = []
        if let end = state.phaseEnd { candidates.append(end) }
        if step.kind == .work, let w = step.window, plan.windows[w].isHardCap, let d = state.windowDeadlines[w] {
            candidates.append(d)
        }
        return candidates.min()
    }
}

// MARK: - Recap

struct SessionRecap: Codable, Equatable {
    var duration: TimeInterval
    var completedNaturally: Bool
    var exercisesPerformed: Int
    var exerciseCount: Int
    var setsCompleted: Int
    var totalSets: Int
    var activeTime: TimeInterval
    var restTime: TimeInterval
    var setsSkipped: Int
    var restSkipped: TimeInterval
    var records: [SetRecord]
}

extension SessionEngine {
    func recap(now: Date) -> SessionRecap {
        let end = state.finishedAt ?? now
        let completed = state.records.filter { !$0.skipped }
        return SessionRecap(
            duration: max(0, end.timeIntervalSince(state.startedAt)),
            completedNaturally: state.isFinished && !state.endedEarly,
            exercisesPerformed: Set(completed.map(\.exerciseIndex)).count,
            exerciseCount: exercises.count,
            setsCompleted: completed.count,
            totalSets: plan.workStepCount,
            activeTime: state.records.reduce(state.partialActiveTime) { $0 + $1.activeDuration },
            restTime: state.restTime,
            setsSkipped: state.records.filter(\.skipped).count,
            restSkipped: state.restSkipped,
            records: state.records)
    }
}
