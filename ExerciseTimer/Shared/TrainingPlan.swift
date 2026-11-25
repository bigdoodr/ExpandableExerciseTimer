import Foundation

// MARK: - 4-week training plans
//
// Inspired by Fitness+ Gym Strength: pick a goal, the days you train and the equipment you have,
// and get a progressive four-week plan. Each session adapts to what you actually logged last
// time (via `Progression.hint`), and the weeks follow a simple wave:
//   Week 1  Base       — the plan as written
//   Week 2  Build      — aim for the top of each rep range
//   Week 3  Overload   — one extra set (or round) per exercise
//   Week 4  Deload     — one fewer set, ~10% lighter, so you recover before the next block
// Everything is computed on-device from the plan + workout history; nothing is stored per session.

/// Ties a finished workout back to the plan session it fulfilled.
struct PlanSessionRef: Codable, Hashable {
    var planID: UUID
    var index: Int
}

enum TrainingGoal: String, Codable, CaseIterable, Identifiable {
    case strength, muscle, general
    var id: String { rawValue }
    var title: String {
        switch self {
        case .strength: return "Get Stronger"
        case .muscle: return "Build Muscle"
        case .general: return "General Fitness"
        }
    }
    var subtitle: String {
        switch self {
        case .strength: return "Heavier weights, 5 reps, longer rests"
        case .muscle: return "Moderate weights, 8–12 reps"
        case .general: return "Lighter weights, 12–15 reps, short rests"
        }
    }
    var sets: Int { self == .strength ? 5 : 3 }
    var reps: (Int, Int?) {
        switch self {
        case .strength: return (5, nil)
        case .muscle: return (8, 12)
        case .general: return (12, 15)
        }
    }
    var rest: TimeInterval {
        switch self {
        case .strength: return 150
        case .muscle: return 90
        case .general: return 60
        }
    }
}

enum EquipmentLevel: String, Codable, CaseIterable, Identifiable {
    case bodyweight, dumbbells, fullGym
    var id: String { rawValue }
    var title: String {
        switch self {
        case .bodyweight: return "Bodyweight"
        case .dumbbells: return "Dumbbells"
        case .fullGym: return "Full Gym"
        }
    }
}

enum SessionLength: String, Codable, CaseIterable, Identifiable {
    case short, long
    var id: String { rawValue }
    var exerciseCount: Int { self == .short ? 5 : 7 }
    var title: String { self == .short ? "5 exercises (~30 min)" : "7 exercises (~50 min)" }
}

enum WeekPhase: Int, Codable, CaseIterable {
    case base = 1, build, overload, deload

    static func forWeek(_ week: Int) -> WeekPhase { WeekPhase(rawValue: ((week - 1) % 4) + 1) ?? .base }

    var title: String {
        switch self {
        case .base: return "Base"
        case .build: return "Build"
        case .overload: return "Overload"
        case .deload: return "Deload"
        }
    }
    var summary: String {
        switch self {
        case .base: return "Learn the movements and find working weights. Log every set."
        case .build: return "Same exercises — push toward the top of each rep range."
        case .overload: return "One extra set or round on every exercise. The hardest week."
        case .deload: return "One fewer set and about 10% lighter, so you recover and come back stronger."
        }
    }
}

struct PlanWorkout: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var exercises: [Exercise]
}

struct PlannedSession: Identifiable, Equatable {
    var index: Int
    var week: Int
    var date: Date
    var workoutIndex: Int
    var id: Int { index }
}

