#if DEBUG
import Foundation

// MARK: - Screenshot scenes (shared by the iPhone/iPad/Mac app and the watch app)
//
// The workouts behind the App Store screenshots, and the engine states each scene freezes at.
// Foundation only, so the watch app can build exactly the same states as the phone. The phone's
// `ScreenshotMode` adds seeded history, plans and Health values on top; the watch's
// `WatchWorkoutView` shows the frozen engine directly.

enum ScreenshotScene: String, CaseIterable {
    case plan, manualSet, superset, timedSuperset, restLog, overview, recap, routines, timer, createPlan

    /// The session kind this scene runs as a frozen session, or `nil` for non-session scenes.
    var sessionKind: SessionKind? {
        switch self {
        case .manualSet, .superset, .timedSuperset, .restLog, .overview, .recap: return .workout
        case .timer: return .timer
        case .plan, .routines, .createPlan: return nil
        }
    }

    /// The scene named by `-screenshotScene <name>` when `-screenshotMode` is on.
    static var requested: ScreenshotScene? {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-screenshotMode"),
              let i = args.firstIndex(of: "-screenshotScene"), args.indices.contains(i + 1) else { return nil }
        return ScreenshotScene(rawValue: args[i + 1])
    }
}

extension ScreenshotScene {
    /// `-screenshotScroll <points>`: how far the watch's scroll view starts scrolled, so a capture
    /// can show content below the fold (a real watch scrolls with the Digital Crown).
    static var requestedScrollOffset: Double? {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-screenshotMode"),
              let i = args.firstIndex(of: "-screenshotScroll"), args.indices.contains(i + 1) else { return nil }
        return Double(args[i + 1])
    }
}

/// A session engine paused at a chosen moment.
struct FrozenSession {
    var engine: SessionEngine
    /// "Now" for every countdown and elapsed-time readout.
    var now: Date
    var kind: SessionKind
    var routineName: String
}

enum ScreenshotScenes {
    /// When the capture was launched. Every scene's engine starts here (and the phone's seeded
    /// history is dated relative to it).
    static let base = Date()

    // MARK: Workouts

