import SwiftUI
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(HealthKit)
import HealthKit
#endif
import UniformTypeIdentifiers
internal import Combine

// Ensure all manager classes are available (they should be in the same target)
// If HealthKitWorkoutManager.swift is not in your target, add it via:
// Project Navigator → Select file → File Inspector → Target Membership

fileprivate struct WorkoutUndoAction: Codable {
    let exerciseIndex: Int
    let setBefore: Int
    let wasResting: Bool
    let advancedExercise: Bool
}

@main
struct ExerciseTimerApp: App {
    var body: some Scene {
        WindowGroup {
            ExerciseListView()
        }
    }
}

struct ExerciseListView: View {
    @State private var exercises: [Exercise] = [Exercise()]
    @State private var isWorkoutActive = false
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var exportURL: URL?
#if canImport(WatchConnectivity)
    @StateObject private var connectivity = WatchConnectivityManager.shared
#endif
#if canImport(UIKit)
    @State private var keepScreenAwake = false
    @State private var enableBackgroundAudio = false
#endif
#if canImport(HealthKit)
    @State private var enableHealthKitTracking = false
    @State private var selectedActivityType: WorkoutActivityOption = .functionalStrengthTraining
#endif
    @State private var showingResetConfirm = false
    
    private let exercisesDefaultsKey = "savedExercises"
    
    var body: some View {
        NavigationStack {
#if canImport(WatchConnectivity)
            if isWorkoutActive {
                workoutViewForPlatform
            } else {
                builderView
                    .onChange(of: connectivity.receivedCommand) { _, command in
                        handleWatchCommand(command)
                    }
            }
#else
            if isWorkoutActive {
                workoutViewForPlatform
            } else {
                builderView
            }
#endif
        }
    }
    
    @ViewBuilder
    private var workoutViewForPlatform: some View {
        #if canImport(UIKit) && canImport(HealthKit)
        WorkoutView(
            exercises: exercises,
            isActive: $isWorkoutActive,
            keepScreenAwake: $keepScreenAwake,
            enableBackgroundAudio: $enableBackgroundAudio,
            healthKitEnabled: enableHealthKitTracking,
            activityType: selectedActivityType
        )
        #elseif canImport(UIKit)
        WorkoutView(
            exercises: exercises,
            isActive: $isWorkoutActive,
            keepScreenAwake: $keepScreenAwake,
            enableBackgroundAudio: $enableBackgroundAudio
        )
        #elseif canImport(HealthKit)
        WorkoutView(
            exercises: exercises,
            isActive: $isWorkoutActive,
            healthKitEnabled: enableHealthKitTracking,
            activityType: selectedActivityType
        )
        #else
        WorkoutView(
            exercises: exercises,
            isActive: $isWorkoutActive
        )
        #endif
    }
    
