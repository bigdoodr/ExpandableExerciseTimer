import SwiftUI
import HealthKit
internal import Combine

struct WatchWorkoutView: View {
    @EnvironmentObject var connectivity: WatchConnectivityManager
    @EnvironmentObject var healthKit: HealthKitWorkoutManager
    @StateObject private var engine = WatchWorkoutEngine()
    @Environment(\.scenePhase) private var scenePhase
    
    let timer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()
    
    var body: some View {
        if engine.isWorkoutRunning && !engine.exercises.isEmpty {
            activeWorkoutView
        } else {
            waitingView
        }
    }
    
    // MARK: - Waiting View
    
    private var waitingView: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.run")
                .font(.largeTitle)
                .foregroundStyle(.green)
            Text("Exercise Timer")
                .font(.headline)
            
            if !connectivity.receivedExercises.isEmpty {
                Button(action: startLocalWorkout) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Start Workout")
                    }
                    .font(.headline)
                    .foregroundStyle(.green)
                }
                
                Text("\(connectivity.receivedExercises.count) exercise(s) ready")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Start a workout\non your iPhone")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .onChange(of: connectivity.receivedCommand) { _, command in
            handleCommand(command)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active, let cmd = connectivity.receivedCommand {
                handleCommand(cmd)
            }
        }
    }
    
    // MARK: - Active Workout View
    
    private var activeWorkoutView: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Exercise info
                Text(currentExerciseName)
                    .font(.headline)
                    .lineLimit(2)
                
                Text("Set \(engine.currentSet) of \(engine.currentExercise?.sets ?? 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                // Phase indicator + timer
                if engine.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.green)
                    Text("Complete!")
                        .font(.title3)
                        .bold()
                } else if engine.isResting {
                    Text("REST")
                        .font(.title3)
                        .bold()
                        .foregroundStyle(.orange)
                    Text(engine.formatTime(engine.timeRemaining))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .monospacedDigit()
                } else if engine.currentExercise?.isTimeBased == true {
                    Text("EXERCISE")
                        .font(.title3)
                        .bold()
                        .foregroundStyle(.green)
                    Text(engine.formatTime(engine.timeRemaining))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .monospacedDigit()
                } else {
                    Text("REPS")
                        .font(.title3)
                        .bold()
                        .foregroundStyle(.blue)
                    
                    if engine.source == .local {
                        Button(action: {
                            engine.repsComplete()
                        }) {
                            Text("Reps Complete")
                                .font(.caption)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.blue)
                                .cornerRadius(8)
                        }
                    } else {
                        Text("Complete reps")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if engine.isPaused && !engine.isCompleted {
                    Text("PAUSED")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                        .bold()
                }
                
                // Up Next
                if !engine.isCompleted {
                    Text(engine.upNextText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                }
                
                // HealthKit metrics
                if healthKit.isWorkoutActive || engine.healthKitEnabled {
                    Divider()
                        .padding(.vertical, 4)
                    
                    if healthKit.isWorkoutActive {
                        HStack(spacing: 16) {
                            VStack(spacing: 2) {
                                Image(systemName: "heart.fill")
                                    .foregroundStyle(.red)
                                    .font(.caption)
                                if healthKit.heartRate > 0 {
                                    Text("\(Int(healthKit.heartRate))")
                                        .font(.caption)
                                        .bold()
                                } else {
                                    Text("--")
                                        .font(.caption)
                                        .bold()
                                        .foregroundStyle(.secondary)
                                }
                                Text("BPM")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                            }
                            VStack(spacing: 2) {
                                Image(systemName: "flame.fill")
                                    .foregroundStyle(.orange)
                                    .font(.caption)
                                if healthKit.activeCalories > 0 {
                                    Text("\(Int(healthKit.activeCalories))")
                                        .font(.caption)
                                        .bold()
                                } else {
                                    Text("--")
                                        .font(.caption)
                                        .bold()
                                        .foregroundStyle(.secondary)
                                }
                                Text("CAL")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("Starting fitness tracking...")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Workout controls
                if !engine.isCompleted {
                    Divider()
                        .padding(.vertical, 4)
                    
                    // Pause/Resume (local mode only)
                    if engine.source == .local {
                        Button(action: {
                            engine.togglePause()
                            if healthKit.isWorkoutActive {
                                if engine.isPaused {
                                    healthKit.pauseWorkout()
                                } else {
                                    healthKit.resumeWorkout()
                                }
                            }
                        }) {
                            HStack {
                                Image(systemName: engine.isPaused ? "play.fill" : "pause.fill")
                                Text(engine.isPaused ? "Resume" : "Pause")
                            }
                            .font(.caption)
                            .foregroundStyle(.orange)
                        }
                    }
                    
                    // End workout (always available)
                    Button(action: endWorkout) {
                        HStack {
                            Image(systemName: "stop.fill")
                            Text("End Workout")
                        }
                        .font(.caption)
                        .foregroundStyle(.red)
                    }
                }
            }
            .padding()
        }
        .onReceive(timer) { _ in
            engine.tickTimer()
        }
        .onChange(of: connectivity.receivedCommand) { _, command in
            handleCommand(command)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                engine.recalculateOnWake()
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var currentExerciseName: String {
        guard let exercise = engine.currentExercise else { return "Exercise" }
        return exercise.name.isEmpty ? "Exercise \(engine.displayExerciseNumber)" : exercise.name
    }
    
    // MARK: - Actions
    
    private func startLocalWorkout() {
        let exercises = connectivity.receivedExercises
        let hkEnabled = connectivity.receivedHealthKitEnabled
        let actType = connectivity.receivedActivityType
        
        engine.startWorkout(exercises: exercises, healthKitEnabled: hkEnabled, activityType: actType)
        
        if hkEnabled {
            Task {
                await healthKit.requestAuthorization()
                let config = HealthKitWorkoutManager.workoutConfiguration(for: actType)
                await healthKit.startWorkoutSession(with: config)
            }
        }
    }
    
    private func endWorkout() {
        engine.stopWorkout()
        Task {
            await healthKit.endWorkout()
        }
    }
    
    // MARK: - Command Handling
    
    private func handleCommand(_ command: WorkoutCommand?) {
        guard let command else { return }
        
        switch command {
        case .start(let exerciseList, let hkEnabled, let actType):
            engine.applyRemoteStart(exercises: exerciseList, healthKitEnabled: hkEnabled, activityType: actType)
            
            if hkEnabled {
                Task {
                    await healthKit.requestAuthorization()
                    let config = HealthKitWorkoutManager.workoutConfiguration(for: actType)
                    await healthKit.startWorkoutSession(with: config)
                }
            }
            
        case .updatePhase(let exerciseIndex, let set, let resting, let paused, let endDate, let completed):
            engine.applyRemoteUpdate(
                exerciseIndex: exerciseIndex, set: set, isResting: resting,
                isPaused: paused, phaseEndDate: endDate, isCompleted: completed
            )
            if completed {
                Task {
                    await healthKit.endWorkout()
                    try? await Task.sleep(for: .seconds(5))
                    engine.isWorkoutRunning = false
                }
            }
            
        case .pause:
            engine.isPaused = true
            if healthKit.isWorkoutActive {
                healthKit.pauseWorkout()
            }
            
        case .resume:
            engine.isPaused = false
            if healthKit.isWorkoutActive {
                healthKit.resumeWorkout()
            }
            
        case .stop:
            engine.stopWorkout()
            Task { await healthKit.endWorkout() }
        }
    }
}