struct TrainingPlan: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var startDate: Date
    /// Calendar weekdays (1 = Sunday … 7 = Saturday), sorted.
    var weekdays: [Int]
    var weeks: Int = 4
    /// Rotated in order across sessions (A, B, A / B, A, B …).
    var workouts: [PlanWorkout]
    var goal: TrainingGoal?
    /// Attribution for plans based on a published program.
    var source: String?
    var sourceURL: String?
    /// Programs that already prescribe their own progression (e.g. a bodyweight circuit) can
    /// opt out of the week-by-week set changes; history-based weight hints still apply.
    var usesWeeklyWave: Bool = true

    var sessionsPerWeek: Int { weekdays.count }
    var totalSessions: Int { weeks * weekdays.count }

    /// Concrete dates for every session, starting from the first chosen weekday on/after `startDate`.
    func sessions(calendar: Calendar = .current) -> [PlannedSession] {
        let days = weekdays.sorted()
        guard !days.isEmpty, !workouts.isEmpty else { return [] }
        let start = calendar.startOfDay(for: startDate)
        var result: [PlannedSession] = []
        var date = start
        var guardDays = 0
        while result.count < totalSessions && guardDays < 400 {
            let weekday = calendar.component(.weekday, from: date)
            if days.contains(weekday) {
                let index = result.count
                result.append(PlannedSession(index: index, week: index / days.count + 1, date: date,
                                             workoutIndex: index % workouts.count))
            }
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86_400)
            guardDays += 1
        }
        return result
    }

    func completedIndices(in history: [CompletedWorkout]) -> Set<Int> {
        Set(history.compactMap { $0.planSession?.planID == id ? $0.planSession?.index : nil })
    }

    /// The first session not yet done (sessions can be done late or early; dates are a guide).
    func nextSession(history: [CompletedWorkout], calendar: Calendar = .current) -> PlannedSession? {
        let done = completedIndices(in: history)
        return sessions(calendar: calendar).first { !done.contains($0.index) }
    }

    func isComplete(history: [CompletedWorkout]) -> Bool {
        completedIndices(in: history).count >= totalSessions
    }

    /// The exercises to run for `session`: the workout template, adjusted for the week's phase
    /// and for what was logged last time.
    func exercises(for session: PlannedSession, lastPerformance: (Exercise) -> LastPerformance?) -> [Exercise] {
        guard workouts.indices.contains(session.workoutIndex) else { return [] }
        let phase = WeekPhase.forWeek(session.week)
        var exercises = workouts[session.workoutIndex].exercises
        for i in exercises.indices {
            var e = exercises[i]
            // 1. Carry weight forward and apply double progression from history.
            if !e.isTimeBased, phase != .deload {
                let last = lastPerformance(e)
                if e.weight == nil, let lastWeight = last?.sets.filter({ !$0.skipped }).compactMap(\.weight).max(), lastWeight > 0 {
                    e.weight = lastWeight
                    e.weightUnit = last?.sets.first?.weightUnit ?? e.weightUnit
                }
                let hint = exercises.isInTimedChain(i) ? nil : Progression.hint(for: e, last: last)
                switch hint {
                case .increaseWeight(let to, let unit)?: e.weight = to; e.weightUnit = unit
                case .increaseReps(let to)?:
                    if let max = e.targetRepsMax { e.targetRepsMax = Swift.max(max, to) } else { e.targetReps = to }
                default: break
                }
            }
            // 2. Weekly wave.
            if usesWeeklyWave {
                let isChainHead = i + 1 < exercises.count && exercises[i + 1].isSupersetContinuation && !e.isSupersetContinuation
                switch phase {
                case .base: break
                case .build:
                    if !e.isTimeBased, let max = e.targetRepsMax { e.targetReps = max }
                case .overload:
                    if isChainHead { e.chainRepeatCount += 1 } else if !e.isSupersetContinuation { e.sets += 1 }
                case .deload:
                    if isChainHead { e.chainRepeatCount = Swift.max(1, e.chainRepeatCount - 1) }
                    else if !e.isSupersetContinuation { e.sets = Swift.max(1, e.sets - 1) }
                    if let w = e.weight, w > 0 {
                        let step = Progression.increment(for: e.weightUnit, weight: w)
                        e.weight = Swift.max(step, ((w * 0.9) / step).rounded() * step)
                    }
                }
            }
            exercises[i] = e
        }
        return exercises
    }

    /// A short, plain-language note for a session — what changed and why (the "Training Note").
    func note(for session: PlannedSession, lastPerformance: (Exercise) -> LastPerformance?) -> [String] {
        let phase = WeekPhase.forWeek(session.week)
        var lines = ["Week \(session.week) · \(phase.title): \(phase.summary)"]
        guard workouts.indices.contains(session.workoutIndex), phase != .deload else { return lines }
        let template = workouts[session.workoutIndex].exercises
        for (i, e) in template.enumerated() where !e.isTimeBased {
            switch Progression.hint(for: template, at: i, last: lastPerformance(e)) {
            case .increaseWeight(let to, let unit)?:
                lines.append("\(e.name): go up to \(SessionFormat.weight(to, unit: unit)) — you hit every rep last time.")
            case .increaseReps(let to)?:
                lines.append("\(e.name): aim for \(to) reps.")
            default: break
            }
        }
        return lines
    }
}

// MARK: - Generator

enum PlanGenerator {
    struct Options: Equatable {
        var goal: TrainingGoal = .muscle
        var equipment: EquipmentLevel = .dumbbells
        var weekdays: [Int] = [2, 4, 6]   // Mon / Wed / Fri
        var length: SessionLength = .short
        var startDate = Date()
    }