    private var builderView: some View {
        List {
            exerciseListSection
            addExerciseSection
#if canImport(UIKit)
            keepAwakeSection
            backgroundAudioSection
#endif
#if canImport(HealthKit)
            healthKitSection
#endif
            startSection
        }
#if os(iOS)
        .listStyle(.insetGrouped)
#else
        .listStyle(.inset)
#endif
        .navigationTitle("Exercise Timer")
        .toolbar {
            // iOS edit button
            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            #endif
            // Primary actions group
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { showingImporter = true }) { Image(systemName: "square.and.arrow.down") }
                    .accessibilityLabel("Import")
                Button(action: exportExercises) { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Export")
                Button(action: { showingResetConfirm = true }) { Image(systemName: "arrow.counterclockwise") }
                    .accessibilityLabel("Reset")
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            importExercises(result)
        }
        .fileExporter(isPresented: $showingExporter, document: ExerciseDocument(exercises: exercises), contentType: .json, defaultFilename: "exercises.json") { result in
            if case .success = result { exportURL = nil }
        }
        .alert("Reset Exercises?", isPresented: $showingResetConfirm) {
            Button("Reset", role: .destructive) { exercises = [Exercise()]; persistExercises() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all exercises in the builder.")
        }
        .onAppear {
            if exercises.count == 1 && exercises.first?.name == "" && exercises.first?.isTimeBased == true && exercises.first?.sets == 1 && exercises.first?.exerciseDuration == 30 && exercises.first?.restDuration == 10 {
                loadSavedExercises()
            }
        }
        .onChange(of: exercises) { _, _ in
            persistExercises()
        }
        .onChange(of: enableHealthKitTracking) { _, _ in
            persistExercises()
        }
        .onChange(of: selectedActivityType) { _, _ in
            persistExercises()
        }
    }
    
    @ViewBuilder
    private var exerciseListSection: some View {
        Section {
            ForEach(Array(exercises.indices), id: \.self) { index in
                ExerciseEntryRow(exercise: $exercises[index])
            }
            .onMove { (indices: IndexSet, newOffset: Int) in
                exercises.move(fromOffsets: indices, toOffset: newOffset)
            }
            .onDelete { (indexSet: IndexSet) in
                exercises.remove(atOffsets: indexSet)
            }
        }
    }
    
    @ViewBuilder
    private var addExerciseSection: some View {
        Section {
            Button(action: {
                exercises.append(Exercise())
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Exercise")
                }
                .font(.headline)
                .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
        }
    }
    
#if canImport(UIKit)
    @ViewBuilder
    private var keepAwakeSection: some View {
        Section(footer: Text("Prevents the display from sleeping while a workout is active. This does not keep the app running in the background.")) {
            Toggle(isOn: $keepScreenAwake) {
                HStack {
                    Image(systemName: keepScreenAwake ? "moon.zzz.fill" : "moon.zzz")
                    Text("Keep Screen Awake")
                }
            }
            .toggleStyle(.switch)
        }
    }
    
    @ViewBuilder
    private var backgroundAudioSection: some View {
        Section(footer: Text("Keeps a low-level audio session active so timers and sounds continue while the screen is locked or the app is backgrounded. May increase battery usage.")) {
            Toggle(isOn: $enableBackgroundAudio) {
                HStack {
                    Image(systemName: enableBackgroundAudio ? "speaker.wave.2.fill" : "speaker.slash")
                    Text("Background Audio")
                }
            }
            .toggleStyle(.switch)
        }
    }
#endif
    
#if canImport(HealthKit)
    @ViewBuilder
    private var healthKitSection: some View {
        Section(footer: Text("When enabled, workouts are recorded to Apple Health via Apple Watch. Requires a paired Apple Watch. Disable this for non-exercise timers.")) {
            Toggle(isOn: $enableHealthKitTracking) {
                HStack {
                    Image(systemName: enableHealthKitTracking ? "heart.fill" : "heart")
                    Text("HealthKit Tracking")
                }
            }
            .toggleStyle(.switch)
            
            if enableHealthKitTracking {
                Picker("Activity Type", selection: $selectedActivityType) {
                    ForEach(WorkoutActivityOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
            }
        }
    }
#endif
    
    @ViewBuilder
    private var startSection: some View {
        Section {
            Button(action: {
#if canImport(WatchConnectivity) && canImport(HealthKit)
                let command = WorkoutCommand.start(
                    exercises: exercises,
                    healthKitEnabled: enableHealthKitTracking,
                    activityType: enableHealthKitTracking ? selectedActivityType.rawValue : nil
                )
                WatchConnectivityManager.shared.sendWorkoutCommand(command)
#endif
                isWorkoutActive = true
            }) {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Start Workout")
                }
                .font(.headline)
                .foregroundStyle(.green)
            }
            .buttonStyle(.plain)
        }
    }
    
    // Helper row to reduce type-checker load
    private struct ExerciseEntryRow: View {
        @Binding var exercise: Exercise

        var body: some View {
            ExerciseEntryView(exercise: $exercise)
        }
    }
    
    func exportExercises() {
        persistExercises()
        showingExporter = true
    }
    
    func importExercises(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([Exercise].self, from: data)
            exercises = decoded
            persistExercises()
        } catch {
            print("Failed to import: \(error)")
        }
    }
    
    private func loadSavedExercises() {
        if let data = UserDefaults.standard.data(forKey: exercisesDefaultsKey) {
            if let decoded = try? JSONDecoder().decode([Exercise].self, from: data) {
                exercises = decoded
            }
        }
    }
    
    private func persistExercises() {
        if let data = try? JSONEncoder().encode(exercises) {
            UserDefaults.standard.set(data, forKey: exercisesDefaultsKey)
        }
#if canImport(WatchConnectivity) && canImport(HealthKit)
        WatchConnectivityManager.shared.updateContext(
            exercises: exercises,
            healthKitEnabled: enableHealthKitTracking,
            activityType: enableHealthKitTracking ? selectedActivityType.rawValue : nil
        )
#endif
    }
    
#if canImport(WatchConnectivity)
    /// Handle workout commands received from Apple Watch
    private func handleWatchCommand(_ command: WorkoutCommand?) {
        guard let command else { return }
        
        switch command {
        case .start(let exerciseList, _, _):
            // Watch is starting a workout — iPhone drives timers
            exercises = exerciseList
            isWorkoutActive = true
            
        default:
            // Other commands (stop, updatePhase, pause, resume) are handled by WorkoutView
            break
        }
    }
#endif
}

struct ExerciseEntryView: View {
    @Binding var exercise: Exercise
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: {
                withAnimation {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    Text(exercise.name.isEmpty ? "New Exercise" : exercise.name)
                        .font(.headline)
                    Spacer()
                }
                .foregroundStyle(.primary)
                .padding()
#if os(iOS)
                .background(Color(uiColor: .systemGray6))
#elseif os(macOS)
                .background(Color(nsColor: .windowBackgroundColor))
#else
                .background(Color.gray.opacity(0.15))
#endif
                .cornerRadius(12)
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Exercise Name")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("Name", text: $exercise.name)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Exercise Type")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Picker("Type", selection: $exercise.isTimeBased) {
                            Text("Time-Based").tag(true)
                            Text("Rep-Based").tag(false)
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Number of Sets")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Stepper("\(exercise.sets)", value: $exercise.sets, in: 1...99)
                    }
                    
                    if exercise.isTimeBased {
                        DurationPickerView(title: "Exercise Duration", duration: $exercise.exerciseDuration)
                    }
                    
                    DurationPickerView(title: "Rest Duration", duration: $exercise.restDuration)
                }
                .padding()
#if os(iOS)
                .background(Color(uiColor: .systemGray5))
#elseif os(macOS)
                .background(Color(nsColor: .underPageBackgroundColor))
#else
                .background(Color.gray.opacity(0.2))
#endif
                .cornerRadius(12)
            }
        }
        .padding(.horizontal)
    }
}

struct DurationPickerView: View {
    let title: String
    @Binding var duration: TimeInterval
    
#if !os(iOS)
    private let twoDigitFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .none
        f.minimum = 0
        f.maximum = 59
        f.allowsFloats = false
        f.generatesDecimalNumbers = false
        return f
    }()
    private let hourFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .none
        f.minimum = 0
        f.maximum = 23
        f.allowsFloats = false
        f.generatesDecimalNumbers = false
        return f
    }()
