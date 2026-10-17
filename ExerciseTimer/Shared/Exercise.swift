import Foundation

enum WeightUnit: String, Codable, CaseIterable {
    case lbs
    case kg
}

/// Whether a Timed Superset's `groupTimeBudget` is re-armed every round (`perRound`, the original
/// behavior) or set once and shared across all of a chain's rounds (`wholeChain`, e.g. a 15-minute
/// AMRAP-style cap to perform 10 rounds of burpees + goblet squats).
enum TimeBudgetScope: String, Codable, CaseIterable {
    case perRound
    case wholeChain
}

struct Exercise: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String = ""
    var isTimeBased: Bool = true
    var sets: Int = 1
    var exerciseDuration: TimeInterval = 30
    var restDuration: TimeInterval = 10
    var targetReps: Int? = nil
    /// Upper bound of a rep range (e.g. 10 for "8–10 reps"). `targetReps` holds the lower bound.
    var targetRepsMax: Int? = nil
    var weight: Double? = nil
    var weightUnit: WeightUnit = .lbs
    /// Free-text guidance, e.g. "perform 4 warmup/ramp-up sets" or "switch with #1 if grip is compromised".
    var notes: String? = nil
    /// True when this exercise is linked into a superset with the previous exercise in the list.
    var isSupersetContinuation: Bool = false
    /// How many rounds a multi-exercise superset chain repeats. Only meaningful on the FIRST exercise
    /// of a chain (the one where `isSupersetContinuation == false` but the next exercise continues from it);
    /// ignored everywhere else. Decoupled from `sets`, which each chain member performs once per round.
    var chainRepeatCount: Int = 1
    /// "Timed Superset" mode: a shared time budget for a chain (e.g. 5 minutes to
    /// complete 8x Bench, 12x Pullovers, 15x Pushups), with any time left over counted as rest before
    /// the next round. Same scoping as `chainRepeatCount` — only meaningful on a chain's first exercise.
    /// `nil` means the chain uses each member's own `restDuration` between exercises, as usual.
    /// Whether the budget covers one round (`groupTimeBudgetScope == .perRound`) or all of
    /// `chainRepeatCount` rounds together (`.wholeChain`) is controlled by `groupTimeBudgetScope`.
    var groupTimeBudget: TimeInterval? = nil
    /// Scope of `groupTimeBudget`: re-armed every round, or shared once across the whole chain.
    /// Only meaningful when `groupTimeBudget != nil`.
    var groupTimeBudgetScope: TimeBudgetScope = .perRound

    enum CodingKeys: String, CodingKey {
        case id, name, isTimeBased, sets, exerciseDuration, restDuration, targetReps, targetRepsMax, weight, weightUnit, notes, isSupersetContinuation, chainRepeatCount, groupTimeBudget, groupTimeBudgetScope
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isTimeBased = try container.decode(Bool.self, forKey: .isTimeBased)
        sets = try container.decode(Int.self, forKey: .sets)
        exerciseDuration = try container.decode(TimeInterval.self, forKey: .exerciseDuration)
        restDuration = try container.decode(TimeInterval.self, forKey: .restDuration)
        targetReps = try container.decodeIfPresent(Int.self, forKey: .targetReps)
        targetRepsMax = try container.decodeIfPresent(Int.self, forKey: .targetRepsMax)
        weight = try container.decodeIfPresent(Double.self, forKey: .weight)
        weightUnit = try container.decodeIfPresent(WeightUnit.self, forKey: .weightUnit) ?? .lbs
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        isSupersetContinuation = try container.decodeIfPresent(Bool.self, forKey: .isSupersetContinuation) ?? false
        chainRepeatCount = try container.decodeIfPresent(Int.self, forKey: .chainRepeatCount) ?? 1
        groupTimeBudget = try container.decodeIfPresent(TimeInterval.self, forKey: .groupTimeBudget)
        groupTimeBudgetScope = try container.decodeIfPresent(TimeBudgetScope.self, forKey: .groupTimeBudgetScope) ?? .perRound
    }

    /// A compact "weight · reps" summary for use in "Up Next" labels.
    var quickSummary: String {
        var parts: [String] = []
        if let w = weight {
            let n = w.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(w))" : String(format: "%.1f", w)
            parts.append("\(n) \(weightUnit.rawValue)")
        }
        if !isTimeBased, let reps = targetReps {
            if let repsMax = targetRepsMax, repsMax != reps {
                parts.append("\(reps)–\(repsMax) reps")
            } else {
                parts.append("\(reps) reps")
            }
        }
        return parts.joined(separator: " · ")
    }
}

extension Array where Element == Exercise {
    /// The contiguous run of superset-linked exercises containing `index` (a lone exercise returns a single-element range).
    /// Used both by the builder (to lock rest across a group) and the workout engine
    /// (to run one set of every group member per round before resting).
    func supersetGroupRange(containing index: Int) -> ClosedRange<Int> {
        guard indices.contains(index) else { return index...index }
        var start = index
        while start > 0 && self[start].isSupersetContinuation {
            start -= 1
        }
        var end = index
        while end + 1 < count && self[end + 1].isSupersetContinuation {
            end += 1
        }
        return start...end
    }

    /// How many rounds the group containing `groupRange` repeats: a lone exercise repeats for its own
    /// `sets`, while a multi-exercise chain repeats for the first exercise's `chainRepeatCount`.
    func roundCount(for groupRange: ClosedRange<Int>) -> Int {
        guard indices.contains(groupRange.lowerBound), indices.contains(groupRange.upperBound) else { return 1 }
        if groupRange.count > 1 {
            return self[groupRange.lowerBound].chainRepeatCount
        } else {
            return self[groupRange.upperBound].sets
        }
    }

    /// Enforces the superset invariants after any edit to an exercise list:
    /// - A superset marker on the first exercise means "linked to nothing" — not valid.
    /// Rest durations on chain members are intentionally left alone — each member's own
    /// `restDuration` is honored between linked exercises (0 means continue straight into the next).
    mutating func normalizeSupersets() {
        guard indices.contains(0) else { return }
        if self[0].isSupersetContinuation {
            self[0].isSupersetContinuation = false
        }
    }

    /// Toggles whether the exercise at `index` is linked to the previous one. Newly linking starts
    /// the previous exercise at no rest (continue straight into this one) — the user can then add
    /// a rest between them explicitly.
    mutating func toggleSupersetLink(at index: Int) {
        guard indices.contains(index), index > 0 else { return }
        self[index].isSupersetContinuation.toggle()
        if self[index].isSupersetContinuation {
            self[index - 1].restDuration = 0
        }
        normalizeSupersets()
    }
}