    /// Split chosen by days per week: 2–3 full body (A/B), 4 upper/lower, 5+ push/pull/legs.
    static func make(_ o: Options) -> TrainingPlan {
        let days = o.weekdays.sorted()
        let templates: [(String, [Move])]
        switch days.count {
        case ...3: templates = [("Full Body A", Library.fullBodyA(o.equipment)), ("Full Body B", Library.fullBodyB(o.equipment))]
        case 4: templates = [("Upper", Library.upper(o.equipment)), ("Lower", Library.lower(o.equipment))]
        default: templates = [("Push", Library.push(o.equipment)), ("Pull", Library.pull(o.equipment)), ("Legs", Library.legs(o.equipment))]
        }
        let workouts = templates.map { name, moves in
            PlanWorkout(name: name, exercises: moves.prefix(o.length.exerciseCount).enumerated().map { i, move in
                move.exercise(goal: o.goal, isMainLift: i < 3)
            })
        }
        let split = days.count <= 3 ? "Full Body" : (days.count == 4 ? "Upper/Lower" : "Push/Pull/Legs")
        return TrainingPlan(name: "\(o.goal.title) · \(split)", startDate: o.startDate, weekdays: days,
                            workouts: workouts, goal: o.goal)
    }

    /// A plan built from routines you already have (saved or built-in), rotated in order.
    static func make(from routines: [Routine], weekdays: [Int], startDate: Date, name: String? = nil) -> TrainingPlan {
        TrainingPlan(name: name ?? (routines.count == 1 ? routines[0].name : routines.map(\.name).joined(separator: " / ")),
                     startDate: startDate, weekdays: weekdays.sorted(),
                     workouts: routines.map { PlanWorkout(name: $0.name, exercises: $0.exercises) })
    }

    /// One movement in the library. `hold` makes it a timed exercise (planks etc.).
    struct Move {
        var name: String
        var hold: TimeInterval? = nil
        var perSide = false

        /// Strength plans run 5×5 on the first three (main) lifts and 3×8–10 on accessories.
        func exercise(goal: TrainingGoal, isMainLift: Bool) -> Exercise {
            var e = Exercise()
            e.name = name
            let isAccessory = goal == .strength && !isMainLift
            e.sets = (goal == .strength && isMainLift && hold == nil) ? goal.sets : 3
            e.restDuration = hold != nil ? 45 : (isAccessory ? 90 : goal.rest)
            if let hold {
                e.isTimeBased = true
                e.exerciseDuration = hold
            } else {
                e.isTimeBased = false
                let (low, high) = isAccessory ? (8, Int?(10)) : goal.reps
                e.targetReps = low
                e.targetRepsMax = high
            }
            if perSide { e.notes = "Each side." }
            return e
        }
    }

