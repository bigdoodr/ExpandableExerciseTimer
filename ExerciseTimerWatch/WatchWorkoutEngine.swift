import Foundation
import WatchKit
internal import Combine

/// Display state for the watch workout UI.
///
/// The iPhone is the timer authority. It sends a full `SessionSync` (exercise list + engine state)
/// on every change; the watch rebuilds the same `SessionEngine` from it, so every label here —
/// round, rest, Up Next, Timed Superset time left — comes from the exact same code the iPhone
/// uses. (Previously the watch re-derived Up Next on its own from an index and a few flags, and
/// got supersets with in-chain rests wrong.)
@MainActor
final class WatchWorkoutEngine: ObservableObject {

    @Published private(set) var mirror: SessionEngine?
    @Published var exercises: [Exercise] = []
    @Published var kind: SessionKind = .workout
    /// Optimistic local pause flag (the iPhone's next sync confirms or corrects it).
    @Published var isPaused = false
    @Published var isWorkoutRunning = false
    @Published var timeRemaining: TimeInterval = 0
    @Published var healthKitEnabled = false
    @Published var activityTypeName: String?
    @Published private(set) var setsCompleted = 0
    @Published private(set) var exercisesPerformed = 0
    @Published private(set) var now = Date()

    private var workoutID: UUID?
    private var lastRevision = -1

    // MARK: Derived

    var isCompleted: Bool { mirror?.state.isFinished ?? false }
    var isResting: Bool { mirror?.currentStep?.isRest ?? false }
    var phaseEndDate: Date? { mirror?.state.phaseEnd }

    /// The exercise to headline — during a rest, the one coming up (matches the phone).
    var currentExerciseIndex: Int { mirror?.headlineExerciseIndex() ?? 0 }

    var currentExercise: Exercise? {
        guard let mirror, let index = mirror.headlineExerciseIndex() else { return nil }
        return mirror.exercises[index]
    }

    var displayExerciseNumber: Int { exercises.isEmpty ? 0 : currentExerciseIndex + 1 }

    var currentExerciseName: String {
        mirror?.displayName(ofExercise: currentExerciseIndex, kind: kind) ?? kind.itemName
    }

    var progressLabel: String { mirror?.progressLabel(kind: kind) ?? "" }

    var phaseStyle: PhaseStyle { mirror?.phaseStyle() ?? .finished }

    var upNextText: String { mirror?.upNextText(kind: kind, now: now) ?? "" }

    var windowTimeRemaining: TimeInterval? { mirror?.windowTimeRemaining(at: now) }

    var totalSets: Int { mirror?.plan.workStepCount ?? 0 }

    // MARK: Lifecycle

    /// Show the workout UI immediately when a session starts (from either device). The
    /// iPhone's first sync follows within moments; until then the watch shows the first step
    /// from a locally built engine.
    func startWorkout(exercises: [Exercise], kind: SessionKind, healthKitEnabled: Bool, activityType: String?, workoutID: UUID? = nil) {
        self.exercises = exercises
        self.kind = kind
        self.mirror = SessionEngine(exercises: exercises, now: Date())
        self.isPaused = false
        self.isWorkoutRunning = true
        self.healthKitEnabled = healthKitEnabled
        self.activityTypeName = activityType
        self.workoutID = workoutID
        self.lastRevision = -1
        self.setsCompleted = 0
        self.exercisesPerformed = 0
        tickTimer()
    }

    func stopWorkout() {
        isWorkoutRunning = false
        mirror = nil
    }

    /// Apply the iPhone's authoritative state. Returns true if this sync finished the workout.
    @discardableResult
    func apply(_ sync: SessionSync) -> Bool {
        if sync.workoutID != workoutID {
            // Another workout (or none running here). Adopt it only if it's live — a stale state
            // parked in the application context from an earlier session is ignored.
            guard !sync.state.isFinished, Date().timeIntervalSince(sync.state.phaseStart) < 3 * 3600 else { return false }
            lastRevision = -1
        }
        guard sync.revision > lastRevision else { return false }
        let wasFinished = isCompleted
        workoutID = sync.workoutID
        lastRevision = sync.revision
        exercises = sync.exercises
        mirror = SessionEngine(exercises: sync.exercises, state: sync.state)
        isPaused = sync.state.isPaused
        setsCompleted = sync.setsCompleted
        exercisesPerformed = sync.exercisesPerformed
        if !isWorkoutRunning && !sync.state.isFinished { isWorkoutRunning = true }
        tickTimer()
        return !wasFinished && sync.state.isFinished
    }

    // MARK: Display timer

    /// Called every display tick. The engine is deterministic, so the watch advances its own copy
    /// through timed phases — it keeps counting correctly even when the iPhone is locked and
    /// can't send updates. The iPhone's next sync is still authoritative.
    func tickTimer() {
        now = Date()
        guard var engine = mirror, !isPaused, !engine.state.isFinished else { return }
        let events = engine.tick(now: now)
        if events.contains(.phaseChanged) {
            WKInterfaceDevice.current().play(.notification)
            mirror = engine
        }
        timeRemaining = engine.timeRemaining(at: now) ?? 0
    }

    func recalculateOnWake() { tickTimer() }

    func formatTime(_ time: TimeInterval) -> String { SessionFormat.time(time) }
}
