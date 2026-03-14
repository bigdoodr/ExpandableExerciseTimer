import SwiftUI
import HealthKit
internal import Combine

struct WatchWorkoutView: View {
    @EnvironmentObject var connectivity: WatchConnectivityManager
    @EnvironmentObject var healthKit: HealthKitWorkoutManager
    
    @State private var isWorkoutRunning = false
    @State private var exercises: [Exercise] = []
    @State private var currentExerciseIndex = 0
    @State private var currentSet = 1
    @State private var isResting = false
    @State private var isPaused = false
    @State private var isCompleted = false
    @State private var phaseEndDate: Date?
    @State private var timeRemaining: TimeInterval = 0
    @State private var healthKitEnabled = false
    @State private var activityTypeName: String?
    
    let timer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()
    
    var body: some View {
        if isWorkoutRunning && !exercises.isEmpty {
            activeWorkoutView
        } else {
            waitingView
        }
    }
    
    private var waitingView: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.run")
                .font(.largeTitle)
                .foregroundStyle(.green)
            Text("Exercise Timer")
                .font(.headline)
            Text("Start a workout\non your iPhone")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .onChange(of: connectivity.receivedCommand) { _, command in
            handleCommand(command)
        }
    }
    
    private var activeWorkoutView: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Exercise info
                Text(currentExerciseName)
                    .font(.headline)
                    .lineLimit(2)
                
                Text("Set \(currentSet) of \(currentExercise?.sets ?? 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                // Phase indicator + timer
                if isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.green)
                    Text("Complete!")
                        .font(.title3)
                        .bold()
                } else if isResting {
                    Text("REST")
                        .font(.title3)
                        .bold()
                        .foregroundStyle(.orange)
                    Text(formatTime(timeRemaining))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .monospacedDigit()
                } else if currentExercise?.isTimeBased == true {
                    Text("EXERCISE")
                        .font(.title3)
                        .bold()
                        .foregroundStyle(.green)
                    Text(formatTime(timeRemaining))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .monospacedDigit()
                } else {
                    Text("REPS")
                        .font(.title3)
                        .bold()
                        .foregroundStyle(.blue)
                    Text("Complete reps")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if isPaused && !isCompleted {
                    Text("PAUSED")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                        .bold()
                }
                
                // Up Next
                if !isCompleted {
                    Text(upNextText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                }
                
                // HealthKit metrics
                if healthKit.isWorkoutActive {
                    Divider()
                        .padding(.vertical, 4)
                    HStack(spacing: 16) {
                        VStack(spacing: 2) {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.red)
                                .font(.caption)
                            Text("\(Int(healthKit.heartRate))")
                                .font(.caption)
                                .bold()
                            Text("BPM")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                        VStack(spacing: 2) {
                            Image(systemName: "flame.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                            Text("\(Int(healthKit.activeCalories))")
                                .font(.caption)
                                .bold()
                            Text("CAL")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding()
        }
        .onReceive(timer) { _ in
            guard !isPaused, !isCompleted, let endDate = phaseEndDate else { return }
            timeRemaining = max(0, endDate.timeIntervalSinceNow)
        }
        .onChange(of: connectivity.receivedCommand) { _, command in
            handleCommand(command)
        }
    }
    
    // MARK: - Computed Properties
    
    private var currentExercise: Exercise? {
        guard !exercises.isEmpty else { return nil }
        let safeIndex = min(max(0, currentExerciseIndex), exercises.count - 1)
        return exercises[safeIndex]
    }
    
    private var currentExerciseName: String {
        guard let exercise = currentExercise else { return "Exercise" }
        let displayIndex = min(max(0, currentExerciseIndex), exercises.count - 1) + 1
        return exercise.name.isEmpty ? "Exercise \(displayIndex)" : exercise.name
    }
    
    private var displayExerciseNumber: Int {
        guard !exercises.isEmpty else { return 0 }
        return min(max(0, currentExerciseIndex), exercises.count - 1) + 1
    }
    
    private var upNextText: String {
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
    
    // MARK: - Command Handling
    
    private func handleCommand(_ command: WorkoutCommand?) {
        guard let command else { return }
        
        switch command {
        case .start(let exerciseList, let hkEnabled, let actType):
            exercises = exerciseList
            currentExerciseIndex = 0
            currentSet = 1
            isResting = false
            isPaused = false
            isCompleted = false
            isWorkoutRunning = true
            healthKitEnabled = hkEnabled
            activityTypeName = actType
            
            if hkEnabled {
                Task {
                    await healthKit.requestAuthorization()
                    let config = HealthKitWorkoutManager.workoutConfiguration(for: actType)
                    healthKit.startWorkoutSession(with: config)
                }
            }
            
        case .updatePhase(let exerciseIndex, let set, let resting, let paused, let endDate, let completed):
            currentExerciseIndex = exerciseIndex
            currentSet = set
            isResting = resting
            isPaused = paused
            phaseEndDate = endDate
            isCompleted = completed
            
            if let endDate {
                timeRemaining = max(0, endDate.timeIntervalSinceNow)
            }
            
            if completed {
                Task {
                    await healthKit.endWorkout()
                    // Keep showing completion for a moment, then return to waiting
                    try? await Task.sleep(for: .seconds(5))
                    isWorkoutRunning = false
                }
            }
            
        case .pause:
            isPaused = true
            if healthKit.isWorkoutActive {
                healthKit.pauseWorkout()
            }
            
        case .resume:
            isPaused = false
            if healthKit.isWorkoutActive {
                healthKit.resumeWorkout()
            }
            
        case .stop:
            isPaused = true
            isCompleted = true
            Task {
                await healthKit.endWorkout()
                isWorkoutRunning = false
            }
        }
    }
    
    // MARK: - Helpers
    
    private func formatTime(_ time: TimeInterval) -> String {
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
