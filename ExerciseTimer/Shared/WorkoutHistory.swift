import Foundation

// MARK: - Workout history & progression
//
// Inspired by Fitness+ Gym Strength's "log reps and weight, next time adapts": every finished
// session's set log is kept on-device, so the app can show what you did last time and suggest
// the next step using simple double progression — no account, no network, no AI required.

struct CompletedWorkout: Codable, Equatable, Identifiable {
    var id = UUID()
    var date: Date
    var kind: SessionKind
    var routineName: String?
    var duration: TimeInterval
    var completedNaturally: Bool
    var records: [SetRecord]
}

/// What we know about an exercise from the most recent session that included it.
struct LastPerformance: Equatable {
    var date: Date
    var sets: [SetRecord]

    var summary: String {
        let done = sets.filter { !$0.skipped }
        guard let first = done.first else { return "" }
        let unit = first.weightUnit
        let allReps = done.compactMap(\.reps)
        let weights = Set(done.compactMap(\.weight))
        var parts: [String] = []
        if !allReps.isEmpty {
            parts.append(Set(allReps).count == 1 ? "\(done.count)×\(allReps[0])" : allReps.map(String.init).joined(separator: ", "))
        } else {
            parts.append("\(done.count) set\(done.count == 1 ? "" : "s")")
        }
        if weights.count == 1, let w = weights.first { parts.append("@ " + SessionFormat.weight(w, unit: unit)) }
        else if let maxW = weights.max() { parts.append("up to " + SessionFormat.weight(maxW, unit: unit)) }
        return parts.joined(separator: " ")
    }
}

enum ProgressionHint: Equatable {
    /// Every set hit the top of the rep range last time: go heavier.
    case increaseWeight(to: Double, unit: WeightUnit)
    /// Bodyweight / no weight: every set hit the top, so aim for more reps.
    case increaseReps(to: Int)
    /// Not every set reached the bottom of the range: stay here.
    case repeatWeight

    var message: String {
        switch self {
        case .increaseWeight(let w, let unit): return "You hit every rep last time — try \(SessionFormat.weight(w, unit: unit))"
        case .increaseReps(let reps): return "You hit every rep last time — aim for \(reps)"
        case .repeatWeight: return "Same weight as last time — match or beat your reps"
        }
    }
}

enum Progression {
    static func increment(for unit: WeightUnit, weight: Double) -> Double {
        switch unit {
        case .lbs: return weight < 20 ? 2.5 : 5
        case .kg: return weight < 10 ? 1 : 2.5
        }
    }

    /// Double progression against the exercise's current targets.
    static func hint(for exercise: Exercise, last: LastPerformance?) -> ProgressionHint? {
        guard !exercise.isTimeBased, let last, let target = exercise.targetReps else { return nil }
        let done = last.sets.filter { !$0.skipped }
        guard !done.isEmpty, done.allSatisfy({ $0.reps != nil }) else { return nil }
        let top = exercise.targetRepsMax ?? target
        let reps = done.compactMap(\.reps)
        let lastWeight = done.compactMap(\.weight).max()
        let currentWeight = exercise.weight

        // If you've already changed the weight since, don't second-guess it.
        if let lastWeight, let currentWeight, abs(lastWeight - currentWeight) > 0.01 { return nil }

        if reps.allSatisfy({ $0 >= top }) {
            if let w = currentWeight ?? lastWeight, w > 0 {
                return .increaseWeight(to: w + increment(for: exercise.weightUnit, weight: w), unit: exercise.weightUnit)
            }
            return .increaseReps(to: top + 1)
        }
        if reps.contains(where: { $0 < target }) { return .repeatWeight }
        return nil
    }

    /// Epley estimated one-rep max.
    static func estimatedOneRepMax(weight: Double, reps: Int) -> Double {
        guard reps > 0, weight > 0 else { return 0 }
        return reps == 1 ? weight : weight * (1 + Double(reps) / 30)
    }
}

/// A personal best spotted in a just-finished workout.
struct Milestone: Equatable, Identifiable {
    enum Kind: Equatable { case heaviestWeight, mostReps, firstTime }
    var id: String { "\(exerciseName)-\(kind)" }
    var exerciseName: String
    var kind: Kind
    var detail: String
}

enum Milestones {
    static func find(in workout: CompletedWorkout, history: [CompletedWorkout]) -> [Milestone] {
        guard workout.kind == .workout else { return [] }
        var results: [Milestone] = []
        let earlier = history.filter { $0.id != workout.id && $0.date < workout.date }.flatMap(\.records).filter { !$0.skipped }
        let byName = Dictionary(grouping: workout.records.filter { !$0.skipped && !$0.exerciseName.isEmpty }) { key($0.exerciseName) }
        for (name, sets) in byName.sorted(by: { $0.key < $1.key }) {
            let displayName = sets[0].exerciseName
            let previous = earlier.filter { key($0.exerciseName) == name }
            if previous.isEmpty {
                if !history.isEmpty { results.append(Milestone(exerciseName: displayName, kind: .firstTime, detail: "First time logged")) }
                continue
            }
            if let best = sets.compactMap(\.weight).max(), let prevBest = previous.compactMap(\.weight).max(), best > prevBest {
                results.append(Milestone(exerciseName: displayName, kind: .heaviestWeight,
                                         detail: "Heaviest yet: \(SessionFormat.weight(best, unit: sets[0].weightUnit))"))
            } else if let bestReps = sets.compactMap(\.reps).max(), let prevReps = previous.compactMap(\.reps).max(), bestReps > prevReps {
                results.append(Milestone(exerciseName: displayName, kind: .mostReps, detail: "Most reps yet: \(bestReps)"))
            }
        }
        return results
    }

    static func key(_ name: String) -> String { name.trimmingCharacters(in: .whitespaces).lowercased() }
}

/// On-device JSON store. Kept deliberately simple; capped so it never grows unbounded.
final class WorkoutHistoryStore {
    static let shared = WorkoutHistoryStore()
    private static let maxWorkouts = 500

    private let url: URL
    private(set) var workouts: [CompletedWorkout] = []

    init(directory: URL? = nil) {
        let base = directory ?? (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                                 ?? FileManager.default.temporaryDirectory)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("WorkoutHistory.json")
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([CompletedWorkout].self, from: data) {
            workouts = decoded
        }
    }

    func add(_ workout: CompletedWorkout) {
        // Nothing was actually done — don't let an accidental start/cancel clutter history.
        guard workout.records.contains(where: { !$0.skipped }) else { return }
        workouts.append(workout)
        if workouts.count > Self.maxWorkouts { workouts.removeFirst(workouts.count - Self.maxWorkouts) }
        if let data = try? JSONEncoder().encode(workouts) { try? data.write(to: url, options: .atomic) }
    }

    func deleteAll() {
        workouts = []
        try? FileManager.default.removeItem(at: url)
    }

    /// Most recent session containing this exercise — matched by id first (same routine), then by name.
    func lastPerformance(of exercise: Exercise, before date: Date = .distantFuture) -> LastPerformance? {
        let nameKey = Milestones.key(exercise.name)
        for workout in workouts.reversed() where workout.date < date {
            var sets = workout.records.filter { $0.exerciseID == exercise.id }
            if sets.isEmpty, !nameKey.isEmpty {
                sets = workout.records.filter { Milestones.key($0.exerciseName) == nameKey }
            }
            if sets.contains(where: { !$0.skipped }) {
                return LastPerformance(date: workout.date, sets: sets)
            }
        }
        return nil
    }
}
