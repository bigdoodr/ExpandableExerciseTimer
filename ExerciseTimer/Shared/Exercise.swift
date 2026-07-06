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
    var weight: Double? = nil
    var weightUnit: WeightUnit = .lbs

    enum CodingKeys: String, CodingKey {
        case id, name, isTimeBased, sets, exerciseDuration, restDuration, targetReps, weight, weightUnit
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
        weight = try container.decodeIfPresent(Double.self, forKey: .weight)
        weightUnit = try container.decodeIfPresent(WeightUnit.self, forKey: .weightUnit) ?? .lbs
    }
}
