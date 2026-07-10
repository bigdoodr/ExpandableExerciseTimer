import Foundation
import WatchKit
internal import Combine

/// Display state container for the watch workout UI.
/// The iPhone is always the timer authority — this engine only mirrors
/// state received via `.updatePhase` commands and updates the display timer.
@MainActor
final class WatchWorkoutEngine: ObservableObject {
    
    @Published var exercises: [Exercise] = []
    @Published var currentExerciseIndex = 0
    @Published var currentSet = 1
    @Published var isResting = false
    @Published var isPaused = false
    @Published var isCompleted = false
    @Published var isWorkoutRunning = false
    @Published var phaseEndDate: Date?
    @Published var timeRemaining: TimeInterval = 0
    @Published var healthKitEnabled = false
    @Published var activityTypeName: String?
    
    var currentExercise: Exercise? {
        guard !exercises.isEmpty else { return nil }
        let safeIndex = min(max(0, currentExerciseIndex), exercises.count - 1)
        return exercises[safeIndex]
    }
    
    var displayExerciseNumber: Int {
        guard !exercises.isEmpty else { return 0 }
        return min(max(0, currentExerciseIndex), exercises.count - 1) + 1
    }
    
    // MARK: - Workout Lifecycle
    
    /// Set up the workout display. Called when either device initiates a workout.
    /// Does NOT start timers — the iPhone sends `.updatePhase` with timing data.
    func startWorkout(exercises: [Exercise], healthKitEnabled: Bool, activityType: String?) {
        self.exercises = exercises
        self.currentExerciseIndex = 0
        self.currentSet = 1
        self.isResting = false
        self.isPaused = false
        self.isCompleted = false
        self.isWorkoutRunning = true
        self.healthKitEnabled = healthKitEnabled
        self.activityTypeName = activityType
    }
    
    func stopWorkout() {
        isCompleted = true
        isWorkoutRunning = false
    }
    
    // MARK: - Display Timer
    
    /// Update the display countdown. Called every timer tick.
    /// Plays haptic feedback when a timed phase reaches zero.
    func tickTimer() {
        guard !isPaused, !isCompleted, let endDate = phaseEndDate else { return }
        let newRemaining = max(0, endDate.timeIntervalSinceNow)
        // Haptic feedback when countdown hits zero
        if timeRemaining > 0 && newRemaining <= 0 {
            WKInterfaceDevice.current().play(.notification)
        }
        timeRemaining = newRemaining
    }
    
    /// Recalculate display timer after wrist-raise or app foregrounding.
    func recalculateOnWake() {
        guard !isPaused, !isCompleted, let endDate = phaseEndDate else { return }
        timeRemaining = max(0, endDate.timeIntervalSinceNow)
    }
    
    // MARK: - State Updates from iPhone
    
    /// Apply a state update received from iPhone via `.updatePhase`.
    func applyUpdate(exerciseIndex: Int, set: Int, isResting: Bool,
                     isPaused: Bool, phaseEndDate: Date?, isCompleted: Bool) {
        self.currentExerciseIndex = exerciseIndex
        self.currentSet = set
        self.isResting = isResting
        self.isPaused = isPaused
        self.phaseEndDate = phaseEndDate
        self.isCompleted = isCompleted
        if let endDate = phaseEndDate {
            self.timeRemaining = max(0, endDate.timeIntervalSinceNow)
        }
    }
    
    // MARK: - Up Next Text
    
    var upNextText: String {
        guard !isCompleted, let exercise = currentExercise else { return "" }
        
        if isResting {
            let nextSet = currentSet + 1
            if nextSet <= exercise.sets {
                let name = exercise.name.isEmpty ? "Exercise \(displayExerciseNumber)" : exercise.name
                if exercise.isTimeBased {
                    return "Up Next: \(name) – Set \(nextSet)"
                } else {
                    return "Up Next: \(name) – Set \(nextSet) (Reps)"
                }
            } else {
                let nextIndex = currentExerciseIndex + 1
                if nextIndex >= exercises.count {
                    return "Up Next: Workout Complete"
                } else {
                    let next = exercises[nextIndex]
                    return "Up Next: \(nextExerciseLabel(next, index: nextIndex))"
                }
            }
        } else {
            if currentSet < exercise.sets {
                if exercise.restDuration > 0 {
                    return "Up Next: Rest (\(formatTime(exercise.restDuration)))"
                } else {
                    return "Up Next: Set \(currentSet + 1)"
                }
            } else {
                if exercise.restDuration > 0 {
                    return "Up Next: Rest (\(formatTime(exercise.restDuration)))"
                } else {
                    let nextIndex = currentExerciseIndex + 1
                    if nextIndex >= exercises.count {
                        return "Up Next: Workout Complete"
                    } else {
                        let next = exercises[nextIndex]
                        return "Up Next: \(nextExerciseLabel(next, index: nextIndex))"
                    }
                }
            }
        }
    }

    private func nextExerciseLabel(_ exercise: Exercise, index: Int) -> String {
        let name = exercise.name.isEmpty ? "Exercise \(index + 1)" : exercise.name
        let summary = exercise.quickSummary
        return summary.isEmpty ? name : "\(name) · \(summary)"
    }
    
    func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}