    /// Generic movement patterns per equipment level, ordered by priority (compound first).
    enum Library {
        static func fullBodyA(_ eq: EquipmentLevel) -> [Move] {
            switch eq {
            case .bodyweight: return [Move(name: "Bodyweight Squat"), Move(name: "Push-Up"), Move(name: "Inverted Row"), Move(name: "Glute Bridge"), Move(name: "Pike Push-Up"), Move(name: "Reverse Lunge", perSide: true), Move(name: "Plank", hold: 45)]
            case .dumbbells: return [Move(name: "Goblet Squat"), Move(name: "DB Bench Press"), Move(name: "One-Arm DB Row", perSide: true), Move(name: "DB Romanian Deadlift"), Move(name: "DB Shoulder Press"), Move(name: "DB Reverse Lunge", perSide: true), Move(name: "Plank", hold: 45)]
            case .fullGym: return [Move(name: "Barbell Back Squat"), Move(name: "Barbell Bench Press"), Move(name: "Barbell Row"), Move(name: "Romanian Deadlift"), Move(name: "Overhead Press"), Move(name: "Lat Pulldown"), Move(name: "Pallof Press", perSide: true)]
            }
        }
        static func fullBodyB(_ eq: EquipmentLevel) -> [Move] {
            switch eq {
            case .bodyweight: return [Move(name: "Split Squat", perSide: true), Move(name: "Chin-Up"), Move(name: "Chair Dip"), Move(name: "Single-Leg Hip Thrust", perSide: true), Move(name: "Decline Push-Up"), Move(name: "Step-Up", perSide: true), Move(name: "Side Plank", hold: 30, perSide: true)]
            case .dumbbells: return [Move(name: "DB Split Squat", perSide: true), Move(name: "Incline DB Press"), Move(name: "DB Pullover"), Move(name: "DB Hip Thrust"), Move(name: "DB Lateral Raise"), Move(name: "DB Step-Up", perSide: true), Move(name: "Dead Bug", hold: 40)]
            case .fullGym: return [Move(name: "Deadlift"), Move(name: "Incline DB Press"), Move(name: "Pull-Up"), Move(name: "Leg Press"), Move(name: "Seated Cable Row"), Move(name: "Cable Lateral Raise", perSide: true), Move(name: "Hanging Knee Raise")]
            }
        }
        static func upper(_ eq: EquipmentLevel) -> [Move] {
            switch eq {
            case .bodyweight: return [Move(name: "Push-Up"), Move(name: "Inverted Row"), Move(name: "Pike Push-Up"), Move(name: "Chin-Up"), Move(name: "Chair Dip"), Move(name: "Plank Shoulder Tap"), Move(name: "Hollow Hold", hold: 30)]
            case .dumbbells: return [Move(name: "DB Bench Press"), Move(name: "One-Arm DB Row", perSide: true), Move(name: "DB Shoulder Press"), Move(name: "DB Pullover"), Move(name: "DB Lateral Raise"), Move(name: "DB Curl"), Move(name: "DB Overhead Triceps Extension")]
            case .fullGym: return [Move(name: "Barbell Bench Press"), Move(name: "Barbell Row"), Move(name: "Overhead Press"), Move(name: "Pull-Up"), Move(name: "Incline DB Press"), Move(name: "Face Pull"), Move(name: "Cable Curl")]
            }
        }
        static func lower(_ eq: EquipmentLevel) -> [Move] {
            switch eq {
            case .bodyweight: return [Move(name: "Bodyweight Squat"), Move(name: "Single-Leg Glute Bridge", perSide: true), Move(name: "Reverse Lunge", perSide: true), Move(name: "Wall Sit", hold: 45), Move(name: "Step-Up", perSide: true), Move(name: "Calf Raise"), Move(name: "Side Plank", hold: 30, perSide: true)]
            case .dumbbells: return [Move(name: "Goblet Squat"), Move(name: "DB Romanian Deadlift"), Move(name: "DB Split Squat", perSide: true), Move(name: "DB Hip Thrust"), Move(name: "DB Step-Up", perSide: true), Move(name: "DB Calf Raise"), Move(name: "Dead Bug", hold: 40)]
            case .fullGym: return [Move(name: "Barbell Back Squat"), Move(name: "Romanian Deadlift"), Move(name: "Leg Press"), Move(name: "Walking Lunge", perSide: true), Move(name: "Leg Curl"), Move(name: "Standing Calf Raise"), Move(name: "Hanging Knee Raise")]
            }
        }
        static func push(_ eq: EquipmentLevel) -> [Move] {
            switch eq {
            case .bodyweight: return [Move(name: "Push-Up"), Move(name: "Pike Push-Up"), Move(name: "Chair Dip"), Move(name: "Decline Push-Up"), Move(name: "Diamond Push-Up"), Move(name: "Plank Shoulder Tap"), Move(name: "Plank", hold: 45)]
            case .dumbbells: return [Move(name: "DB Bench Press"), Move(name: "DB Shoulder Press"), Move(name: "Incline DB Press"), Move(name: "DB Lateral Raise"), Move(name: "DB Floor Fly"), Move(name: "DB Overhead Triceps Extension"), Move(name: "DB Skull Crusher")]
            case .fullGym: return [Move(name: "Barbell Bench Press"), Move(name: "Overhead Press"), Move(name: "Incline DB Press"), Move(name: "Cable Lateral Raise", perSide: true), Move(name: "Cable Crossover"), Move(name: "Triceps Pushdown"), Move(name: "Dip")]
            }
        }
        static func pull(_ eq: EquipmentLevel) -> [Move] {
            switch eq {
            case .bodyweight: return [Move(name: "Chin-Up"), Move(name: "Inverted Row"), Move(name: "Doorframe Row", perSide: true), Move(name: "Prone Y-T-W Raise"), Move(name: "Superman Hold", hold: 30), Move(name: "Towel Curl"), Move(name: "Hollow Hold", hold: 30)]
            case .dumbbells: return [Move(name: "One-Arm DB Row", perSide: true), Move(name: "DB Pullover"), Move(name: "Chest-Supported DB Row"), Move(name: "DB Rear Delt Fly"), Move(name: "DB Shrug"), Move(name: "DB Hammer Curl"), Move(name: "DB Curl")]
            case .fullGym: return [Move(name: "Deadlift"), Move(name: "Pull-Up"), Move(name: "Barbell Row"), Move(name: "Lat Pulldown"), Move(name: "Face Pull"), Move(name: "Barbell Curl"), Move(name: "Hammer Curl")]
            }
        }
        static func legs(_ eq: EquipmentLevel) -> [Move] { lower(eq) }
    }
}

// MARK: - Store

final class TrainingPlanStore {
    static let shared = TrainingPlanStore()
    private let url: URL
    private(set) var plan: TrainingPlan?

    init(directory: URL? = nil) {
        let base = directory ?? (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                                 ?? FileManager.default.temporaryDirectory)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("TrainingPlan.json")
        if let data = try? Data(contentsOf: url) {
            plan = try? JSONDecoder().decode(TrainingPlan.self, from: data)
        }
    }

    func save(_ plan: TrainingPlan?) {
        self.plan = plan
        if let plan, let data = try? JSONEncoder().encode(plan) {
            try? data.write(to: url, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
