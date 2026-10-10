import Foundation

/// Distinguishes a HealthKit-tracked exercise workout (weight, target reps, Health recording)
/// from a plain Timers session (no HealthKit, no weight/reps prompts). Drives wording across
/// the builder, the active session, the recap, and both the phone and watch UIs.
enum SessionKind: String, Codable {
    case workout
    case timer
}

extension SessionKind {
    var tabTitle: String { self == .workout ? "Exercises" : "Timers" }
    var tabIcon: String { self == .workout ? "figure.strengthtraining.traditional" : "timer" }

    var itemName: String { self == .workout ? "Exercise" : "Interval" }
    var itemNamePlural: String { self == .workout ? "Exercises" : "Intervals" }
    var newItemPlaceholder: String { self == .workout ? "New Exercise" : "New Interval" }
    var itemNameFieldLabel: String { self == .workout ? "Exercise Name" : "Interval Name" }
    var itemTypeFieldLabel: String { self == .workout ? "Exercise Type" : "Interval Type" }
    var addItemLabel: String { self == .workout ? "Add Exercise" : "Add Interval" }

    /// Label for the manual-advance exercise type: "Rep-Based" for workouts, "Prompt-Based" for timers.
    var manualTypeLabel: String { self == .workout ? "Rep-Based" : "Prompt-Based" }
    /// Button tapped to advance a manual-advance phase.
    var manualAdvanceButtonLabel: String { self == .workout ? "Reps Complete" : "Ready to Proceed" }
    var manualPhaseLabel: String { self == .workout ? "REP-BASED" : "PROMPT-BASED" }
    var activePhaseLabel: String { self == .workout ? "EXERCISE" : "INTERVAL" }
    var restPhaseLabel: String { self == .workout ? "REST" : "BREAK" }

    var setUnitSingular: String { self == .workout ? "Set" : "Cycle" }
    var numberOfSetsLabel: String { self == .workout ? "Number of Sets" : "Number of Cycles" }
    var setsAddedToastLabel: String { self == .workout ? "Set added" : "Cycle added" }

    var restFieldLabel: String { self == .workout ? "Rest Duration" : "Break Duration" }
    var restBeforeNextLabel: String { self == .workout ? "Rest Before Next Exercise" : "Break Before Next Interval" }
    var noRestContinuationMessage: String {
        self == .workout
            ? "No rest — continues straight into the linked superset exercise."
            : "No break — continues straight into the linked interval."
    }

    var supersetActionLabel: String { self == .workout ? "Superset" : "Link" }
    var unlinkSupersetActionLabel: String { self == .workout ? "Unlink Superset" : "Unlink" }
    var supersetWithPreviousLabel: String { self == .workout ? "Superset with Previous" : "Link with Previous" }
    var timedSupersetLabel: String { self == .workout ? "Timed Superset" : "Timed Chain" }

    var startButtonLabel: String { self == .workout ? "Start Workout" : "Start Timer" }
    var endAlertTitle: String { self == .workout ? "End Workout?" : "End Timer?" }
    var endAlertMessage: String {
        self == .workout ? "Are you sure you want to end this workout?" : "Are you sure you want to end this timer?"
    }
    var endButtonLabel: String { self == .workout ? "End Workout" : "End Timer" }
    var cancelConfirmTitle: String { endAlertTitle }

    var upNextCompleteLabel: String { self == .workout ? "Workout Complete" : "All Done" }

    var recapCompletedTitle: String { self == .workout ? "Workout Complete!" : "All Done!" }
    var recapEndedTitle: String { self == .workout ? "Workout Ended" : "Timer Ended" }
    var recapItemsLabel: String { itemNamePlural }
    var recapItemsIcon: String { self == .workout ? "figure.strengthtraining.traditional" : "timer" }
    var recapSetsLabel: String { self == .workout ? "Sets" : "Cycles" }
    var recapSetsIcon: String { self == .workout ? "repeat" : "arrow.triangle.2.circlepath" }
    var recapActiveLabel: String { self == .workout ? "Active Time" : "Time Active" }
    var recapActiveIcon: String { self == .workout ? "figure.run" : "play.circle.fill" }
    var recapRestLabel: String { self == .workout ? "Rest Time" : "Break Time" }
    var recapRestIcon: String { self == .workout ? "bed.double.fill" : "cup.and.saucer.fill" }
    var recapItemsSkippedLabel: String { self == .workout ? "Exercises Skipped" : "Intervals Skipped" }
    var recapRestSkippedLabel: String { self == .workout ? "Rest Skipped" : "Break Skipped" }

