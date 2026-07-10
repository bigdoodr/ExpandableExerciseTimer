import Foundation

/// Commands sent between iOS and watchOS to control workout state.
/// iPhone is always the timer authority; watch sends action commands back.
enum WorkoutCommand: Codable, Equatable {
    case start(exercises: [Exercise], healthKitEnabled: Bool, activityType: String?)
    case updatePhase(exerciseIndex: Int, set: Int, isResting: Bool, isPaused: Bool,
                     phaseEndDate: Date?, isCompleted: Bool)
    case pause
    case resume
    case stop
    case healthData(heartRate: Double, activeCalories: Double)
    /// Sent from watch to iPhone when user completes a rep-based set
    case repsComplete
    /// Sent from iPhone to watch to wake the watch app; watch calls session.prepare() so it surfaces on wrist raise
    case wake
}

/// Keys for WatchConnectivity message/context dictionaries
enum WCContextKey {
    static let exercises = "exercises"
    static let workoutCommand = "workoutCommand"
    static let healthKitEnabled = "healthKitEnabled"
    static let activityType = "activityType"
}

/// Supported HealthKit workout activity types for the picker
enum WorkoutActivityOption: String, CaseIterable, Identifiable {
    case traditionalStrengthTraining = "Traditional Strength Training"
    case highIntensityIntervalTraining = "High Intensity Interval Training"
    case yoga = "Yoga"
    case flexibility = "Flexibility"
    case coreTraining = "Core Training"
    case functionalStrengthTraining = "Functional Strength Training"
    case mixedCardio = "Mixed Cardio"
    case other = "Other"
    
    var id: String { rawValue }
}

/// A named, saved collection of exercises
struct Routine: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var exercises: [Exercise]
}

/// Heart rate zone computed from BPM relative to estimated max heart rate
struct HRZone {
    let number: Int
    let label: String
    /// Primary fuel source burned at this intensity
    let fuelType: String

    static func zone(for heartRate: Double, maxHR: Double) -> HRZone? {
        guard maxHR > 0, heartRate > 0 else { return nil }
        let pct = heartRate / maxHR
        switch pct {
        case ..<0.50:  return HRZone(number: 1, label: "Recovery",  fuelType: "Fat")
        case 0.50..<0.60: return HRZone(number: 2, label: "Fat Burn",  fuelType: "Fat")
        case 0.60..<0.70: return HRZone(number: 3, label: "Cardio",    fuelType: "Mixed")
        case 0.70..<0.85: return HRZone(number: 4, label: "Threshold", fuelType: "Carb")
        default:          return HRZone(number: 5, label: "Peak",      fuelType: "Carb")
        }
    }
}
