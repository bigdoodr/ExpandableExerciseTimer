import Foundation

/// Commands sent from iOS to watchOS to control workout display
enum WorkoutCommand: Codable, Equatable {
    case start(exercises: [Exercise], healthKitEnabled: Bool, activityType: String?)
    case updatePhase(exerciseIndex: Int, set: Int, isResting: Bool, isPaused: Bool,
                     phaseEndDate: Date?, isCompleted: Bool)
    case pause
    case resume
    case stop
    case healthData(heartRate: Double, activeCalories: Double)
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