    var restCompleteNotificationTitle: String { self == .workout ? "Rest Complete" : "Break Complete" }
    var activeCompleteNotificationTitle: String { self == .workout ? "Timer Complete" : "Interval Complete" }

    var watchStartButtonLabel: String { startButtonLabel }
    var watchItemsReadySuffix: String { self == .workout ? "exercise(s) ready" : "interval(s) ready" }
    var watchManualButtonLabel: String { manualAdvanceButtonLabel }
    var watchManualPhaseLabel: String { self == .workout ? "REPS" : "PROMPT" }
}

/// Commands sent between iOS and watchOS to control workout state.
/// iPhone is always the timer authority — watch sends action commands back.
enum WorkoutCommand: Codable, Equatable {
    /// `workoutID` identifies this specific workout session. `.zoneSummary` is delivered via
    /// `transferUserInfo` (queued, best-effort) so it can arrive after a *later* workout has
    /// already started — the receiver compares this id against the current workout's id and
    /// discards anything that doesn't match, rather than displaying stale zone data.
    case start(exercises: [Exercise], kind: SessionKind, healthKitEnabled: Bool, activityType: String?, workoutID: UUID)
    case updatePhase(exerciseIndex: Int, set: Int, isResting: Bool, isPaused: Bool,
                     phaseEndDate: Date?, isCompleted: Bool)
    case pause
    case resume
    case stop
    case healthData(heartRate: Double, activeCalories: Double, hrZoneIndex: Int?)
    /// Sent from watch to iPhone when user completes a rep-based (or prompt-based) set
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
    /// Sent from iPhone/Mac to watch when the weight for an exercise is adjusted mid-session
    /// (e.g. realizing a set is too heavy/light and changing it for the next set/round).
    /// `weight` of `nil` clears it. iPhone/Mac remains the source of truth — the watch only mirrors this.
    case updateWeight(exerciseIndex: Int, weight: Double?, weightUnit: WeightUnit)
    /// Sent from iPhone/Mac to watch when the target reps for an exercise are adjusted mid-session.
    /// `reps` of `nil` clears it. iPhone/Mac remains the source of truth — the watch only mirrors this.
    case updateTargetReps(exerciseIndex: Int, reps: Int?, repsMax: Int?)
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
    static let hrZoneSettings = "hrZoneSettings"
    static let sessionKind = "sessionKind"
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

/// A named, saved collection of exercises or intervals.
struct Routine: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var exercises: [Exercise]
    /// Defaults to `.workout` so routines saved before this existed keep working, since
    /// every routine was a workout at the time.
    var kind: SessionKind = .workout
    /// Optional free-form folder name, e.g. "Push Day" or "Leg Day" — lets a person organize
    /// their own saved/imported routines in the Routines tab. `nil` (or blank) means
    /// uncategorized. Never set on preloaded routines, which group by `PreloadedRoutine.seriesName` instead.
    var category: String?

    enum CodingKeys: String, CodingKey {
        case id, name, exercises, kind, category
    }

    init(id: UUID = UUID(), name: String, exercises: [Exercise], kind: SessionKind = .workout, category: String? = nil) {
        self.id = id
        self.name = name
        self.exercises = exercises
        self.kind = kind
        self.category = category
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        exercises = try container.decode([Exercise].self, forKey: .exercises)
        kind = try container.decodeIfPresent(SessionKind.self, forKey: .kind) ?? .workout
        category = try container.decodeIfPresent(String.self, forKey: .category)
    }
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
