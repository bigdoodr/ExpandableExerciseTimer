import SwiftUI
import AVFoundation
#if os(iOS)
import UIKit
import UserNotifications
#endif
import UniformTypeIdentifiers
internal import Combine

@main
struct ExerciseTimerApp: App {
    var body: some Scene {
        WindowGroup {
            ExerciseListView()
        }
    }
}

struct Exercise: Identifiable, Codable {
    var id = UUID()
    var name: String = ""
    var isTimeBased: Bool = true
    var sets: Int = 1
    var exerciseDuration: TimeInterval = 30
    var restDuration: TimeInterval = 10
}

struct ExerciseListView: View {
    @State private var exercises: [Exercise] = [Exercise()]
    @State private var isWorkoutActive = false
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var exportURL: URL?
#if os(iOS)
    @State private var keepScreenAwake = false
#endif
    
    var body: some View {
        NavigationStack {
#if os(iOS)
            if isWorkoutActive {
                WorkoutView(exercises: exercises, isActive: $isWorkoutActive, keepScreenAwake: $keepScreenAwake)
            } else {
                builderView
            }
#else
            if isWorkoutActive {
                WorkoutView(exercises: exercises, isActive: $isWorkoutActive)
            } else {
                builderView
            }
#endif
        }
    }
    
    private var builderView: some View {
        List {
            Section {
                ForEach(Array(exercises.enumerated()), id: \.element.id) { index, _ in
                    ExerciseEntryView(exercise: $exercises[index])
                }
                .onMove { indices, newOffset in
                    exercises.move(fromOffsets: indices, toOffset: newOffset)
                }
                .onDelete { indexSet in
                    exercises.remove(atOffsets: indexSet)
                }
            }

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

#if os(iOS)
            Section {
                Toggle(isOn: $keepScreenAwake) {
                    HStack {
                        Image(systemName: keepScreenAwake ? "moon.zzz.fill" : "moon.zzz")
                        Text("Keep Screen Awake")
                    }
                }
                .toggleStyle(.switch)
            }
#endif
            Section {
                Button(action: { isWorkoutActive = true }) {
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
                Button(action: { exercises = [Exercise()] }) { Image(systemName: "arrow.counterclockwise") }
                    .accessibilityLabel("Reset")
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            importExercises(result)
        }
        .fileExporter(isPresented: $showingExporter, document: ExerciseDocument(exercises: exercises), contentType: .json, defaultFilename: "exercises.json") { result in
            if case .success = result { exportURL = nil }
        }
    }
    
    func exportExercises() {
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
        } catch {
            print("Failed to import: \(error)")
        }
    }
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
#if os(iOS)
    @Binding var keepScreenAwake: Bool
#endif
    
    @State private var currentExerciseIndex = 0
    @State private var currentSet = 1
    @State private var isResting = false
    @State private var isPaused = false
    @State private var timeRemaining: TimeInterval = 0
    @State private var phaseEndDate: Date = .now
    @State private var showingRepCompletion = false
    @State private var showingCompletion = false
    @State private var isCompleted = false
    @State private var isExiting = false
    
    let audioEngine = AVAudioEngine()
    // Removed silentPlayer property
    
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
    
    var body: some View {
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
                            showingRepCompletion = true
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
#if os(iOS)
                // Two-row layout in compact width: first row Pause/Cancel, second row Awake
                Group {
                    if horizontalSizeClass == .compact {
                        VStack(spacing: 12) {
                            HStack(spacing: 16) {
                                pauseResumeButton
                                cancelButton
                            }
                            HStack(spacing: 16) {
                                awakeButton
                            }
                        }
                    } else {
                        HStack(spacing: 16) {
                            pauseResumeButton
                            cancelButton
                            awakeButton
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
            if !isExiting && !isCompleted && !showingCompletion && !isPaused && (currentExercise.isTimeBased || isResting) {
                let now = Date()
                timeRemaining = max(0, phaseEndDate.timeIntervalSince(now))
                if timeRemaining <= 0 {
                    timerExpired()
                }
            }
        }
        .onAppear {
#if os(iOS)
            configureAudioSession()
#endif
            requestNotificationPermission()
            startCurrentPhase()
#if os(iOS)
            UIApplication.shared.isIdleTimerDisabled = keepScreenAwake
#endif
            // Removed startBackgroundAudioLoop() call
        }
        .alert("Reps Complete?", isPresented: $showingRepCompletion) {
            Button("Yes", action: advanceWorkout)
            Button("Cancel", role: .cancel) {}
        }
        .alert("Workout Complete!", isPresented: $showingCompletion) {
            Button("Done") {
                isExiting = true
                showingCompletion = false
#if os(iOS)
                UIApplication.shared.isIdleTimerDisabled = false
#endif
                DispatchQueue.main.async {
                    isActive = false
                }
            }
        } message: {
            Text("Great job! You've completed all exercises.")
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // Recompute remaining time from end date when app becomes active
                timeRemaining = max(0, phaseEndDate.timeIntervalSince(.now))
            }
        }
#if os(iOS)
        .onChange(of: keepScreenAwake) { _, newValue in
            UIApplication.shared.isIdleTimerDisabled = newValue
        }
#endif
        .onDisappear {
            cancelPhaseEndNotification()
            if audioEngine.isRunning { audioEngine.stop() }
#if os(iOS)
            UIApplication.shared.isIdleTimerDisabled = false
#endif
            // Removed stopBackgroundAudioLoop() call
        }
    }
    
    private func beginExit() {
        // Freeze UI and dismiss any modals
        isExiting = true
        isPaused = true
        isCompleted = true
        isResting = false
        showingCompletion = false
        showingRepCompletion = false
        // Stop notifications and audio synchronously
        cancelPhaseEndNotification()
        if audioEngine.isRunning { audioEngine.stop() }
        // Removed stopBackgroundAudioLoop() call
#if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = false
#endif
        // Flip navigation on next runloop tick
        DispatchQueue.main.async {
            isActive = false
        }
    }
    
    func startCurrentPhase() {
        if isCompleted { return }
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
                    showingCompletion = true
                    return
                }
                // Start next exercise phase
                if exercises[currentExerciseIndex].isTimeBased {
                    startCurrentPhase()
                } else {
                    timeRemaining = 0
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
                        showingCompletion = true
                        return
                    }
                    // Start next exercise phase (exercise or rep-based)
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
                        showingCompletion = true
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
                    showingCompletion = true
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
    
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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
#endif

    private var pauseResumeButton: some View {
        Button(action: { isPaused.toggle() }) {
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
        Button(action: { beginExit() }) {
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
    
#if os(iOS)
    private func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? audioSession.setActive(true, options: [])
    }
#endif
    
    // Removed startBackgroundAudioLoop() function
    
    // Removed stopBackgroundAudioLoop() function
    
#if os(iOS)
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
        if audioEngine.isRunning { audioEngine.stop() }
#if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = false
#endif
        DispatchQueue.main.async {
            isActive = false
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

