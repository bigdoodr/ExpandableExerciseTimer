import Foundation

/// Commands sent between iOS and watchOS to control workout state.
/// iPhone is always the timer authority; watch sends action commands back.
enum WorkoutCommand: Codable, Equatable {
    /// `workoutID` identifies this specific workout session. `.zoneSummary` is delivered via
    /// `transferUserInfo` (queued, best-effort) so it can arrive after a *later* workout has
    /// already started — the receiver compares this id against the current workout's id and
    /// discards anything that doesn't match, rather than displaying stale zone data.
    case start(exercises: [Exercise], healthKitEnabled: Bool, activityType: String?, workoutID: UUID)
    case updatePhase(exerciseIndex: Int, set: Int, isResting: Bool, isPaused: Bool,
                     phaseEndDate: Date?, isCompleted: Bool)
    case pause
    case resume
    case stop
    case healthData(heartRate: Double, activeCalories: Double, hrZoneIndex: Int?)
    /// Sent from watch to iPhone when user completes a rep-based set
    case repsComplete
    /// Sent from watch to iPhone to skip the current exercise or rest phase, mirroring the
    /// iPhone's own Skip button. iPhone remains the timer authority — it advances the phase
    /// and sends the resulting state back to the watch, same as `.repsComplete`.
    case skipPhase
    /// Sent from iPhone to watch to wake the watch app; watch calls session.prepare() so it surfaces on wrist raise
    case wake
    /// Sent from whichever device recorded the HealthKit workout session to the other device once the
    /// workout ends, so both recaps can show the same time-in-zone breakdown. Only the device that owns
    /// the session can read `HKWorkout.zoneGroupsByType`, so the data has to be forwarded as plain values.
    /// `workoutID` must match the `.start` that began the session it was computed from.
    case zoneSummary(zones: [HRZoneRecapEntry], workoutID: UUID)
}

/// A single HR zone's time-in-zone, computed by the device that owns the HealthKit workout session and
/// forwarded to the other device for recap display.
struct HRZoneRecapEntry: Codable, Equatable {
    let zoneIndex: Int
    let duration: TimeInterval
    let minBPM: Double?
    let maxBPM: Double?
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