    private static func uuid(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n)) ?? UUID()
    }

    private static func repExercise(_ id: Int, _ name: String, sets: Int, reps: Int, repsMax: Int? = nil,
                                    weight: Double? = nil, rest: TimeInterval) -> Exercise {
        var e = Exercise()
        e.id = uuid(id)
        e.name = name
        e.isTimeBased = false
        e.sets = sets
        e.targetReps = reps
        e.targetRepsMax = repsMax
        e.weight = weight
        e.restDuration = rest
        return e
    }

    private static func timedExercise(_ id: Int, _ name: String, sets: Int = 1, seconds: TimeInterval, rest: TimeInterval) -> Exercise {
        var e = Exercise()
        e.id = uuid(id)
        e.name = name
        e.isTimeBased = true
        e.sets = sets
        e.exerciseDuration = seconds
        e.restDuration = rest
        return e
    }

    static let upperPush: [Exercise] = [
        repExercise(1, "Bench Press", sets: 4, reps: 8, repsMax: 10, weight: 135, rest: 90),
        repExercise(2, "Overhead Press", sets: 3, reps: 8, repsMax: 10, weight: 85, rest: 90),
        repExercise(3, "Incline DB Press", sets: 3, reps: 10, repsMax: 12, weight: 50, rest: 75),
        repExercise(4, "Triceps Pushdown", sets: 3, reps: 12, repsMax: 15, weight: 50, rest: 60),
    ]

    /// Squat and deadlift, then a 3-round superset of two timed moves, then calves.
    static let legDay: [Exercise] = {
        var jumpSquat = timedExercise(13, "Jump Squat", seconds: 45, rest: 0)
        jumpSquat.chainRepeatCount = 3
        var climber = timedExercise(14, "Mountain Climber", seconds: 45, rest: 60)
        climber.isSupersetContinuation = true
        return [
            repExercise(11, "Barbell Back Squat", sets: 4, reps: 6, repsMax: 8, weight: 225, rest: 120),
            repExercise(12, "Deadlift", sets: 3, reps: 5, weight: 275, rest: 150),
            jumpSquat,
            climber,
            repExercise(15, "Standing Calf Raise", sets: 3, reps: 15, weight: 90, rest: 45),
        ]
    }()

    /// A Timed Superset: 10 rounds of three moves in 12:00, the budget shared by the whole chain.
    static let metCon: [Exercise] = {
        var squat = repExercise(21, "Goblet Squat", sets: 1, reps: 10, weight: 40, rest: 0)
        squat.chainRepeatCount = 10
        squat.groupTimeBudget = 720
        squat.groupTimeBudgetScope = .wholeChain
        var pushUp = repExercise(22, "Push-Up", sets: 1, reps: 15, rest: 0)
        pushUp.isSupersetContinuation = true
        var swing = repExercise(23, "Kettlebell Swing", sets: 1, reps: 15, weight: 53, rest: 0)
        swing.isSupersetContinuation = true
        return [squat, pushUp, swing]
    }()

    /// Eight 20-second intervals with 10-second breaks.
    static let tabata: [Exercise] = [timedExercise(31, "Burpees", sets: 8, seconds: 20, rest: 10)]

    // MARK: Engine states

    /// Runs a fresh engine forward with explicit dates until it reaches `step` (or finishes):
    /// manual sets take `manualSeconds` each, timed phases run their full length. Returns the
    /// engine and the moment the current step began.
    static func play(_ exercises: [Exercise], from start: Date = base, toStep step: Int, manualSeconds: TimeInterval = 40,
                     reps: (PlanStep) -> Int? = { _ in nil }) -> (engine: SessionEngine, clock: Date) {
        var engine = SessionEngine(exercises: exercises, now: start)
        var clock = start
        while engine.state.stepIndex < step, !engine.state.isFinished, let current = engine.currentStep {
            if current.kind == .work, current.duration == nil {
                clock = clock.addingTimeInterval(manualSeconds)
                engine.completeSet(now: clock, reps: reps(current))
            } else if let end = engine.state.phaseEnd {
                clock = end
                engine.tick(now: clock)
            } else {
                break
            }
        }
        return (engine, clock)
    }

    /// The engine state for a session scene, started at `start`; `nil` for scenes that aren't sessions.
    static func session(for scene: ScreenshotScene, from start: Date = base) -> FrozenSession? {
        func frozen(_ played: (engine: SessionEngine, clock: Date), elapsedInStep: TimeInterval = 0,
                    kind: SessionKind = .workout, name: String) -> FrozenSession {
            FrozenSession(engine: played.engine, now: played.clock.addingTimeInterval(elapsedInStep),
                          kind: kind, routineName: name)
        }

        switch scene {
        case .manualSet:
            // Bench Press, set 2 of 4: set 1 logged at 10 reps, 6 s into the next set.
            let played = play(upperPush, from: start, toStep: 2) { $0.round == 1 ? 10 : nil }
            return frozen(played, elapsedInStep: 6, name: "Upper Push")

        case .restLog:
            // Bench is two sets here so that the next exercise (Overhead Press) differs from the
            // one just logged. 18 s into the 90 s rest leaves 1:12.
            var list = upperPush
            list[0].sets = 2
            let played = play(list, from: start, toStep: 3) { _ in 10 }
            return frozen(played, elapsedInStep: 18, name: "Upper Push")

        case .superset, .overview:
            // Leg Day: round 2 of the superset, second move (Mountain Climber), 11 s into its 45 s.
            let played = play(legDay, from: start, toStep: 18)
            return frozen(played, elapsedInStep: 11, name: "Leg Day")

        case .timedSuperset:
            // Thirteen sets at 19 s, then 11 s into the next: 258 s of the 720 s budget gone, 7:42 left.
            let played = play(metCon, from: start, toStep: 13, manualSeconds: 19)
            return frozen(played, elapsedInStep: 11, name: "Friday MetCon")

        case .recap:
            // The whole of Leg Day, deadlift at 295 lb: heavier than anything in the phone's history.
            var list = legDay
            list[1].weight = 295
            return frozen(play(list, from: start, toStep: .max), name: "Leg Day")

        case .timer:
            // Tabata, third break, 4 s in: 0:06 left.
            return frozen(play(tabata, from: start, toStep: 5), elapsedInStep: 4, kind: .timer, name: "Tabata")

        case .plan, .routines, .createPlan:
            return nil
        }
    }

    /// The same scene, started so that "now" is the present moment, for a clip where the countdown
    /// should actually run (`-screenshotLive`). The engine behaves as if the workout began however
    /// long the scene's earlier steps took, so the live clock picks up where the scene stops.
    static func liveSession(for scene: ScreenshotScene) -> FrozenSession? {
        let probeStart = Date()
        guard let probe = session(for: scene, from: probeStart) else { return nil }
        let elapsed = probe.now.timeIntervalSince(probeStart)
        return session(for: scene, from: Date().addingTimeInterval(-elapsed))
    }
}
#endif
