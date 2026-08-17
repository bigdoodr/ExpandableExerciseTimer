import Foundation

enum WeightUnit: String, Codable, CaseIterable {
    case lbs
    case kg
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

    enum CodingKeys: String, CodingKey {
        case id, name, isTimeBased, sets, exerciseDuration, restDuration, targetReps, targetRepsMax, weight, weightUnit, notes, isSupersetContinuation, chainRepeatCount
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
}