#endif
    
    var hours: Int { Int(duration) / 3600 }
    var minutes: Int { (Int(duration) % 3600) / 60 }
    var seconds: Int { Int(duration) % 60 }
    
    private func setHours(_ newHours: Int) {
        duration = TimeInterval((newHours * 3600) + (minutes * 60) + seconds)
    }
    
    private func setMinutes(_ newMinutes: Int) {
        duration = TimeInterval((hours * 3600) + (newMinutes * 60) + seconds)
    }
    
    private func setSeconds(_ newSeconds: Int) {
        duration = TimeInterval((hours * 3600) + (minutes * 60) + newSeconds)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 16) {
                VStack {
                    Text("Hours")
                        .font(.caption)
                        .foregroundStyle(.secondary)
#if os(iOS)
                    Picker("Hours", selection: Binding(
                        get: { hours },
                        set: { setHours($0) }
                    )) {
                        ForEach(0..<24) { hour in
                            Text("\(hour)").tag(hour)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 80, height: 100)
                    .clipped()
#else
                    HStack(spacing: 4) {
                        TextField(
                            "0",
                            value: Binding(
                                get: { hours },
                                set: { setHours(max(0, min(23, $0))) }
                            ),
                            formatter: hourFormatter
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        Text("h")
                            .foregroundStyle(.secondary)
                    }
#endif
                }
                
                VStack {
                    Text("Minutes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
#if os(iOS)
                    Picker("Minutes", selection: Binding(
                        get: { minutes },
                        set: { setMinutes($0) }
                    )) {
                        ForEach(0..<60) { minute in
                            Text("\(minute)").tag(minute)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 80, height: 100)
                    .clipped()
#else
                    HStack(spacing: 4) {
                        TextField(
                            "0",
                            value: Binding(
                                get: { minutes },
                                set: { setMinutes(max(0, min(59, $0))) }
                            ),
                            formatter: twoDigitFormatter
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        Text("m")
                            .foregroundStyle(.secondary)
                    }
#endif
                }
                
                VStack {
                    Text("Seconds")
                        .font(.caption)
                        .foregroundStyle(.secondary)
#if os(iOS)
                    Picker("Seconds", selection: Binding(
                        get: { seconds },
                        set: { setSeconds($0) }
                    )) {
                        ForEach(0..<60) { second in
                            Text("\(second)").tag(second)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 80, height: 100)
                    .clipped()
#else
                    HStack(spacing: 4) {
                        TextField(
                            "0",
                            value: Binding(
                                get: { seconds },
                                set: { setSeconds(max(0, min(59, $0))) }
                            ),
                            formatter: twoDigitFormatter
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        Text("s")
                            .foregroundStyle(.secondary)
                    }
#endif
                }
            }
        }
    }
}

struct WorkoutView: View {
    let exercises: [Exercise]
    @Binding var isActive: Bool
#if canImport(UIKit)
    @Binding var keepScreenAwake: Bool
    @Binding var enableBackgroundAudio: Bool
#endif
#if canImport(HealthKit)
    var healthKitEnabled: Bool
    var activityType: WorkoutActivityOption
#endif
#if canImport(WatchConnectivity)
    @StateObject private var connectivity = WatchConnectivityManager.shared
#endif
#if canImport(HealthKit)
    @StateObject private var healthKitManager = HealthKitWorkoutManager.shared
#endif
    
    @State private var currentExerciseIndex = 0
    @State private var currentSet = 1
    @State private var isResting = false
    @State private var isPaused = false
    @State private var timeRemaining: TimeInterval = 0
    @State private var phaseEndDate: Date = .now
    @State private var isCompleted = false
    @State private var isExiting = false
    @State private var pausedTimeRemaining: TimeInterval? = nil
    
    @State private var undoAction: WorkoutUndoAction? = nil
    @State private var showUndoToast = false
    @State private var showCancelConfirmation = false
    @State private var workoutStartDate: Date = .now
    @State private var showRecap = false
    @State private var recapDuration: TimeInterval = 0
    @State private var recapExercisesCompleted = 0
    @State private var recapSetsCompleted = 0
    @State private var recapHeartRate: Double = 0
    @State private var recapCalories: Double = 0
    @State private var recapCompletedNaturally = false
    @State private var heartRateReadings: [Double] = []
    
    let audioEngine = AVAudioEngine()
    /// Retained reference for completion sound so AVAudioPlayer isn't deallocated mid-play
    @State private var completionSoundPlayer: AVAudioPlayer?
#if canImport(UIKit)
    private let backgroundPlayerNode = AVAudioPlayerNode()
    @State private var isBackgroundLoopRunning = false
#endif
    
    let timer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()
    @Environment(\.scenePhase) private var scenePhase
    
    var currentExercise: Exercise {
        let safeIndex = min(max(0, currentExerciseIndex), max(0, exercises.count - 1))
        return exercises[safeIndex]
    }
    
    var displayExerciseNumber: Int {
        guard !exercises.isEmpty else { return 0 }
        let idx = min(max(0, currentExerciseIndex), max(0, exercises.count - 1))
        return idx + 1
    }
    var totalExercises: Int { exercises.count }
    
    var upNextText: String {
        guard !isCompleted else { return "" }
        
        if isResting {
            // Currently resting. After rest: currentSet increments.
            let nextSet = currentSet + 1
            if nextSet <= currentExercise.sets {
                // More sets of the same exercise
                let name = currentExercise.name.isEmpty ? "Exercise \(displayExerciseNumber)" : currentExercise.name
                if currentExercise.isTimeBased {
                    return "Up Next: \(name) – Set \(nextSet)"
                } else {
                    return "Up Next: \(name) – Set \(nextSet) (Reps)"
                }
            } else {
                // All sets done after this rest; move to next exercise
                let nextIndex = currentExerciseIndex + 1
                if nextIndex >= exercises.count {
                    return "Up Next: Workout Complete"
                } else {
                    let next = exercises[nextIndex]
                    return "Up Next: \(next.name.isEmpty ? "Exercise \(nextIndex + 1)" : next.name)"
                }
            }
        } else {
            // Currently exercising (time-based or rep-based)
            if currentSet < currentExercise.sets {
                // More sets remain – rest comes next
                if currentExercise.restDuration > 0 {
                    return "Up Next: Rest (\(formatTime(currentExercise.restDuration)))"
                } else {
                    return "Up Next: Set \(currentSet + 1)"
                }
            } else {
                // Last set of current exercise
                if currentExercise.restDuration > 0 {
                    return "Up Next: Rest (\(formatTime(currentExercise.restDuration)))"
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
    
    var body: some View {
        Group {
            if showRecap {
                recapView
            } else {
                workoutContent
            }
        }
        .alert("End Workout?", isPresented: $showCancelConfirmation) {
            Button("End Workout", role: .destructive) {
                captureRecap(completedNaturally: false)
                beginExit()
                showRecap = true
            }
            Button("Keep Going", role: .cancel) {}
        } message: {
            Text("Are you sure you want to end this workout?")
        }
    }

    private var workoutContent: some View {
        ScrollView {
            VStack(spacing: 30) {
                VStack(spacing: 8) {
                    Text("Exercise \(displayExerciseNumber) of \(totalExercises)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Text(currentExercise.name.isEmpty ? "Exercise \(displayExerciseNumber)" : currentExercise.name)
                        .font(.largeTitle)
                        .bold()
                    
                    Text("Set \(currentSet) of \(currentExercise.sets)")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .padding()
                
                if isResting {
                    VStack(spacing: 20) {
                        Text("REST")
                            .font(.title)
                            .bold()
                            .foregroundStyle(.orange)
                        
                        Text(formatTime(timeRemaining))
                            .font(.system(size: 72, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                    .padding()
                } else if currentExercise.isTimeBased {
                    VStack(spacing: 20) {
                        Text("EXERCISE")
                            .font(.title)
                            .bold()
                            .foregroundStyle(.green)
                        
                        Text(formatTime(timeRemaining))
                            .font(.system(size: 72, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                    .padding()
                } else {
                    VStack(spacing: 20) {
                        Text("REP-BASED")
                            .font(.title)
                            .bold()
                            .foregroundStyle(.blue)
                        
                        Text("Complete your reps")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        
                        Button(action: {
                            repsCompleteTapped()
                        }) {
                            Text("Reps Complete")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    }
                    .padding()
                }
                
                // "Up Next" line
                if !upNextText.isEmpty {
                    Text(upNextText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
                
#if canImport(HealthKit) && canImport(UIKit)
                // HealthKit Metrics Display
                // Show when iPhone session is active, or when watch is forwarding data
                if healthKitEnabled && healthKitManager.isWorkoutActive {
                    healthKitMetricsView
                        .padding(.horizontal)
                }
#endif
                
#if canImport(UIKit)
                // Two-row layout in compact width: first row Pause/Cancel, second row Awake and Background Audio
                Group {
                    if horizontalSizeClass == .compact {
                        VStack(spacing: 12) {
                            HStack(spacing: 16) {
                                pauseResumeButton
                                cancelButton
                            }
                            HStack(spacing: 16) {
                                awakeButton
                                backgroundAudioButton
                            }
                        }
                    } else {
                        HStack(spacing: 16) {
                            pauseResumeButton
                            cancelButton
                            awakeButton
                            backgroundAudioButton
                        }
                    }
                }
                .padding(.horizontal)
#else
                HStack(spacing: 16) {
                    pauseResumeButton
                    cancelButton
                }
                .padding(.horizontal)
#endif
            }
            .padding(.top)
        }
        .onReceive(timer) { _ in
            if !isExiting && !isCompleted && !showRecap && !isPaused && (currentExercise.isTimeBased || isResting) {
                let now = Date()
                timeRemaining = max(0, phaseEndDate.timeIntervalSince(now))
                if timeRemaining <= 0 {
                    timerExpired()
                }
            }
        }
        .onAppear {
#if canImport(UIKit)
            configureAudioSession()
            if enableBackgroundAudio {
                startBackgroundAudioLoop()
            }
#endif
            // iPhone always drives timers — watch owns HealthKit session
            workoutStartDate = Date()
            requestNotificationPermission()
            startCurrentPhase()
#if canImport(UIKit)
            UIApplication.shared.isIdleTimerDisabled = keepScreenAwake
#endif
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active && !isPaused {
                let remaining = phaseEndDate.timeIntervalSinceNow
                if (currentExercise.isTimeBased || isResting) && remaining <= 0 {
                    timerExpired()
                } else {
                    timeRemaining = max(0, remaining)
                }
            }
        }
#if canImport(UIKit)
        .onChange(of: keepScreenAwake) { _, newValue in
            UIApplication.shared.isIdleTimerDisabled = newValue
        }
        .onChange(of: enableBackgroundAudio) { _, newValue in
            if newValue {
                startBackgroundAudioLoop()
            } else {
                stopBackgroundAudioLoop()
            }
        }
#endif
#if canImport(WatchConnectivity)
        .onChange(of: connectivity.receivedCommand) { _, command in
            handleWatchWorkoutCommand(command)
        }
#endif
        .onDisappear {
            cancelPhaseEndNotification()
#if canImport(UIKit)
            stopBackgroundAudioLoop()
#endif
#if canImport(HealthKit)
            // Reset forwarded health data from watch
            if healthKitEnabled {
                healthKitManager.heartRate = 0
                healthKitManager.activeCalories = 0
                healthKitManager.isWorkoutActive = false
            }
#endif
            if audioEngine.isRunning { audioEngine.stop() }
#if canImport(UIKit)
            UIApplication.shared.isIdleTimerDisabled = false
#endif
        }
        .overlay(alignment: .bottom) {
            if showUndoToast {
                HStack {
                    Text("Set added")
                        .foregroundStyle(.white)
                    Spacer()
                    Button("Undo") {
                        undoLastAction()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .bold()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.bottom, 24)
                .padding(.horizontal)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
    
    // MARK: - Recap View
    
    private var recapView: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: recapCompletedNaturally ? "checkmark.circle.fill" : "stop.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(recapCompletedNaturally ? .green : .orange)
                        
                        Text(recapCompletedNaturally ? "Workout Complete!" : "Workout Ended")
                            .font(.title)
                            .bold()
                    }
                    .padding(.top)
                    
                    // Stats
                    VStack(spacing: 16) {
                        recapRow(icon: "clock", color: .blue, label: "Duration", value: formatTime(recapDuration))
                        
                        Divider()
                        
                        recapRow(icon: "figure.strengthtraining.traditional", color: .green,
                                 label: "Exercises", value: "\(recapExercisesCompleted) of \(exercises.count)")
                        
                        Divider()
                        
                        let totalSets = exercises.reduce(0) { $0 + $1.sets }
                        recapRow(icon: "repeat", color: .purple,
                                 label: "Sets", value: "\(recapSetsCompleted) of \(totalSets)")
                        
#if canImport(HealthKit)
                        if recapHeartRate > 0 {
                            Divider()
                            recapRow(icon: "heart.fill", color: .red,
                                     label: "Avg Heart Rate", value: "\(Int(recapHeartRate)) BPM")
                        }
                        
                        if recapCalories > 0 {
                            Divider()
                            recapRow(icon: "flame.fill", color: .orange,
                                     label: "Calories", value: "\(Int(recapCalories)) CAL")
                        }
#endif
                    }
                    .padding()
#if canImport(UIKit)
                    .background(Color(uiColor: .systemGray6))
#endif
                    .cornerRadius(16)
                    .padding(.horizontal)
                    
                    Button(action: {
                        showRecap = false
                        isActive = false
                    }) {
                        Text("Done")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom)
            }
            .navigationTitle("Summary")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if recapCompletedNaturally {
                    playCompletionSound()
                }
            }
        }
    }
    
    private func recapRow(icon: String, color: Color, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 28)
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .bold()
        }
    }
    
    private func captureRecap(completedNaturally: Bool) {
        recapDuration = Date().timeIntervalSince(workoutStartDate)
        recapCompletedNaturally = completedNaturally
        
        if completedNaturally {
            recapExercisesCompleted = exercises.count
            recapSetsCompleted = exercises.reduce(0) { $0 + $1.sets }
        } else {
            recapExercisesCompleted = min(currentExerciseIndex + 1, exercises.count)
            // Count sets completed in finished exercises + current exercise
            var sets = 0
            for i in 0..<currentExerciseIndex {
                sets += exercises[i].sets
            }
            sets += max(0, currentSet - (isResting ? 0 : 1))
            recapSetsCompleted = sets
        }
        
#if canImport(HealthKit)
        // Use average heart rate over the workout, falling back to last reading
        if !heartRateReadings.isEmpty {
            recapHeartRate = heartRateReadings.reduce(0, +) / Double(heartRateReadings.count)
        } else {
            recapHeartRate = healthKitManager.heartRate
        }
        recapCalories = healthKitManager.activeCalories
#endif
    }
    
#if canImport(WatchConnectivity)
    private func sendStateToWatch() {
        let command = WorkoutCommand.updatePhase(
            exerciseIndex: currentExerciseIndex,
            set: currentSet,
            isResting: isResting,
            isPaused: isPaused,
            phaseEndDate: (currentExercise.isTimeBased || isResting) ? phaseEndDate : nil,
            isCompleted: isCompleted
        )
        WatchConnectivityManager.shared.sendWorkoutCommand(command)
    }
    
    /// Handle workout commands from Apple Watch
    private func handleWatchWorkoutCommand(_ command: WorkoutCommand?) {
        guard let command else { return }
        
        switch command {
        case .start:
            // Watch started the workout, already handled in ExerciseListView
            break
            
        case .updatePhase:
            // iPhone is the timer authority — ignore any updatePhase from watch
            break
            
        case .pause:
            // Watch user tapped pause — pause and send authoritative state back
            let remaining = max(0, phaseEndDate.timeIntervalSinceNow)
            pausedTimeRemaining = remaining
            timeRemaining = remaining
            isPaused = true
            cancelPhaseEndNotification()
            sendStateToWatch()
            
        case .resume:
            // Watch user tapped resume — resume and send authoritative state back
            if let remaining = pausedTimeRemaining {
                phaseEndDate = Date().addingTimeInterval(remaining)
                timeRemaining = remaining
                pausedTimeRemaining = nil
                schedulePhaseEndNotification(in: remaining)
            }
            isPaused = false
            sendStateToWatch()
            
        case .stop:
            // Watch ended the workout — show recap
            captureRecap(completedNaturally: false)
            beginExit()
            showRecap = true
            
        case .repsComplete:
            // Watch user tapped "Reps Complete" — advance and send state back
            repsCompleteTapped()
            
        case .healthData(let heartRate, let activeCalories):
            // Receive live health data forwarded from the watch
            healthKitManager.heartRate = heartRate
            healthKitManager.activeCalories = activeCalories
            // Accumulate for average calculation in recap
            if heartRate > 0 {
                heartRateReadings.append(heartRate)
            }
            // Mark as active so the metrics view shows
            if !healthKitManager.isWorkoutActive {
                healthKitManager.isWorkoutActive = true
            }
        }
    }
#endif
    
    private func beginExit() {
        // Freeze UI and dismiss any modals
        isExiting = true
        isPaused = true
        isCompleted = true
        isResting = false

        // Stop notifications and audio synchronously
        cancelPhaseEndNotification()
#if canImport(UIKit)
        stopBackgroundAudioLoop()
#endif
#if canImport(WatchConnectivity)
        WatchConnectivityManager.shared.sendWorkoutCommand(.stop)
#endif
        // Watch owns HealthKit session — it will end when it receives .stop
        if audioEngine.isRunning { audioEngine.stop() }
#if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = false
#endif
        // Navigation back to builder is handled by the recap view's "Done" button
    }
    
    func startCurrentPhase() {
        if isCompleted { return }
        pausedTimeRemaining = nil
        var duration: TimeInterval = 0
        if isResting {
            duration = currentExercise.restDuration
        } else if currentExercise.isTimeBased {
            duration = currentExercise.exerciseDuration
        } else {
            // Rep-based: no countdown; nothing to schedule
            timeRemaining = 0
            return
        }
        phaseEndDate = Date().addingTimeInterval(duration)
        timeRemaining = max(0, duration)
        schedulePhaseEndNotification(in: duration)
#if canImport(WatchConnectivity)
        sendStateToWatch()
#endif
    }
    
    func timerExpired() {
        if isExiting { return }
        if isCompleted { return }
        cancelPhaseEndNotification()
        playSound()
        
        if isResting {
            // Completed a rest that belongs to the SAME exercise
            isResting = false
            currentSet += 1
            if currentSet > currentExercise.sets {
                // Finished all sets for this exercise; advance to next exercise
                currentSet = 1
                currentExerciseIndex += 1
                if currentExerciseIndex >= exercises.count {
                    isCompleted = true
                    timeRemaining = 0
#if canImport(WatchConnectivity)
                    sendStateToWatch()
#endif
                    captureRecap(completedNaturally: true)
                    showRecap = true
                    return
                }
                // Start next exercise phase
                if exercises[currentExerciseIndex].isTimeBased {
                    startCurrentPhase()
                } else {
                    timeRemaining = 0
#if canImport(WatchConnectivity)
                    sendStateToWatch()
#endif
                }
            } else {
                // Start the next set's exercise for the SAME exercise
                startCurrentPhase()
            }
        } else {
            // Exercise just finished
            if currentSet < currentExercise.sets {
                // More sets remain in the current exercise: rest for the SAME exercise
                isResting = true
                startCurrentPhase()
            } else {
                // Last set for the current exercise: still rest for the SAME exercise
                // Only after this rest completes will we advance to the next exercise
                if currentExercise.isTimeBased && currentExercise.restDuration > 0 {
                    isResting = true
                    startCurrentPhase()
                } else {
                    // No rest for this exercise; advance immediately to next exercise
                    currentSet = 1
                    currentExerciseIndex += 1
                    if currentExerciseIndex >= exercises.count {
                        isCompleted = true
                        timeRemaining = 0
#if canImport(WatchConnectivity)
                        sendStateToWatch()
#endif
                        captureRecap(completedNaturally: true)
                        showRecap = true
                        return
                    }
                    // Start next exercise phase (exercise or rep-based)
                    if exercises[currentExerciseIndex].isTimeBased {
                        isResting = false
                        startCurrentPhase()
                    } else {
                        isResting = false
                        timeRemaining = 0
#if canImport(WatchConnectivity)
                        sendStateToWatch()
#endif
                    }
                }
            }
        }
    }
    
    func advanceWorkout() {
        cancelPhaseEndNotification()
        // If the current exercise is rep-based, tapping "Reps Complete" should start that exercise's rest
        if !currentExercise.isTimeBased {
            if currentSet < currentExercise.sets {
                // More sets remain for this rep-based exercise: start its rest (same exercise)
                isResting = true
                startCurrentPhase()
            } else {
                // Finished last set of this rep-based exercise
                if currentExercise.restDuration > 0 {
                    // Do this exercise's rest first, then timerExpired() will advance to next exercise
                    isResting = true
                    startCurrentPhase()
                } else {
                    // No rest for this exercise; advance immediately
                    currentSet = 1
                    currentExerciseIndex += 1
                    if currentExerciseIndex >= exercises.count {
                        isCompleted = true
                        timeRemaining = 0
#if canImport(WatchConnectivity)
                        sendStateToWatch()
#endif
                        captureRecap(completedNaturally: true)
                        showRecap = true
                        return
                    }
                    if exercises[currentExerciseIndex].isTimeBased {
                        isResting = false
                        startCurrentPhase()
                    } else {
                        isResting = false
                        timeRemaining = 0
                    }
                }
            }
            return
        }

        // Time-based current exercise shouldn't reach here via the button normally,
        // but keep prior behavior as fallback: rest belongs to the SAME exercise
        if currentSet < currentExercise.sets {
            isResting = true
            startCurrentPhase()
        } else {
            if currentExercise.restDuration > 0 {
                isResting = true
                startCurrentPhase()
            } else {
                currentSet = 1
                currentExerciseIndex += 1
                if currentExerciseIndex >= exercises.count {
                    isCompleted = true
                    timeRemaining = 0
#if canImport(WatchConnectivity)
                    sendStateToWatch()
#endif
                    captureRecap(completedNaturally: true)
                    showRecap = true
                    return
                }
                if exercises[currentExerciseIndex].isTimeBased {
                    isResting = false
                    startCurrentPhase()
                } else {
                    isResting = false
                    timeRemaining = 0
                }
            }
        }
    }
    
    func repsCompleteTapped() {
        // immediate advance for rep-based exercises with undo capture
        guard !currentExercise.isTimeBased else { return }
        let prevExerciseIndex = currentExerciseIndex
        let prevSet = currentSet
        let prevWasResting = isResting
        // Determine whether this tap will advance to next exercise immediately (no rest)
        let willAdvanceExercise: Bool = {
            if currentSet < currentExercise.sets { return false }
            if currentExercise.restDuration > 0 { return false }
            return true
        }()
        advanceWorkout()
#if canImport(WatchConnectivity)
        sendStateToWatch()
#endif
        undoAction = WorkoutUndoAction(exerciseIndex: prevExerciseIndex, setBefore: prevSet, wasResting: prevWasResting, advancedExercise: willAdvanceExercise)
        withAnimation { showUndoToast = true }
        // Auto-hide after 4 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation { showUndoToast = false }
        }
    }

    func undoLastAction() {
        guard let action = undoAction else { return }
        cancelPhaseEndNotification()
        // Revert to the captured state
        currentExerciseIndex = action.exerciseIndex
        currentSet = action.setBefore
        isResting = false
        isCompleted = false

        // For rep-based, return to pre-rest state (no active timer)
        timeRemaining = 0
        // Clear undo and hide toast
        undoAction = nil
        withAnimation { showUndoToast = false }
    }
    
    func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
#if canImport(UIKit)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var healthKitMetricsView: some View {
        VStack(spacing: 12) {
            Text("Health Metrics")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 20) {
                heartRateMetric
                
                Divider()
                    .frame(height: 60)
                
                caloriesMetric
            }
        }
        .padding()
        .background(Color(uiColor: .systemGray6))
        .cornerRadius(16)
    }
    
    private var heartRateMetric: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                Text("Heart Rate")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            if healthKitManager.heartRate > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(Int(healthKitManager.heartRate))")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("BPM")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("--")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    private var caloriesMetric: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                Text("Calories")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            if healthKitManager.activeCalories > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(Int(healthKitManager.activeCalories))")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("CAL")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("--")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var awakeButton: some View {
        Button(action: { keepScreenAwake.toggle() }) {
            HStack {
                Image(systemName: keepScreenAwake ? "bolt.fill" : "bolt.slash")
                Text(keepScreenAwake ? "Awake On" : "Awake Off")
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(keepScreenAwake ? Color.green : Color.gray)
            .cornerRadius(12)
        }
    }
    
    private var backgroundAudioButton: some View {
        Button(action: { enableBackgroundAudio.toggle() }) {
            HStack {
                Image(systemName: enableBackgroundAudio ? "speaker.wave.2.fill" : "speaker.slash")
                Text(enableBackgroundAudio ? "BG Audio On" : "BG Audio Off")
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(enableBackgroundAudio ? Color.green : Color.gray)
            .cornerRadius(12)
        }
    }
#endif

    private var pauseResumeButton: some View {
        Button(action: {
            if isPaused {
                // RESUMING: recalculate phaseEndDate from stored remaining time
                if let remaining = pausedTimeRemaining {
                    phaseEndDate = Date().addingTimeInterval(remaining)
                    timeRemaining = remaining
                    pausedTimeRemaining = nil
                    schedulePhaseEndNotification(in: remaining)
                }
                isPaused = false
            } else {
                // PAUSING: capture current remaining time
                let remaining = max(0, phaseEndDate.timeIntervalSince(Date()))
                pausedTimeRemaining = remaining
                timeRemaining = remaining
                isPaused = true
                cancelPhaseEndNotification()
            }
#if canImport(WatchConnectivity)
            WatchConnectivityManager.shared.sendWorkoutCommand(isPaused ? .pause : .resume)
            sendStateToWatch()
#endif
        }) {
            HStack {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                Text(isPaused ? "Resume" : "Pause")
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.orange)
            .cornerRadius(12)
        }
    }

    private var cancelButton: some View {
        Button(action: { showCancelConfirmation = true }) {
            HStack {
                Image(systemName: "xmark.circle.fill")
                Text("Cancel")
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.red)
            .cornerRadius(12)
        }
    }
    
#if canImport(UIKit)
    private func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? audioSession.setActive(true, options: [])
    }
#endif
    
#if canImport(UIKit)
    private func startBackgroundAudioLoop() {
        guard !isBackgroundLoopRunning else { return }
        let sampleRate: Double = 44100
        let durationSeconds: Double = 1.0
        let frames = AVAudioFrameCount(sampleRate * durationSeconds)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        do {
            if !audioEngine.attachedNodes.contains(backgroundPlayerNode) {
                audioEngine.attach(backgroundPlayerNode)
                audioEngine.connect(backgroundPlayerNode, to: audioEngine.mainMixerNode, format: format)
            }
            if !audioEngine.isRunning {
                try audioEngine.start()
            }
        } catch {
            print("Audio engine start failed: \(error)")
            return
        }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        buffer.frameLength = frames
        if let channel = buffer.floatChannelData?[0] {
            // Fill with very low-amplitude noise to keep the session alive
            let count = Int(buffer.frameLength)
            for i in 0..<count { channel[i] = 0.00001 * ((i % 2 == 0) ? 1.0 : -1.0) }
        }
        backgroundPlayerNode.play()
        backgroundPlayerNode.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
        isBackgroundLoopRunning = true
    }

    private func stopBackgroundAudioLoop() {
        guard isBackgroundLoopRunning else { return }
        backgroundPlayerNode.stop()
        isBackgroundLoopRunning = false
    }
#endif
    
#if canImport(UserNotifications)
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    
    func schedulePhaseEndNotification(in interval: TimeInterval) {
        guard interval > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = isResting ? "Rest Complete" : "Timer Complete"
        content.body = isResting ? "Time to start the next set." : (currentExercise.isTimeBased ? "Move to rest or next exercise." : "")
        content.sound = UNNotificationSound.default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: "exercisePhaseEnd", content: content, trigger: trigger)

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["exercisePhaseEnd"])
        center.add(request)
    }
    
    func cancelPhaseEndNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["exercisePhaseEnd"])
    }
#else
    func requestNotificationPermission() {}
    func schedulePhaseEndNotification(in interval: TimeInterval) {}
    func cancelPhaseEndNotification() {}
#endif

    private func finishWorkoutAndExit() {
        // Centralized teardown and navigation back to builder
        isPaused = true
        isCompleted = true
        isResting = false
        cancelPhaseEndNotification()
#if canImport(UIKit)
        stopBackgroundAudioLoop()
#endif
        if audioEngine.isRunning { audioEngine.stop() }
#if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = false
#endif
        DispatchQueue.main.async {
            isActive = false
        }
    }
    
    /// Plays a rising three-tone celebration sound for workout completion.
    /// Uses AVAudioPlayer with an in-memory WAV so it's independent of the shared audioEngine.
    func playCompletionSound() {
        let sampleRate: Int = 44100
        let bitsPerSample: Int = 16
        let numChannels: Int = 1

        // Three ascending tones: C6, E6, G6 — each ~0.18s with brief gaps
        let toneLength = Int(Double(sampleRate) * 0.18)
        let gapLength = Int(Double(sampleRate) * 0.04)
        let totalFrames = toneLength * 3 + gapLength * 2

        // Generate 16-bit PCM samples
        let frequencies: [Double] = [1047.0, 1319.0, 1568.0]
        let amplitude: Double = 0.4
        var pcmData = [Int16](repeating: 0, count: totalFrames)
        var offset = 0
        for (noteIndex, freq) in frequencies.enumerated() {
            for i in 0..<toneLength {
                let envelope = min(1.0, min(Double(i) / 300, Double(toneLength - i) / 300))
                let phase = Double(i) * freq / Double(sampleRate)
                pcmData[offset + i] = Int16(sin(phase * 2 * .pi) * amplitude * envelope * Double(Int16.max))
            }
            offset += toneLength
            if noteIndex < 2 {
                offset += gapLength // already zeroed
            }
        }

        // Build a minimal WAV file in memory
        let dataSize = totalFrames * numChannels * (bitsPerSample / 8)
        var wav = Data()
        wav.append(contentsOf: "RIFF".utf8)
        wav.append(withUnsafeBytes(of: UInt32(36 + dataSize).littleEndian) { Data($0) })
        wav.append(contentsOf: "WAVE".utf8)
        wav.append(contentsOf: "fmt ".utf8)
        wav.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })       // chunk size
        wav.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })        // PCM
        wav.append(withUnsafeBytes(of: UInt16(numChannels).littleEndian) { Data($0) })
        wav.append(withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Data($0) })
        let byteRate = sampleRate * numChannels * (bitsPerSample / 8)
        wav.append(withUnsafeBytes(of: UInt32(byteRate).littleEndian) { Data($0) })
        let blockAlign = numChannels * (bitsPerSample / 8)
        wav.append(withUnsafeBytes(of: UInt16(blockAlign).littleEndian) { Data($0) })
        wav.append(withUnsafeBytes(of: UInt16(bitsPerSample).littleEndian) { Data($0) })
        wav.append(contentsOf: "data".utf8)
        wav.append(withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Data($0) })
        pcmData.withUnsafeBufferPointer { wav.append(UnsafeBufferPointer(start: UnsafeRawPointer($0.baseAddress!).assumingMemoryBound(to: UInt8.self), count: dataSize)) }

        do {
            let player = try AVAudioPlayer(data: wav)
            completionSoundPlayer = player  // retain
            player.play()
        } catch {
            print("Completion sound failed: \(error)")
        }
    }

    func playSound() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 22050)!
        buffer.frameLength = 22050

        let channels = UnsafeBufferPointer(start: buffer.floatChannelData, count: Int(format.channelCount))
        let samples = UnsafeMutableBufferPointer(start: channels[0], count: Int(buffer.frameLength))

        for i in 0..<Int(buffer.frameLength) {
            let frequency: Float = 880.0
            let amplitude: Float = 0.3
            let phase = Float(i) * frequency / Float(format.sampleRate)
            samples[i] = sin(phase * 2 * .pi) * amplitude
        }

        let playerNode = AVAudioPlayerNode()
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)

        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
            } catch {
                print("Audio engine start failed: \(error)")
                return
            }
        }
        playerNode.play()
        playerNode.scheduleBuffer(buffer, at: nil, options: []) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                playerNode.stop()
            }
        }
    }
}

struct ExerciseDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    
    var exercises: [Exercise]
    
    init(exercises: [Exercise]) {
        self.exercises = exercises
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        exercises = try JSONDecoder().decode([Exercise].self, from: data)
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder().encode(exercises)
        return FileWrapper(regularFileWithContents: data)
    }
}

#Preview {
    ExerciseListView()
}
