import Foundation
import WatchKit

/// Encapsulates the workout timer logic for the watch.
/// Supports two modes:
/// - `.local`: watch drives the timer independently (started from watch)
/// - `.remote`: iOS drives the timer, watch mirrors state from commands
@MainActor
final class WatchWorkoutEngine: ObservableObject {
    enum WorkoutSource {
        case local
        case remote
    }
    
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
    
    var source: WorkoutSource = .remote
    
    private var pausedTimeRemaining: TimeInterval?
    
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
        self.source = .local
        self.pausedTimeRemaining = nil
        startCurrentPhase()
    }
    
    func stopWorkout() {
        isPaused = true
        isCompleted = true
        isWorkoutRunning = false
        pausedTimeRemaining = nil
    }
    
    // MARK: - Timer Control
    
    func tickTimer() {
        guard !isPaused, !isCompleted, let endDate = phaseEndDate else { return }
        timeRemaining = max(0, endDate.timeIntervalSinceNow)
        if source == .local && timeRemaining <= 0 {
            timerExpired()
        }
    }
    
    func togglePause() {
        if isPaused {
            // Resume: recalculate phaseEndDate from stored remaining time
            if let remaining = pausedTimeRemaining {
                phaseEndDate = Date().addingTimeInterval(remaining)
                timeRemaining = remaining
                pausedTimeRemaining = nil
            }
            isPaused = false
        } else {
            // Pause: capture current remaining time
            if let endDate = phaseEndDate {
                let remaining = max(0, endDate.timeIntervalSinceNow)
                pausedTimeRemaining = remaining
                timeRemaining = remaining
            }
            isPaused = true
        }
    }
    
    func repsComplete() {
        guard source == .local else { return }
        advanceWorkout()
    }
    
    func recalculateOnWake() {
        guard !isPaused, !isCompleted, let endDate = phaseEndDate else { return }
        let remaining = endDate.timeIntervalSinceNow
        if remaining <= 0 {
            if source == .local {
                timerExpired()
            } else {
                timeRemaining = 0
            }
        } else {
            timeRemaining = remaining
        }
    }
    
    // MARK: - Remote State Updates (Mirror Mode)
    
    func applyRemoteStart(exercises: [Exercise], healthKitEnabled: Bool, activityType: String?) {
        self.exercises = exercises
        self.source = .remote
        self.currentExerciseIndex = 0
        self.currentSet = 1
        self.isResting = false
        self.isPaused = false
        self.isCompleted = false
        self.isWorkoutRunning = true
        self.healthKitEnabled = healthKitEnabled
        self.activityTypeName = activityType
        self.pausedTimeRemaining = nil
    }
    
    func applyRemoteUpdate(exerciseIndex: Int, set: Int, isResting: Bool,
                           isPaused: Bool, phaseEndDate: Date?, isCompleted: Bool) {
        self.source = .remote
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
    
    // MARK: - Phase Management
    
    func startCurrentPhase() {
        guard !isCompleted else { return }
        guard let exercise = currentExercise else { return }
        pausedTimeRemaining = nil
        
        var duration: TimeInterval = 0
        if isResting {
            duration = exercise.restDuration
        } else if exercise.isTimeBased {
            duration = exercise.exerciseDuration
        } else {
            // Rep-based: no countdown
            timeRemaining = 0
            phaseEndDate = nil
            return
        }
        phaseEndDate = Date().addingTimeInterval(duration)
        timeRemaining = duration
    }
    
    // MARK: - Timer Logic (mirrors iOS WorkoutView logic)
    
    private func timerExpired() {
        guard !isCompleted else { return }
        guard let exercise = currentExercise else { return }
        
        // Haptic feedback on watch
        WKInterfaceDevice.current().play(.notification)
        
        if isResting {
            isResting = false
            currentSet += 1
            if currentSet > exercise.sets {
                currentSet = 1
                currentExerciseIndex += 1
                if currentExerciseIndex >= exercises.count {
                    isCompleted = true
                    timeRemaining = 0
                    return
                }
                startCurrentPhase()
            } else {
                startCurrentPhase()
            }
        } else {
            if currentSet < exercise.sets {
                isResting = true
                startCurrentPhase()
            } else {
                if exercise.isTimeBased && exercise.restDuration > 0 {
                    isResting = true
                    startCurrentPhase()
                } else {
                    currentSet = 1
                    currentExerciseIndex += 1
                    if currentExerciseIndex >= exercises.count {
                        isCompleted = true
                        timeRemaining = 0
                        return
                    }
                    startCurrentPhase()
                }
            }
        }
    }
    
    private func advanceWorkout() {
        guard let exercise = currentExercise, !exercise.isTimeBased else { return }
        
        // Haptic feedback for rep completion
        WKInterfaceDevice.current().play(.click)
        
        if currentSet < exercise.sets {
            isResting = true
            startCurrentPhase()
        } else {
            if exercise.restDuration > 0 {
                isResting = true
                startCurrentPhase()
            } else {
                currentSet = 1
                currentExerciseIndex += 1
                if currentExerciseIndex >= exercises.count {
                    isCompleted = true
                    timeRemaining = 0
                    return
                }
                startCurrentPhase()
            }
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
                    return "Up Next: \(next.name.isEmpty ? "Exercise \(nextIndex + 1)" : next.name)"
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
                        return "Up Next: \(next.name.isEmpty ? "Exercise \(nextIndex + 1)" : next.name)"
                    }
                }
            }
        }
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
