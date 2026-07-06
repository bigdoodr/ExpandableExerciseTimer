import SwiftUI
import HealthKit
import WatchKit
internal import Combine

struct WatchWorkoutView: View {
    @EnvironmentObject var connectivity: WatchConnectivityManager
    @EnvironmentObject var healthKit: HealthKitWorkoutManager
    @StateObject private var engine = WatchWorkoutEngine()
    @Environment(\.scenePhase) private var scenePhase
    
    /// Tracks when we last sent health data to throttle updates
    @State private var lastHealthDataSend: Date = .distantPast
    /// Confirmation before ending workout
    @State private var showEndConfirmation = false
    /// Workout start time for elapsed-time display
    @State private var workoutStartDate: Date = .now
    /// Running total of session elapsed time (updated every timer tick)
    @State private var sessionElapsed: TimeInterval = 0
    /// Show recap screen after workout ends
    @State private var showRecap = false
    /// Captured recap data
    @State private var recapData: WorkoutRecap?
    /// Accumulated heart rate readings for average calculation
    @State private var heartRateReadings: [Double] = []
    
    let timer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()
    
    var body: some View {
        Group {
            if let recap = recapData, showRecap {
                watchRecapView(recap)
            } else if engine.isWorkoutRunning && !engine.exercises.isEmpty {
                activeWorkoutView
            } else {
                waitingView
            }
        }
        .alert("End Workout?", isPresented: $showEndConfirmation) {
            Button("End", role: .destructive) {
                endWorkoutWithRecap(completedNaturally: false)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to end this workout?")
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
                Button(action: startWorkout) {
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
        .onAppear {
            // Clear any leftover recap from a previous session
            if !engine.isWorkoutRunning {
                showRecap = false
                recapData = nil
                heartRateReadings = []
                sessionElapsed = 0
            }
        }
        .onChange(of: connectivity.receivedCommand) { _, command in
            handleCommand(command)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active, let cmd = connectivity.receivedCommand,
               case .start = cmd {
                handleCommand(cmd)
            }
        }
    }
    
    // MARK: - Active Workout View
    
    private var activeWorkoutView: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Session elapsed time
                Text(engine.formatTime(sessionElapsed))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                
                // Exercise info
                Text(currentExerciseName)
                    .font(.headline)
                    .lineLimit(2)
                
                Text("Set \(engine.currentSet) of \(engine.currentExercise?.sets ?? 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                // Weight reminder (if set)
                if let currentEx = engine.currentExercise, let weight = currentEx.weight {
                    Text(formatWeight(weight, unit: currentEx.weightUnit))
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
                
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
                    
                    // Target reps reminder
                    if let targetReps = engine.currentExercise?.targetReps {
                        Text("Target: \(targetReps) reps")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    
                    Button(action: {
                        WKInterfaceDevice.current().play(.click)
                        connectivity.sendWorkoutCommand(.repsComplete)
                    }) {
                        Text("Reps Complete")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.blue)
                            .cornerRadius(8)
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
                                    Text("BPM")
                                        .font(.system(size: 8))
                                        .foregroundStyle(.secondary)
                                    // HR Zone
                                    if let zone = HRZone.zone(for: healthKit.heartRate, maxHR: healthKit.maxHeartRate) {
                                        Text("Z\(zone.number)·\(zone.fuelType)")
                                            .font(.system(size: 8))
                                            .foregroundStyle(hrZoneColor(zone.number))
                                    }
                                } else {
                                    Text("--")
                                        .font(.caption)
                                        .bold()
                                        .foregroundStyle(.secondary)
                                    Text("BPM")
                                        .font(.system(size: 8))
                                        .foregroundStyle(.secondary)
                                }
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
                    } else if let error = healthKit.startError {
                        VStack(spacing: 4) {
                            Text("Tracking unavailable")
                                .font(.caption2)
                                .foregroundStyle(.red)
                            Text(error)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(3)
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
                    
                    // Pause/Resume
                    Button(action: {
                        let willPause = !engine.isPaused
                        engine.isPaused = willPause
                        if healthKit.isWorkoutActive {
                            if willPause {
                                healthKit.pauseWorkout()
                            } else {
                                healthKit.resumeWorkout()
                            }
                        }
                        connectivity.sendWorkoutCommand(willPause ? .pause : .resume)
                    }) {
                        HStack {
                            Image(systemName: engine.isPaused ? "play.fill" : "pause.fill")
                            Text(engine.isPaused ? "Resume" : "Pause")
                        }
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                    
                    // End workout — shows confirmation first
                    Button(action: { showEndConfirmation = true }) {
                        HStack {
                            Image(systemName: "stop.fill")
                            Text("End Workout")
                        }
                        .font(.caption)
                        .foregroundStyle(.red)
                    }
                }
                
                // Bottom padding to prevent Digital Crown overscroll from
                // triggering the End Workout button
                Spacer()
                    .frame(height: 60)
            }
            .padding()
        }
        .onReceive(timer) { _ in
            engine.tickTimer()
            sessionElapsed = Date().timeIntervalSince(workoutStartDate)
            // Accumulate heart rate readings for average calculation in recap.
            if healthKit.isWorkoutActive,
               Date().timeIntervalSince(lastHealthDataSend) >= 2.0 {
                let hr = healthKit.heartRate
                if hr > 0 {
                    heartRateReadings.append(hr)
                }
                lastHealthDataSend = Date()
            }
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
    
    // MARK: - Recap View
    
    private func watchRecapView(_ recap: WorkoutRecap) -> some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: recap.completedNaturally ? "checkmark.circle.fill" : "stop.circle.fill")
                    .font(.title2)
                    .foregroundStyle(recap.completedNaturally ? .green : .orange)
                
                Text(recap.completedNaturally ? "Workout Complete!" : "Workout Ended")
                    .font(.headline)
                
                Divider()
                    .padding(.vertical, 4)
                
                // Duration
                HStack {
                    Image(systemName: "clock")
                        .foregroundStyle(.blue)
                    Text("Duration")
                        .font(.caption)
                    Spacer()
                    Text(engine.formatTime(recap.duration))
                        .font(.caption)
                        .bold()
                }
                
                // Exercises
                HStack {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .foregroundStyle(.green)
                    Text("Exercises")
                        .font(.caption)
                    Spacer()
                    Text("\(recap.exercisesCompleted)/\(recap.totalExercises)")
                        .font(.caption)
                        .bold()
                }
                
                // Sets
                HStack {
                    Image(systemName: "repeat")
                        .foregroundStyle(.purple)
                    Text("Sets")
                        .font(.caption)
                    Spacer()
                    Text("\(recap.setsCompleted)/\(recap.totalSets)")
                        .font(.caption)
                        .bold()
                }
                
                // Average Heart Rate (if available)
                if recap.heartRate > 0 {
                    HStack {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.red)
                        Text("Avg HR")
                            .font(.caption)
                        Spacer()
                        Text("\(Int(recap.heartRate)) BPM")
                            .font(.caption)
                            .bold()
                    }
                }
                
                // Calories (if available)
                if recap.calories > 0 {
                    HStack {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(.orange)
                        Text("Calories")
                            .font(.caption)
                        Spacer()
                        Text("\(Int(recap.calories)) CAL")
                            .font(.caption)
                            .bold()
                    }
                }
                
                Divider()
                    .padding(.vertical, 4)
                
                Button(action: dismissRecap) {
                    Text("Done")
                        .font(.headline)
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding()
        }
    }
    
    // MARK: - Computed Properties
    
    private var averageHeartRate: Double {
        guard !heartRateReadings.isEmpty else { return healthKit.heartRate }
        return heartRateReadings.reduce(0, +) / Double(heartRateReadings.count)
    }

    private var currentExerciseName: String {
        guard let exercise = engine.currentExercise else { return "Exercise" }
        return exercise.name.isEmpty ? "Exercise \(engine.displayExerciseNumber)" : exercise.name
    }
    
    private func hrZoneColor(_ zone: Int) -> Color {
        switch zone {
        case 1: return .blue
        case 2: return .teal
        case 3: return .green
        case 4: return .orange
        default: return .red
        }
    }
    
    private func formatWeight(_ weight: Double, unit: WeightUnit = .lbs) -> String {
        let rounded = weight.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(weight))
            : String(format: "%.1f", weight)
        return "\(rounded) \(unit.rawValue)"
    }
    
    // MARK: - Actions
    
    private func startWorkout() {
        let exercises = connectivity.receivedExercises
        let hkEnabled = connectivity.receivedHealthKitEnabled
        let actType = connectivity.receivedActivityType
        
        connectivity.sendWorkoutCommand(.start(exercises: exercises, healthKitEnabled: hkEnabled, activityType: actType))
        engine.startWorkout(exercises: exercises, healthKitEnabled: hkEnabled, activityType: actType)
        workoutStartDate = Date()
        sessionElapsed = 0
        
        if hkEnabled {
            Task {
                await healthKit.requestAuthorization()
                if !healthKit.isAuthorized {
                    healthKit.startError = "HealthKit permission not granted. Please enable in Settings > Privacy & Security > Health."
                    return
                }
                let config = HealthKitWorkoutManager.workoutConfiguration(for: actType)
                await healthKit.startWorkoutSession(with: config)
            }
        }
    }
    
    private func endWorkoutWithRecap(completedNaturally: Bool) {
        let duration = Date().timeIntervalSince(workoutStartDate)
        let exercisesCompleted: Int
        if completedNaturally {
            exercisesCompleted = engine.exercises.count
        } else {
            exercisesCompleted = min(engine.currentExerciseIndex + 1, engine.exercises.count)
        }
        let setsCompleted = computeSetsCompleted(completedNaturally: completedNaturally)
        let totalSets = engine.exercises.reduce(0) { $0 + $1.sets }
        
        recapData = WorkoutRecap(
            duration: duration,
            exercisesCompleted: exercisesCompleted,
            totalExercises: engine.exercises.count,
            setsCompleted: setsCompleted,
            totalSets: totalSets,
            heartRate: averageHeartRate,
            calories: healthKit.activeCalories,
            completedNaturally: completedNaturally
        )
        
        engine.stopWorkout()
        connectivity.sendWorkoutCommand(.stop)
        Task { await healthKit.endWorkout() }
        
        showRecap = true
    }
    
    private func dismissRecap() {
        showRecap = false
        recapData = nil
        engine.isWorkoutRunning = false
        heartRateReadings = []
        sessionElapsed = 0
    }
    
    private func computeSetsCompleted(completedNaturally: Bool) -> Int {
        if completedNaturally {
            return engine.exercises.reduce(0) { $0 + $1.sets }
        }
        var total = 0
        for i in 0..<engine.currentExerciseIndex {
            total += engine.exercises[i].sets
        }
        total += max(0, engine.currentSet - (engine.isResting ? 0 : 1))
        return total
    }
    
    // MARK: - Command Handling
    
    private func handleCommand(_ command: WorkoutCommand?) {
        guard let command else { return }
        
        switch command {
        case .start(let exerciseList, let hkEnabled, let actType):
            engine.startWorkout(exercises: exerciseList, healthKitEnabled: hkEnabled, activityType: actType)
            workoutStartDate = Date()
            sessionElapsed = 0
            
            if hkEnabled {
                Task {
                    await healthKit.requestAuthorization()
                    if !healthKit.isAuthorized {
                        healthKit.startError = "HealthKit permission not granted. Please enable in Settings > Privacy & Security > Health."
                        return
                    }
                    let config = HealthKitWorkoutManager.workoutConfiguration(for: actType)
                    await healthKit.startWorkoutSession(with: config)
                }
            }
            
        case .updatePhase(let exerciseIndex, let set, let resting, let paused, let endDate, let completed):
            engine.applyUpdate(
                exerciseIndex: exerciseIndex, set: set, isResting: resting,
                isPaused: paused, phaseEndDate: endDate, isCompleted: completed
            )
            if completed {
                Task {
                    await healthKit.endWorkout()
                    let duration = Date().timeIntervalSince(workoutStartDate)
                    let totalSets = engine.exercises.reduce(0) { $0 + $1.sets }
                    await MainActor.run {
                        recapData = WorkoutRecap(
                            duration: duration,
                            exercisesCompleted: engine.exercises.count,
                            totalExercises: engine.exercises.count,
                            setsCompleted: totalSets,
                            totalSets: totalSets,
                            heartRate: averageHeartRate,
                            calories: healthKit.activeCalories,
                            completedNaturally: true
                        )
                        showRecap = true
                    }
                }
            }
            
        case .pause:
            engine.isPaused = true
            if healthKit.isWorkoutActive { healthKit.pauseWorkout() }
            
        case .resume:
            engine.isPaused = false
            if healthKit.isWorkoutActive { healthKit.resumeWorkout() }
            
        case .stop:
            let duration = Date().timeIntervalSince(workoutStartDate)
            let exercisesCompleted = min(engine.currentExerciseIndex + 1, engine.exercises.count)
            let setsCompleted = computeSetsCompleted(completedNaturally: false)
            let totalSets = engine.exercises.reduce(0) { $0 + $1.sets }
            recapData = WorkoutRecap(
                duration: duration,
                exercisesCompleted: exercisesCompleted,
                totalExercises: engine.exercises.count,
                setsCompleted: setsCompleted,
                totalSets: totalSets,
                heartRate: averageHeartRate,
                calories: healthKit.activeCalories,
                completedNaturally: false
            )
            engine.stopWorkout()
            Task { await healthKit.endWorkout() }
            showRecap = true
            
        case .healthData, .repsComplete:
            break
        }
    }
}

// MARK: - Recap Data

struct WorkoutRecap {
    let duration: TimeInterval
    let exercisesCompleted: Int
    let totalExercises: Int
    let setsCompleted: Int
    let totalSets: Int
    let heartRate: Double
    let calories: Double
    let completedNaturally: Bool
}
