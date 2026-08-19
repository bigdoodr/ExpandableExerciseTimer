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
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif
import UniformTypeIdentifiers
internal import Combine

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
#if os(iOS)
    @State private var enableHealthKitTracking = false
    @State private var selectedActivityType: WorkoutActivityOption = .functionalStrengthTraining
#endif
    @State private var showingResetConfirm = false
    @State private var savedRoutines: [Routine] = []
    @State private var showRoutineSheet = false
    @State private var showSaveRoutineAlert = false
    @State private var newRoutineName = ""
#if canImport(WatchConnectivity)
    @State private var isSearchingForWatch = false
#endif
    @State private var showOnboarding = false
    @State private var onboardingMode: OnboardingView.Mode = .full
    @Environment(\.scenePhase) private var scenePhase

    private let exercisesDefaultsKey = "savedExercises"
    private let savedRoutinesKey = "savedRoutines"
    private let pendingRoutineKey = "pendingRoutineStart"
    private let hasSeenOnboardingKey = "hasSeenOnboarding"
    private let lastSeenAppVersionKey = "lastSeenAppVersion"

    private var currentAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    /// Shows the full guide on first launch, or a condensed "What's New" pass after an app update.
    private func presentOnboardingIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: hasSeenOnboardingKey) else {
            onboardingMode = .full
            showOnboarding = true
            return
        }
        if defaults.string(forKey: lastSeenAppVersionKey) != currentAppVersion {
            onboardingMode = .whatsNew
            showOnboarding = true
        }
    }

    private func markOnboardingSeen() {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: hasSeenOnboardingKey)
        defaults.set(currentAppVersion, forKey: lastSeenAppVersionKey)
    }

    /// HealthKit params forwarded to WatchSearchView (which launches the watch app)
    private var watchSearchHealthKitEnabled: Bool {
#if os(iOS)
        enableHealthKitTracking
#else
        false
#endif
    }

    private var watchSearchActivityType: String? {
#if os(iOS)
        enableHealthKitTracking ? selectedActivityType.rawValue : nil
#else
        nil
#endif
    }
    
    var body: some View {
        NavigationStack {
#if canImport(WatchConnectivity)
            if isWorkoutActive {
                workoutViewForPlatform
            } else {
                builderView
                    .onChange(of: connectivity.commandSequence) { _, _ in
                        handleWatchCommand(connectivity.receivedCommand)
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
        #if os(iOS)
        WorkoutView(
            exercises: exercises,
            isActive: $isWorkoutActive,
            keepScreenAwake: $keepScreenAwake,
            enableBackgroundAudio: $enableBackgroundAudio,
            healthKitEnabled: enableHealthKitTracking,
            activityType: selectedActivityType
        )
        #else
        WorkoutView(
            exercises: exercises,
            isActive: $isWorkoutActive,
            healthKitEnabled: false,
            activityType: .functionalStrengthTraining
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
#if os(iOS)
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
                Button(action: { showRoutineSheet = true }) { Image(systemName: "folder") }
                    .accessibilityLabel("Routines")
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
            loadSavedRoutines()
            checkPendingRoutine()
            presentOnboardingIfNeeded()
        }
        .onChange(of: exercises) { _, _ in
            persistExercises()
        }
#if os(iOS)
        .onChange(of: enableHealthKitTracking) { _, _ in
            persistExercises()
        }
        .onChange(of: selectedActivityType) { _, _ in
            persistExercises()
        }
#endif
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                checkPendingRoutine()
#if os(iOS) && canImport(HealthKit)
                if enableHealthKitTracking {
                    Task { await HealthKitWorkoutManager.shared.requestAuthorization() }
                }
#endif
            }
        }
        .sheet(isPresented: $showRoutineSheet) {
            RoutineManagerSheet(
                savedRoutines: $savedRoutines,
                currentExercises: exercises,
                onLoad: { loadedExercises in
                    exercises = loadedExercises
                    normalizeSupersets()
                    showRoutineSheet = false
                },
                onSaved: { updated in
                    savedRoutines = updated
                    persistRoutines()
                }
            )
        }
        .alert("Save as Routine", isPresented: $showSaveRoutineAlert) {
            TextField("Routine Name", text: $newRoutineName)
            Button("Save") {
                let trimmed = newRoutineName.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                let routine = Routine(name: trimmed, exercises: exercises)
                savedRoutines.append(routine)
                persistRoutines()
                newRoutineName = ""
            }
            Button("Cancel", role: .cancel) { newRoutineName = "" }
        }
#if canImport(WatchConnectivity)
        .fullScreenCover(isPresented: $isSearchingForWatch) {
            NavigationStack {
                WatchSearchView(
                    exercises: exercises,
                    isPresented: $isSearchingForWatch,
                    isWorkoutActive: $isWorkoutActive,
                    healthKitEnabled: watchSearchHealthKitEnabled,
                    activityType: watchSearchActivityType
                )
                .environmentObject(connectivity)
            }
        }
#endif
        .sheet(isPresented: $showOnboarding, onDismiss: {
            markOnboardingSeen()
        }) {
            OnboardingView(mode: onboardingMode)
        }
    }
    
    @ViewBuilder
    private var exerciseListSection: some View {
        Section {
            ForEach(Array(exercises.indices), id: \.self) { index in
                let isAnchor = index + 1 < exercises.count && exercises[index + 1].isSupersetContinuation
                ExerciseEntryRow(exercise: $exercises[index], isSupersetAnchor: isAnchor)
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if index > 0 {
                            Button {
                                exercises[index].isSupersetContinuation.toggle()
                                normalizeSupersets()
                            } label: {
                                Label(
                                    exercises[index].isSupersetContinuation ? "Unlink Superset" : "Superset",
                                    systemImage: exercises[index].isSupersetContinuation ? "link.badge.minus" : "link"
                                )
                            }
                            .tint(.purple)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            exercises.remove(at: index)
                            normalizeSupersets()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            var copy = exercises[index]
                            copy.id = UUID()
                            exercises.insert(copy, at: index + 1)
                        } label: {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                        }
                        .tint(.blue)
                    }
                    .contextMenu {
                        Button {
                            var copy = exercises[index]
                            copy.id = UUID()
                            exercises.insert(copy, at: index + 1)
                        } label: {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                        }
                        if index > 0 {
                            Button {
                                exercises[index].isSupersetContinuation.toggle()
                                normalizeSupersets()
                            } label: {
                                Label(
                                    exercises[index].isSupersetContinuation ? "Unlink Superset" : "Superset with Previous",
                                    systemImage: exercises[index].isSupersetContinuation ? "link.badge.minus" : "link"
                                )
                            }
                        }
                    }
            }
            .onMove { (indices: IndexSet, newOffset: Int) in
                exercises.move(fromOffsets: indices, toOffset: newOffset)
                normalizeSupersets()
            }
            .onDelete { (indexSet: IndexSet) in
                exercises.remove(atOffsets: indexSet)
                normalizeSupersets()
            }
        }
    }

    /// Enforces the superset invariants after any edit to the exercise list:
    /// - A superset marker on the first exercise means "linked to nothing" — not valid.
    /// - An exercise immediately followed by a superset continuation has no rest of its own
    ///   (rest lives on the chain's last exercise instead).
    private func normalizeSupersets() {
        guard exercises.indices.contains(0) else { return }
        if exercises[0].isSupersetContinuation {
            exercises[0].isSupersetContinuation = false
        }
        for index in exercises.indices {
            let isAnchor = index + 1 < exercises.count && exercises[index + 1].isSupersetContinuation
            if isAnchor && exercises[index].restDuration != 0 {
                exercises[index].restDuration = 0
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
    
#if os(iOS)
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
            Button(action: startOrSearchForWatch) {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Start Workout")
                }
                .font(.headline)
                .foregroundStyle(.green)
            }
            .buttonStyle(.plain)

            Button(action: { showSaveRoutineAlert = true }) {
                HStack {
                    Image(systemName: "folder.badge.plus")
                    Text("Save as Routine…")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Button(action: {
                onboardingMode = .full
                showOnboarding = true
            }) {
                HStack {
                    Image(systemName: "questionmark.circle")
                    Text("View Onboarding Guide")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func startOrSearchForWatch() {
#if canImport(WatchConnectivity)
        if WCSession.isSupported() {
#if canImport(HealthKit)
            WatchConnectivityManager.shared.updateContext(
                exercises: exercises,
                healthKitEnabled: enableHealthKitTracking,
                activityType: enableHealthKitTracking ? selectedActivityType.rawValue : nil
            )
#else
            WatchConnectivityManager.shared.updateContext(
                exercises: exercises,
                healthKitEnabled: false,
                activityType: nil
            )
#endif
            WatchConnectivityManager.shared.sendWorkoutCommand(.wake)
            isSearchingForWatch = true
            return
        }
#endif
        launchWorkoutDirectly()
    }

    private func launchWorkoutDirectly() {
#if canImport(WatchConnectivity) && canImport(HealthKit)
        let command = WorkoutCommand.start(
            exercises: exercises,
            healthKitEnabled: enableHealthKitTracking,
            activityType: enableHealthKitTracking ? selectedActivityType.rawValue : nil
        )
        WatchConnectivityManager.shared.sendWorkoutCommand(command)
#endif
        isWorkoutActive = true
    }
    
    // Helper row to reduce type-checker load
    private struct ExerciseEntryRow: View {
        @Binding var exercise: Exercise
        var isSupersetAnchor: Bool = false

        var body: some View {
            ExerciseEntryView(exercise: $exercise, isSupersetAnchor: isSupersetAnchor)
#if os(macOS)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
#endif
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
            normalizeSupersets()
            persistExercises()
        } catch {
            print("Failed to import: \(error)")
        }
    }
    
    private func loadSavedExercises() {
        if let data = UserDefaults.standard.data(forKey: exercisesDefaultsKey) {
            if let decoded = try? JSONDecoder().decode([Exercise].self, from: data) {
                exercises = decoded
                normalizeSupersets()
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

    private func loadSavedRoutines() {
        if let data = UserDefaults.standard.data(forKey: savedRoutinesKey),
           let decoded = try? JSONDecoder().decode([Routine].self, from: data) {
            savedRoutines = decoded
        }
    }

    private func persistRoutines() {
        if let data = try? JSONEncoder().encode(savedRoutines) {
            UserDefaults.standard.set(data, forKey: savedRoutinesKey)
        }
    }

    private func checkPendingRoutine() {
        guard let idStr = UserDefaults.standard.string(forKey: pendingRoutineKey),
              let uuid = UUID(uuidString: idStr),
              let routine = savedRoutines.first(where: { $0.id == uuid }) else { return }
        UserDefaults.standard.removeObject(forKey: pendingRoutineKey)
        exercises = routine.exercises
        normalizeSupersets()
#if canImport(WatchConnectivity)
        isSearchingForWatch = true
#else
        isWorkoutActive = true
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
            normalizeSupersets()
#if canImport(WatchConnectivity)
            isSearchingForWatch = false
#endif
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
    /// True when the *next* exercise in the list continues a superset with this one — meaning this exercise has no rest of its own.
    var isSupersetAnchor: Bool = false
    @State private var isExpanded = false

    /// True when this exercise starts a multi-exercise superset chain — it owns the chain's repeat count
    /// instead of its own Number of Sets.
    private var isChainHead: Bool {
        isSupersetAnchor && !exercise.isSupersetContinuation
    }

    /// True for every exercise in a chain except the first — its own Number of Sets doesn't apply,
    /// since chain members each perform one set per round.
    private var isGroupedNonHead: Bool {
        exercise.isSupersetContinuation
    }

    @ViewBuilder
    private var supersetBadge: some View {
        if exercise.isSupersetContinuation {
            Image(systemName: "arrow.turn.down.right")
                .font(.caption)
                .foregroundStyle(.purple)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
#if os(macOS)
            HStack(spacing: 0) {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.tertiary)
                    .font(.callout)
                    .frame(width: 20)
                HStack {
                    supersetBadge
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    Text(exercise.name.isEmpty ? "New Exercise" : exercise.name)
                        .font(.headline)
                    Spacer()
                }
                .foregroundStyle(.primary)
                .padding()
                .padding(.leading, exercise.isSupersetContinuation ? 16 : 0)
                .background(exercise.isSupersetContinuation ? Color.purple.opacity(0.12) : Color(nsColor: .windowBackgroundColor))
                .cornerRadius(12)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation {
                        isExpanded.toggle()
                    }
                }
            }
#else
            HStack {
                supersetBadge
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                Text(exercise.name.isEmpty ? "New Exercise" : exercise.name)
                    .font(.headline)
                Spacer()
            }
            .foregroundStyle(.primary)
            .padding()
            .padding(.leading, exercise.isSupersetContinuation ? 16 : 0)
#if os(iOS)
            .background(exercise.isSupersetContinuation ? Color.purple.opacity(0.12) : Color(uiColor: .systemGray6))
#else
            .background(exercise.isSupersetContinuation ? Color.purple.opacity(0.12) : Color.gray.opacity(0.15))
#endif
            .cornerRadius(12)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation {
                    isExpanded.toggle()
                }
            }
#endif
            
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

                    if isChainHead {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "repeat")
                                    .font(.caption)
                                    .foregroundStyle(.purple)
                                Text("Repeat Chain")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Stepper("\(exercise.chainRepeatCount) round\(exercise.chainRepeatCount == 1 ? "" : "s")", value: $exercise.chainRepeatCount, in: 1...99)
                            Text("Each linked exercise performs one set per round.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else if isGroupedNonHead {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Number of Sets")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("Performed once per round — set the round count on the first exercise in this chain.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Number of Sets")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Stepper("\(exercise.sets)", value: $exercise.sets, in: 1...99)
                        }
                    }

                    if exercise.isTimeBased {
                        DurationPickerView(title: "Exercise Duration", duration: $exercise.exerciseDuration)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Target Reps")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if exercise.targetReps != nil {
                                Stepper(
                                    "\(exercise.targetReps ?? 10) reps",
                                    value: Binding(
                                        get: { exercise.targetReps ?? 10 },
                                        set: { exercise.targetReps = $0 }
                                    ),
                                    in: 1...999
                                )
                                Button("Clear") { exercise.targetReps = nil }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Button("Set target reps") { exercise.targetReps = 10 }
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                        }
                    }

                    if isSupersetAnchor {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Rest Duration")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                Image(systemName: "link")
                                    .foregroundStyle(.purple)
                                Text("No rest — continues straight into the linked superset exercise.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.purple.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    } else {
                        DurationPickerView(title: "Rest Duration", duration: $exercise.restDuration)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Weight")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if exercise.weight != nil {
                            HStack(spacing: 8) {
                                TextField("0", value: Binding(
                                    get: { exercise.weight ?? 0 },
                                    set: { exercise.weight = max(0, $0) }
                                ), format: .number)
#if os(iOS)
                                .keyboardType(.decimalPad)
#endif
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 90)

                                Picker("Unit", selection: $exercise.weightUnit) {
                                    Text("LB").tag(WeightUnit.lbs)
                                    Text("KG").tag(WeightUnit.kg)
                                }
                                .pickerStyle(.segmented)
                                .frame(maxWidth: 80)

                                Spacer()

                                Button("Clear") { exercise.weight = nil }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .buttonStyle(.plain)
                            }
                        } else {
                            Button("Add weight") { exercise.weight = 0 }
                                .font(.caption)
                                .foregroundStyle(.blue)
                                .buttonStyle(.plain)
                        }
                    }
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
#if canImport(HealthKit) && !os(macOS)
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
    @State private var sessionElapsed: TimeInterval = 0
    /// HR zone breakdown forwarded from the watch, when the watch (not the iPhone) owns the HealthKit session
    @State private var recapZoneSummary: [HRZoneRecapEntry] = []
#if os(iOS) && canImport(HealthKit) && canImport(WatchConnectivity)
    @State private var iPhoneOwnsHKSession = false
#endif
    
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

    /// The superset group containing the current exercise — a single-element range for a lone exercise.
    var currentGroupRange: ClosedRange<Int> {
        let safeIndex = min(max(0, currentExerciseIndex), max(0, exercises.count - 1))
        return exercises.supersetGroupRange(containing: safeIndex)
    }

    var displayExerciseNumber: Int {
        guard !exercises.isEmpty else { return 0 }
        let idx = min(max(0, currentExerciseIndex), max(0, exercises.count - 1))
        return idx + 1
    }
    var totalExercises: Int { exercises.count }
    
    var upNextText: String {
        guard !isCompleted else { return "" }
        let groupRange = currentGroupRange
        let roundCount = exercises.roundCount(for: groupRange)

        func nextExerciseAfterGroupText() -> String {
            let nextIndex = groupRange.upperBound + 1
            if nextIndex >= exercises.count {
                return "Up Next: Workout Complete"
            }
            let next = exercises[nextIndex]
            let nextName = next.name.isEmpty ? "Exercise \(nextIndex + 1)" : next.name
            let nextSummary = next.quickSummary
            return "Up Next: \(nextName)\(nextSummary.isEmpty ? "" : " · \(nextSummary)")"
        }

        if isResting {
            // Rest only ever happens after the last exercise in a group finishes a round.
            let nextSet = currentSet + 1
            if nextSet <= roundCount {
                // Another round — loop back to the first exercise in the group.
                let first = exercises[groupRange.lowerBound]
                let name = first.name.isEmpty ? "Exercise \(groupRange.lowerBound + 1)" : first.name
                if first.isTimeBased {
                    return "Up Next: \(name) – Round \(nextSet)"
                } else {
                    return "Up Next: \(name) – Round \(nextSet) (Reps)"
                }
            } else {
                return nextExerciseAfterGroupText()
            }
        } else if currentExerciseIndex < groupRange.upperBound {
            // More linked exercises remain this round — no rest before them.
            let nextIndex = currentExerciseIndex + 1
            let next = exercises[nextIndex]
            let nextName = next.name.isEmpty ? "Exercise \(nextIndex + 1)" : next.name
            let nextSummary = next.quickSummary
            return "Up Next: \(nextName)\(nextSummary.isEmpty ? "" : " · \(nextSummary)")"
        } else if currentSet < roundCount {
            // Last exercise in the group, but more rounds remain
            if currentExercise.restDuration > 0 {
                return "Up Next: Rest (\(formatTime(currentExercise.restDuration)))"
            } else {
                return "Up Next: Round \(currentSet + 1)"
            }
        } else {
            // Final round of the final exercise in the group
            if currentExercise.restDuration > 0 {
                return "Up Next: Rest (\(formatTime(currentExercise.restDuration)))"
            } else {
                return nextExerciseAfterGroupText()
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
                Text(formatTime(sessionElapsed))
                    .font(.title3)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    Text("Exercise \(displayExerciseNumber) of \(totalExercises)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Text(currentExercise.name.isEmpty ? "Exercise \(displayExerciseNumber)" : currentExercise.name)
                        .font(.largeTitle)
                        .bold()

                    Text(currentGroupRange.count > 1 ? "Round \(currentSet) of \(exercises.roundCount(for: currentGroupRange))" : "Set \(currentSet) of \(currentExercise.sets)")
                        .font(.title2)
                        .foregroundStyle(.secondary)

                    if let weight = currentExercise.weight {
                        Text(String(format: weight.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f \(currentExercise.weightUnit.rawValue)" : "%.1f \(currentExercise.weightUnit.rawValue)", weight))
                            .font(.title3)
                            .bold()
                            .foregroundStyle(.blue)
                    }

                    if !currentExercise.isTimeBased, let reps = currentExercise.targetReps {
                        Text("\(reps) reps")
                            .font(.title3)
                            .bold()
                            .foregroundStyle(.purple)
                    }
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

                        if let targetReps = currentExercise.targetReps {
                            Text("Target: \(targetReps) reps")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Complete your reps")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        
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
            sessionElapsed = Date().timeIntervalSince(workoutStartDate)
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
            workoutStartDate = Date()
            requestNotificationPermission()
            startCurrentPhase()
#if canImport(UIKit)
            UIApplication.shared.isIdleTimerDisabled = keepScreenAwake
#endif
#if os(iOS) && canImport(HealthKit) && canImport(WatchConnectivity)
            if healthKitEnabled && !connectivity.isWatchReachable {
                Task {
                    await healthKitManager.requestAuthorization()
                    if healthKitManager.isAuthorized {
                        let config = HealthKitWorkoutManager.workoutConfiguration(for: activityType.rawValue)
                        await healthKitManager.startWorkoutSession(with: config)
                        iPhoneOwnsHKSession = true
                    }
                }
            }
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
        .onChange(of: connectivity.commandSequence) { _, _ in
            handleWatchWorkoutCommand(connectivity.receivedCommand)
        }
#endif
        .onDisappear {
            cancelPhaseEndNotification()
#if canImport(UIKit)
            stopBackgroundAudioLoop()
#endif
#if canImport(HealthKit) && !os(macOS)
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
                        
                        let totalSets = exercises.indices.reduce(0) { $0 + effectiveSets(at: $1) }
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
                        let zoneEntries = recapZoneEntries
                        if !zoneEntries.isEmpty {
                            let totalZoneTime = zoneEntries.reduce(0.0) { $0 + $1.duration }
                            Divider()
                            Text("Heart Rate Zones")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            ForEach(zoneEntries, id: \.zoneIndex) { entry in
                                if entry.zoneIndex > 0 { Divider() }
                                let zoneNum = entry.zoneIndex + 1
                                let color = hrZoneColor(zoneNum)
                                let minBPM = entry.minBPM.map { Int($0) }
                                let maxBPM = entry.maxBPM.map { Int($0) }
                                let bpmLabel: String = {
                                    switch (minBPM, maxBPM) {
                                    case (nil, let hi?): return "<\(hi) bpm"
                                    case (let lo?, nil): return ">\(lo) bpm"
                                    case (let lo?, let hi?): return "\(lo)–\(hi) bpm"
                                    default: return ""
                                    }
                                }()
                                VStack(spacing: 6) {
                                    HStack(spacing: 10) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(color)
                                            .frame(width: 4, height: 20)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Zone \(zoneNum)")
                                                .font(.subheadline)
                                            if !bpmLabel.isEmpty {
                                                Text(bpmLabel)
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        Text(formatTime(entry.duration))
                                            .font(.subheadline)
                                            .bold()
                                            .foregroundStyle(entry.duration > 0 ? .primary : .secondary)
                                            .monospacedDigit()
                                    }
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(Color.secondary.opacity(0.2))
                                                .frame(height: 6)
                                            if totalZoneTime > 0 && entry.duration > 0 {
                                                RoundedRectangle(cornerRadius: 3)
                                                    .fill(color)
                                                    .frame(width: geo.size.width * CGFloat(entry.duration / totalZoneTime), height: 6)
                                            }
                                        }
                                    }
                                    .frame(height: 6)
                                }
                            }
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
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
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
    
    /// Effective "sets" for recap purposes: a lone exercise's own `sets`, or a chain member's round count.
    private func effectiveSets(at index: Int) -> Int {
        exercises.roundCount(for: exercises.supersetGroupRange(containing: index))
    }

    /// The HR zone breakdown to show in the recap: data forwarded from the watch (which owns the
    /// HealthKit session whenever a watch is involved), falling back to reading the iPhone's own
    /// finished workout when the iPhone recorded the session directly (no watch).
    private var recapZoneEntries: [HRZoneRecapEntry] {
#if canImport(WatchConnectivity)
        // Read from the connectivity manager — a @StateObject that outlives the recap branch —
        // rather than from view @State. The watch only sends .zoneSummary once its HealthKit
        // session has finished, which lands after showRecap flips and workoutContent (along
        // with the onChange that used to catch it) has left the view hierarchy.
        if !connectivity.completedZoneSummary.isEmpty { return connectivity.completedZoneSummary }
#endif
        if !recapZoneSummary.isEmpty { return recapZoneSummary }
#if canImport(HealthKit) && os(iOS)
        if #available(iOS 27.0, *),
           let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate),
           let zoneGroups = healthKitManager.finishedWorkout?.zoneGroupsByType,
           let zoneGroup = zoneGroups[hrType] {
            let bpmUnit = HKUnit.count().unitDivided(by: .minute())
            return zoneGroup.zoneDurations.enumerated().map { index, zoneDuration in
                HRZoneRecapEntry(
                    zoneIndex: index,
                    duration: zoneDuration.duration,
                    minBPM: zoneDuration.zone.minimum?.doubleValue(for: bpmUnit),
                    maxBPM: zoneDuration.zone.maximum?.doubleValue(for: bpmUnit)
                )
            }
        }
#endif
        return []
    }

    private func captureRecap(completedNaturally: Bool) {
        recapDuration = Date().timeIntervalSince(workoutStartDate)
        recapCompletedNaturally = completedNaturally

        if completedNaturally {
            recapExercisesCompleted = exercises.count
            recapSetsCompleted = exercises.indices.reduce(0) { $0 + effectiveSets(at: $1) }
        } else {
            recapExercisesCompleted = min(currentExerciseIndex + 1, exercises.count)
            // Count sets (rounds) completed in finished groups + the in-progress group
            var sets = 0
            let groupRange = currentGroupRange
            for i in 0..<groupRange.lowerBound {
                sets += effectiveSets(at: i)
            }
            for i in groupRange {
                if i < currentExerciseIndex {
                    // Already performed this round for this group member
                    sets += currentSet
                } else if i == currentExerciseIndex {
                    sets += max(0, currentSet - (isResting ? 0 : 1))
                } else {
                    // Hasn't performed the in-progress round yet, only prior ones
                    sets += max(0, currentSet - 1)
                }
            }
            recapSetsCompleted = sets
        }
        
#if canImport(HealthKit) && !os(macOS)
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
            
        case .healthData(let heartRate, let activeCalories, let hrZoneIndex):
            // Receive live health data forwarded from the watch
            healthKitManager.heartRate = heartRate
            healthKitManager.activeCalories = activeCalories
            healthKitManager.currentHRZoneIndex = hrZoneIndex
            // Accumulate for average calculation in recap
            if heartRate > 0 {
                heartRateReadings.append(heartRate)
            }
            // Mark as active so the metrics view shows
            if !healthKitManager.isWorkoutActive {
                healthKitManager.isWorkoutActive = true
            }

        case .zoneSummary(let zones):
            // Forwarded from the watch once it ends the HealthKit session it owns.
            recapZoneSummary = zones

        case .wake:
            break
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
#if os(iOS) && canImport(HealthKit) && canImport(WatchConnectivity)
        if iPhoneOwnsHKSession {
            iPhoneOwnsHKSession = false
            Task { await healthKitManager.endWorkout() }
        }
#endif
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
#if canImport(WatchConnectivity)
            sendStateToWatch()
#endif
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
            isResting = false
            advancePastRest(groupRange: currentGroupRange)
        } else {
            advancePastCompletedSet()
        }
    }

    /// Called when the current exercise's work phase finishes (a timer expiring, or a "Reps Complete" tap).
    /// Superset partners run back-to-back with no rest between them; rest only happens after the
    /// last exercise in the group finishes each round.
    private func advancePastCompletedSet() {
        let groupRange = currentGroupRange
        if currentExerciseIndex < groupRange.upperBound {
            // More linked exercises remain this round — move on immediately, no rest.
            currentExerciseIndex += 1
            isResting = false
            startCurrentPhase()
            return
        }

        // Finished the last exercise in the group for this round.
        if currentExercise.restDuration > 0 {
            isResting = true
            startCurrentPhase()
        } else {
            advancePastRest(groupRange: groupRange)
        }
    }

    /// Called once a between-round (or between-group) rest finishes, or immediately if there was none.
    /// Loops back to the first exercise in the group for another round, or advances past the group entirely.
    private func advancePastRest(groupRange: ClosedRange<Int>) {
        let roundCount = exercises.roundCount(for: groupRange)
        if currentSet < roundCount {
            // Another round remains — loop back to the first exercise in the group.
            currentSet += 1
            currentExerciseIndex = groupRange.lowerBound
        } else {
            // Finished all rounds for this group — advance past it entirely.
            currentSet = 1
            currentExerciseIndex = groupRange.upperBound + 1
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
        }
        isResting = false
        startCurrentPhase()
    }

    func advanceWorkout() {
        cancelPhaseEndNotification()
        advancePastCompletedSet()
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

    private func hrZoneColor(_ zone: Int) -> Color {
        switch zone {
        case 1: return .blue
        case 2: return .teal
        case 3: return .green
        case 4: return .orange
        default: return .red
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

                zoneMetric

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
                Text("BPM")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if healthKitManager.heartRate > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(Int(healthKitManager.heartRate))")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
            } else {
                Text("--")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var zoneMetric: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(healthKitManager.currentHRZoneIndex.map { hrZoneColor($0 + 1) } ?? .secondary)
                Text("Zone")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let zoneIndex = healthKitManager.currentHRZoneIndex {
                Text("Z\(zoneIndex + 1)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(hrZoneColor(zoneIndex + 1))
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
        let sampleRate: Double = 44100
        // C5 (523 Hz) — pleasant and clear without being harsh
        let frequency: Float = 523.0
        let amplitude: Float = 0.22
        let duration: Double = 0.22
        let frameCount = AVAudioFrameCount(sampleRate * duration)

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        let samples = UnsafeMutableBufferPointer(start: buffer.floatChannelData![0], count: Int(frameCount))
        for i in 0..<Int(frameCount) {
            // Hanning envelope: smooth attack and release, no click or pop
            let t = Double(i) / Double(frameCount - 1)
            let envelope = Float(0.5 * (1.0 - cos(2.0 * .pi * t)))
            let phase = Float(i) * frequency / Float(sampleRate)
            samples[i] = sin(phase * 2 * .pi) * amplitude * envelope
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                playerNode.stop()
            }
        }
    }
}

// MARK: - Routine Manager Sheet

struct RoutineManagerSheet: View {
    @Binding var savedRoutines: [Routine]
    let currentExercises: [Exercise]
    let onLoad: ([Exercise]) -> Void
    let onSaved: ([Routine]) -> Void

    @Environment(\.dismiss) private var dismiss

    private var pplRoutines: [PreloadedRoutine] {
        PreloadedRoutines.all.filter { $0.seriesName == "Perfect PPL Split" }
    }
    private var standaloneRoutines: [PreloadedRoutine] {
        PreloadedRoutines.all.filter { $0.seriesName == nil }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(pplRoutines) { routine in
                        NavigationLink {
                            PreloadedRoutineDetailView(routine: routine, onLoad: onLoad)
                        } label: {
                            PreloadedRoutineRow(routine: routine)
                        }
                    }
                } header: {
                    Text("Perfect PPL Split — Athlean-X")
                }

                if !standaloneRoutines.isEmpty {
                    Section("Other Routines") {
                        ForEach(standaloneRoutines) { routine in
                            NavigationLink {
                                PreloadedRoutineDetailView(routine: routine, onLoad: onLoad)
                            } label: {
                                PreloadedRoutineRow(routine: routine)
                            }
                        }
                    }
                }

                Section("My Routines") {
                    if savedRoutines.isEmpty {
                        Text("No saved routines yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(savedRoutines) { routine in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(routine.name)
                                        .font(.headline)
                                    Text("\(routine.exercises.count) exercise\(routine.exercises.count == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Load") { onLoad(routine.exercises) }
                                    .buttonStyle(.bordered)
                            }
                        }
                        .onDelete { indexSet in
                            savedRoutines.remove(atOffsets: indexSet)
                            onSaved(savedRoutines)
                        }
                    }
                }
            }
            .navigationTitle("Routines")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
            }
#else
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
#endif
        }
    }
}

private struct PreloadedRoutineRow: View {
    let routine: PreloadedRoutine

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 8)
                .fill(routine.accentColor)
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: routine.systemImage)
                        .foregroundStyle(.white)
                        .font(.title3)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(routine.name)
                    .font(.body)
                    .fontWeight(.medium)
                HStack(spacing: 6) {
                    Text(routine.source)
                    Text("·")
                    Text(routine.summaryLine)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct PreloadedRoutineDetailView: View {
    let routine: PreloadedRoutine
    let onLoad: ([Exercise]) -> Void

    private var isVideoSource: Bool {
        routine.sourceURL.contains("youtu")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(routine.source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(routine.name)
                        .font(.title2)
                        .fontWeight(.bold)
                    if !routine.routineDescription.isEmpty {
                        Text(routine.routineDescription)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if !routine.sourceURL.isEmpty, let url = URL(string: routine.sourceURL) {
                        Link(destination: url) {
                            Label(routine.sourceLinkLabel, systemImage: isVideoSource ? "play.rectangle.fill" : "doc.text.fill")
                                .font(.caption)
                                .foregroundStyle(routine.accentColor)
                        }
                        .padding(.top, 2)
                    }
                }
                .padding()
                .background(.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Exercises")
                        .font(.title3)
                        .fontWeight(.semibold)

                    ForEach(Array(routine.exercises.enumerated()), id: \.offset) { index, exercise in
                        let displaySets = routine.exercises.roundCount(for: routine.exercises.supersetGroupRange(containing: index))
                        PreloadedExerciseRow(index: index, exercise: exercise, displaySets: displaySets, accentColor: routine.accentColor)
                    }
                }

                Button {
                    onLoad(routine.exercises)
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Load Routine")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(routine.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            .padding()
        }
        .navigationTitle(routine.name)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}

private struct PreloadedExerciseRow: View {
    let index: Int
    let exercise: Exercise
    /// Sets to display: a lone exercise's own `sets`, or its superset chain's round count.
    let displaySets: Int
    let accentColor: Color

    private var repsLabel: String {
        guard !exercise.isTimeBased else {
            return "\(Int(exercise.exerciseDuration))s"
        }
        guard let reps = exercise.targetReps else { return "failure" }
        if let repsMax = exercise.targetRepsMax, repsMax != reps {
            return "\(reps)–\(repsMax)"
        }
        return "\(reps)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if exercise.isSupersetContinuation {
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 22, alignment: .trailing)
            } else {
                Text("\(index + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 22, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.subheadline)
                    .fontWeight(exercise.isSupersetContinuation ? .regular : .medium)
                if let notes = exercise.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text("\(displaySets) × \(repsLabel)")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(accentColor)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(exercise.isSupersetContinuation ? accentColor.opacity(0.08) : Color.gray.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.leading, exercise.isSupersetContinuation ? 16 : 0)
    }
}

// MARK: - Watch Search View

#if canImport(WatchConnectivity)
struct WatchSearchView: View {
    let exercises: [Exercise]
    @Binding var isPresented: Bool
    @Binding var isWorkoutActive: Bool
    var healthKitEnabled: Bool = false
    var activityType: String? = nil

    @EnvironmentObject private var connectivity: WatchConnectivityManager
    @State private var countdown = 30
    @State private var watchFound = false
    @State private var timedOut = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 130, height: 130)
                Image(systemName: watchFound ? "applewatch.radiowaves.left.and.right" : "applewatch")
                    .font(.system(size: 52))
                    .foregroundStyle(watchFound ? .green : .blue)
            }

            VStack(spacing: 10) {
                if timedOut && !watchFound {
                    Text("Apple Watch Not Found")
                        .font(.title2).bold()
                    Text("Make sure Exercise Timer is installed and open on your Apple Watch, then try again.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else if watchFound {
                    Text("Apple Watch Connected")
                        .font(.title2).bold()
                        .foregroundStyle(.green)
                    Text("Tap Start Workout on your Apple Watch to begin.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Searching for Apple Watch…")
                        .font(.title2).bold()
                    Text("Your Apple Watch should appear automatically. If not, open Exercise Timer on your Watch.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    if !timedOut {
                        ProgressView()
                            .padding(.top, 4)
                        Text("\(countdown)s")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 14) {
                Button(action: continueOnIPhone) {
                    Text(timedOut && !watchFound ? "Start on iPhone" : "Continue on iPhone")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(timedOut && !watchFound ? Color.blue : Color.gray.opacity(0.7))
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .navigationTitle("Starting Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { isPresented = false }
            }
        }
        .onAppear {
            watchFound = connectivity.isWatchReachable
            // If the watch app is already running, .wake tells it to prepare its HK session.
            // (sendMessage from iPhone→watch cannot LAUNCH the watch app — it only delivers
            // when the watch app is already reachable.)
            WatchConnectivityManager.shared.sendWorkoutCommand(.wake)
            // Actually launch the watch app. HKHealthStore.startWatchApp(with:) is the only
            // API that launches the watch app from the iPhone; it delivers the configuration
            // to WatchAppDelegate.handle(_:) on the watch.
            launchWatchApp()
        }
        .onChange(of: connectivity.isWatchReachable) { _, reachable in
            if reachable { watchFound = true }
        }
        .onChange(of: connectivity.commandSequence) { _, _ in
            if case .start(_, _, _) = connectivity.receivedCommand {
                isPresented = false
                isWorkoutActive = true
            }
        }
        .task {
            while countdown > 0 && !watchFound && !timedOut {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                countdown -= 1
            }
            if !watchFound { timedOut = true }
        }
    }

    private func continueOnIPhone() {
#if canImport(HealthKit)
        WatchConnectivityManager.shared.sendWorkoutCommand(
            .start(exercises: exercises, healthKitEnabled: healthKitEnabled, activityType: activityType)
        )
#endif
        isPresented = false
        isWorkoutActive = true
    }

    /// Launches the companion watch app on the paired Apple Watch.
    private func launchWatchApp() {
#if os(iOS) && canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let config = HealthKitWorkoutManager.workoutConfiguration(for: activityType)
        Task { @MainActor in
            // Ensure iPhone-side HealthKit authorization when tracking is on
            if healthKitEnabled {
                await HealthKitWorkoutManager.shared.requestAuthorization()
            }
            HealthKitWorkoutManager.shared.healthStore.startWatchApp(with: config) { success, error in
                if let error {
                    print("startWatchApp failed: \(error.localizedDescription)")
                } else if !success {
                    print("startWatchApp reported failure (watch app may not be installed)")
                }
            }
        }
#endif
    }
}
#endif

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
