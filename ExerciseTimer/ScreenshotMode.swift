#if DEBUG
import SwiftUI
import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Screenshot mode
//
// DEBUG-only support for capturing App Store screenshots deterministically.
//
//   -screenshotMode              seeded, isolated data; no onboarding; frozen clock
//   -screenshotScene <name>      jump straight to one scene (see `ScreenshotScene`)
//
// Nothing here changes session or plan behaviour: it builds a `SessionEngine` with explicit
// dates, wraps it in a `SessionController` that never starts its ticker, and seeds a throwaway
// history, plan, UserDefaults suite and (on iOS) fake Health values.

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
}

@MainActor
enum ScreenshotMode {
    // MARK: Flags

    static let isActive = ProcessInfo.processInfo.arguments.contains("-screenshotMode")

    static let scene: ScreenshotScene? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-screenshotScene"), args.indices.contains(i + 1) else { return nil }
        return ScreenshotScene(rawValue: args[i + 1])
    }()

    static var opensPlanSheet: Bool { scene == .overview }
    static var opensCreatePlan: Bool { scene == .createPlan }

    static var initialTab: AppTab {
        switch scene {
        case .plan, .createPlan: return .plan
        case .routines: return .routines
        case .timer: return .timers
        default: return .exercises
        }
    }

    // MARK: Isolated storage

    /// A fresh temporary directory for `WorkoutHistoryStore` and `TrainingPlanStore`; `nil` when off.
    static let storeDirectory: URL? = {
        guard isActive else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("EETScreenshotMode", isDirectory: true)
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// A separate UserDefaults suite, wiped on every launch.
    static let defaultsSuite: UserDefaults? = {
        let name = "com.bigdoodr.ExerciseTimer.screenshotMode"
        UserDefaults().removePersistentDomain(forName: name)
        return UserDefaults(suiteName: name)
    }()

    // MARK: Entry point

    static func prepareIfNeeded() {
        guard isActive else { return }
        #if canImport(UIKit)
        UIView.setAnimationsEnabled(false)
        UIApplication.shared.isIdleTimerDisabled = true
        #endif
        seedDefaults()
        seedHistoryAndPlan()
        fakeHealth()
    }

    // MARK: Seed: routines

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

    private static func seedDefaults() {
        let defaults = AppDefaults.store
        let routines = [
            Routine(name: "Upper Push", exercises: upperPush, kind: .workout),
            Routine(name: "Leg Day", exercises: legDay, kind: .workout),
            Routine(name: "Friday MetCon", exercises: metCon, kind: .workout),
            Routine(name: "Tabata", exercises: tabata, kind: .timer),
        ]
        if let data = try? JSONEncoder().encode(routines) { defaults.set(data, forKey: "savedRoutines") }
        // The builder tabs open on something real rather than an empty row.
        if let data = try? JSONEncoder().encode(upperPush) { defaults.set(data, forKey: "savedExercises") }
        if let data = try? JSONEncoder().encode(tabata) { defaults.set(data, forKey: "savedTimers") }
        defaults.set(true, forKey: "keepScreenAwake")
    }

    // MARK: Seed: history and plan

    /// When the capture was launched. Every seeded date is relative to it, and every scene's
    /// engine starts at it, so "last time" lookups (which only consider earlier workouts) work.
    static let base = Date()

    private typealias SetSpec = (reps: Int?, weight: Double?)

    private static func completedWorkout(daysAgo: Double, name: String, duration: TimeInterval,
                                         exercises: [Exercise], sets: [[SetSpec]],
                                         planSession: PlanSessionRef? = nil, at date: Date? = nil) -> CompletedWorkout {
        let when = date ?? base.addingTimeInterval(-daysAgo * 86_400)
        var records: [SetRecord] = []
        for (index, exercise) in exercises.enumerated() where sets.indices.contains(index) {
            for (n, spec) in sets[index].enumerated() {
                records.append(SetRecord(exerciseID: exercise.id, exerciseIndex: index, exerciseName: exercise.name,
                                         round: n + 1, reps: spec.reps, weight: spec.weight, weightUnit: exercise.weightUnit,
                                         activeDuration: exercise.isTimeBased ? exercise.exerciseDuration : 40,
                                         skipped: false, completedAt: when))
            }
        }
        return CompletedWorkout(date: when, kind: .workout, routineName: name, duration: duration,
                                completedNaturally: true, records: records, planSession: planSession)
    }

    private static func seedHistoryAndPlan() {
        var workouts: [CompletedWorkout] = []
        let none: SetSpec = (nil, nil)

        // Upper Push, three weeks running. The latest Bench Press hits every rep at 135 lb, so the
        // "try 140 lb" hint shows on the Bench Press card.
        func upper(_ days: Double, bench: [SetSpec], press: [SetSpec], incline: [SetSpec], pushdown: [SetSpec]) -> CompletedWorkout {
            completedWorkout(daysAgo: days, name: "Upper Push", duration: 2_700, exercises: upperPush,
                             sets: [bench, press, incline, pushdown])
        }
        workouts.append(upper(21, bench: [(9, 125), (8, 125), (8, 125)], press: [(8, 80), (8, 80), (8, 80)],
                              incline: [(12, 45), (11, 45), (10, 45)], pushdown: [(15, 45), (14, 45), (12, 45)]))
        workouts.append(upper(14, bench: [(10, 130), (9, 130), (8, 130)], press: [(10, 80), (9, 80), (8, 80)],
                              incline: [(12, 50), (11, 50), (10, 50)], pushdown: [(15, 50), (13, 50), (12, 50)]))
        workouts.append(upper(7, bench: [(10, 135), (10, 135), (10, 135)], press: [(10, 85), (9, 85), (8, 85)],
                              incline: [(12, 50), (11, 50), (11, 50)], pushdown: [(15, 50), (14, 50), (12, 50)]))

        // Leg Day twice, deadlift topping out at 275 lb (the recap scene beats it with 295).
        func legs(_ days: Double, squat: [SetSpec], deadlift: [SetSpec]) -> CompletedWorkout {
            completedWorkout(daysAgo: days, name: "Leg Day", duration: 3_000, exercises: legDay,
                             sets: [squat, deadlift, [none, none, none], [none, none, none], [(15, 90), (15, 90), (15, 90)]])
        }
        workouts.append(legs(19, squat: [(8, 215), (8, 215), (7, 215), (6, 215)], deadlift: [(5, 265), (5, 265), (5, 265)]))
        workouts.append(legs(12, squat: [(8, 225), (7, 225), (6, 225), (6, 225)], deadlift: [(5, 275), (5, 275), (5, 275)]))

        // Friday MetCon: eight rounds before the 12:00 cap.
        let rounds: [SetSpec] = Array(repeating: (10, 40), count: 8)
        workouts.append(completedWorkout(daysAgo: 5, name: "Friday MetCon", duration: 720, exercises: metCon,
                                         sets: [rounds, Array(repeating: (15, nil), count: 8), Array(repeating: (15, 53), count: 8)]))

        // The active plan: Build Muscle, dumbbells, three days a week anchored on the launch day
        // (today, today + 2, today + 4, wrapping round the week), started 7 days ago. Sessions 0–2
        // fall 7, 5 and 3 days ago and are done and tagged; session 3 (Week 2 · Build, Full Body B)
        // falls today, so Up Next always says "Today".
        var options = PlanGenerator.Options()
        options.goal = .muscle
        options.equipment = .dumbbells
        let calendar = Calendar.current
        let today = calendar.component(.weekday, from: base)   // 1 = Sunday … 7 = Saturday
        options.weekdays = [0, 2, 4].map { (today - 1 + $0) % 7 + 1 }.sorted()
        options.startDate = calendar.date(byAdding: .day, value: -7, to: base) ?? base.addingTimeInterval(-7 * 86_400)
        let plan = PlanGenerator.make(options)

        let planWeights: [String: Double] = [
            "Goblet Squat": 50, "DB Bench Press": 45, "One-Arm DB Row": 50, "DB Romanian Deadlift": 50, "DB Shoulder Press": 35,
            "DB Split Squat": 30, "Incline DB Press": 45, "DB Pullover": 40, "DB Hip Thrust": 50, "DB Lateral Raise": 15,
        ]
        let sessions = plan.sessions()
        for index in 0..<3 where sessions.indices.contains(index) {
            let session = sessions[index]
            let template = plan.workouts[session.workoutIndex]
            // Incline DB Press and DB Pullover hit the top of the 8–12 range, so the next session
            // suggests a heavier pair; the rest stay inside the range.
            let sets: [[SetSpec]] = template.exercises.map { e in
                guard !e.isTimeBased else { return Array(repeating: none, count: e.sets) }
                let reps = (e.name == "Incline DB Press" || e.name == "DB Pullover") ? 12 : 10
                return Array(repeating: (reps, planWeights[e.name]), count: e.sets)
            }
            // Early evening on the day the session was planned for (always in the past: 7, 5 and 3 days ago).
            let finished = session.date.addingTimeInterval(18 * 3_600)
            workouts.append(completedWorkout(daysAgo: 0, name: "\(template.name) · Week \(session.week)", duration: 2_400,
                                             exercises: template.exercises, sets: sets,
                                             planSession: PlanSessionRef(planID: plan.id, index: session.index),
                                             at: finished))
        }

        // The store returns "last time" by walking backwards, so add oldest first.
        for workout in workouts.sorted(by: { $0.date < $1.date }) { WorkoutHistoryStore.shared.add(workout) }
        TrainingPlanStore.shared.save(plan)
    }

    // MARK: Fake Health

    private static func fakeHealth() {
        #if os(iOS) && canImport(HealthKit)
        let hk = HealthKitWorkoutManager.shared
        hk.heartRate = 142
        hk.activeCalories = 186
        hk.currentHRZoneIndex = 2
        hk.isWorkoutActive = true
        // So the Settings tab doesn't wear a "!" badge for a missing age.
        hk.age = 34
        #if canImport(WatchConnectivity)
        // The recap reads its zone breakdown from here (forwarded from the watch in real use).
        let bounds: [(Double?, Double?)] = [(95, 114), (114, 133), (133, 152), (152, 171), (171, nil)]
        let seconds: [TimeInterval] = [190, 400, 845, 330, 45]   // Z1 3:10, Z2 6:40, Z3 14:05, Z4 5:30, Z5 0:45
        WatchConnectivityManager.shared.completedZoneSummary = (0..<5).map {
            HRZoneRecapEntry(zoneIndex: $0, duration: seconds[$0], minBPM: bounds[$0].0, maxBPM: bounds[$0].1)
        }
        #endif
        #endif
    }

    // MARK: Scenes

    private static var controllers: [SessionKind: SessionController] = [:]

    /// The frozen session for `kind`, if the requested scene is a session scene of that kind.
    static func controller(for kind: SessionKind) -> SessionController? {
        guard isActive, let scene, scene.sessionKind == kind else { return nil }
        if let existing = controllers[kind] { return existing }
        let built = makeController(for: scene)
        controllers[kind] = built
        return built
    }

    /// Runs a fresh engine forward with explicit dates until it reaches `step` (or finishes):
    /// manual sets take `manualSeconds` each, timed phases run their full length. Returns the
    /// engine and the moment the current step began.
    private static func play(_ exercises: [Exercise], toStep step: Int, manualSeconds: TimeInterval = 40,
                             reps: (PlanStep) -> Int? = { _ in nil }) -> (engine: SessionEngine, clock: Date) {
        var engine = SessionEngine(exercises: exercises, now: base)
        var clock = base
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

    private static func makeController(for scene: ScreenshotScene) -> SessionController {
        let history = WorkoutHistoryStore.shared
        func controller(_ played: (engine: SessionEngine, clock: Date), elapsedInStep: TimeInterval = 0,
                        kind: SessionKind = .workout, name: String) -> SessionController {
            SessionController(frozenEngine: played.engine, now: played.clock.addingTimeInterval(elapsedInStep),
                              kind: kind, routineName: name, history: history)
        }

        switch scene {
        case .manualSet:
            // Bench Press, set 2 of 4: set 1 logged at 10 reps, 6 s into the next set.
            let played = play(upperPush, toStep: 2) { $0.round == 1 ? 10 : nil }
            return controller(played, elapsedInStep: 6, name: "Upper Push")

        case .restLog:
            // Bench is two sets here so that the next exercise (Overhead Press) differs from the
            // one just logged. 18 s into the 90 s rest leaves 1:12.
            var list = upperPush
            list[0].sets = 2
            let played = play(list, toStep: 3) { _ in 10 }
            return controller(played, elapsedInStep: 18, name: "Upper Push")

        case .superset, .overview:
            // Leg Day: round 2 of the superset, second move (Mountain Climber), 11 s into its 45 s.
            let played = play(legDay, toStep: 18)
            return controller(played, elapsedInStep: 11, name: "Leg Day")

        case .timedSuperset:
            // Thirteen sets at 19 s, then 11 s into the next: 258 s of the 720 s budget gone, 7:42 left.
            let played = play(metCon, toStep: 13, manualSeconds: 19)
            return controller(played, elapsedInStep: 11, name: "Friday MetCon")

        case .recap:
            // The whole of Leg Day, deadlift at 295 lb: heavier than anything in the history.
            var list = legDay
            list[1].weight = 295
            let played = play(list, toStep: .max)
            return controller(played, name: "Leg Day")

        case .timer:
            // Tabata, third break, 4 s in: 0:06 left.
            let played = play(tabata, toStep: 5)
            return controller(played, elapsedInStep: 4, kind: .timer, name: "Tabata")

        case .plan, .routines, .createPlan:
            // Not session scenes; `controller(for:)` never routes these here.
            return controller(play(upperPush, toStep: 0), name: "Upper Push")
        }
    }
}
#endif
