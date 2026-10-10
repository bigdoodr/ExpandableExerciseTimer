import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(HealthKit)
import HealthKit
#endif
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// The builder screen for one session kind (Exercises or Timers): the editable list plus Start.
/// Hosted inside a `NavigationStack` provided by `RootTabView`.
struct SessionBuilderView: View {
    let kind: SessionKind
    @Binding var savedRoutines: [Routine]
    @Binding var loadRequest: RoutineLoadRequest?

    @State private var exercises: [Exercise] = [Exercise()]
    @State private var isWorkoutActive = false
    @State private var showingResetConfirm = false
    /// The saved routine `exercises` was loaded from, if any — mid-session reps/weight edits are
    /// written back to this routine (by exercise id) in addition to the builder. `nil` after Reset,
    /// import, or loading a preloaded (non-editable) routine, so those never get treated as edits
    /// to a saved routine that merely happens to share exercise ids.
    @State private var loadedRoutineID: Routine.ID?
    @State private var showSaveRoutineAlert = false
    @State private var newRoutineName = ""
    @State private var newRoutineCategory = ""
#if canImport(WatchConnectivity)
    @StateObject private var connectivity = WatchConnectivityManager.shared
    @State private var isSearchingForWatch = false
#endif
#if canImport(UIKit)
    // Persisted so a preference set in Settings sticks across app launches.
    @AppStorage("keepScreenAwake") private var keepScreenAwake = false
    @AppStorage("enableBackgroundAudio") private var enableBackgroundAudio = false
#endif
#if os(iOS)
    @AppStorage("workoutActivityType") private var workoutActivityTypeRaw = WorkoutActivityOption.functionalStrengthTraining.rawValue
    private var activityType: WorkoutActivityOption {
        WorkoutActivityOption(rawValue: workoutActivityTypeRaw) ?? .functionalStrengthTraining
    }
    private var activityTypeBinding: Binding<WorkoutActivityOption> {
        Binding(
            get: { activityType },
            set: { workoutActivityTypeRaw = $0.rawValue }
        )
    }
    /// HealthKit only ever tracks Exercises-tab workouts — Timers never record to Health.
    private var healthKitEnabled: Bool { kind == .workout }
#endif

    private var exercisesDefaultsKey: String { kind == .workout ? "savedExercises" : "savedTimers" }

    var body: some View {
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

    @ViewBuilder
    private var workoutViewForPlatform: some View {
        makeSessionView()
            .toolbar(.hidden, for: .tabBar)
    }

    #if os(iOS)
    private func makeSessionView() -> SessionView {
        var view = SessionView(
            kind: kind,
            exercises: exercises,
            isActive: $isWorkoutActive,
            keepScreenAwake: $keepScreenAwake,
            enableBackgroundAudio: $enableBackgroundAudio,
            healthKitEnabled: healthKitEnabled,
            activityType: activityType
        )
        view.onExerciseAdjusted = applyLiveAdjustment
        return view
    }
    #else
    private func makeSessionView() -> SessionView {
        var view = SessionView(
            kind: kind,
            exercises: exercises,
            isActive: $isWorkoutActive,
            healthKitEnabled: false,
            activityType: .functionalStrengthTraining
        )
        view.onExerciseAdjusted = applyLiveAdjustment
        return view
    }
    #endif

    private var builderView: some View {
        List {
            ExerciseListEditor(exercises: $exercises, kind: kind)
#if os(iOS)
            workoutTrackingSection
#endif
            startSection
        }
#if os(iOS)
        .listStyle(.insetGrouped)
        // Default List behavior dismisses the keyboard on any scroll, which competes with
        // (and can win against) a tap on a button below a focused field. Interactive-only
        // dismissal removes that competing gesture — see "intermittent tap failures" in the backlog.
        .scrollDismissesKeyboard(.interactively)
#else
        .listStyle(.inset)
#endif
        .navigationTitle(kind == .workout ? "Exercise Timer" : "Timers")
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            #endif
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Reset", systemImage: "arrow.counterclockwise") { showingResetConfirm = true }
            }
        }
        .alert("Reset \(kind.itemNamePlural)?", isPresented: $showingResetConfirm) {
            Button("Reset", role: .destructive) { exercises = [Exercise()]; loadedRoutineID = nil; persistExercises() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all \(kind.itemNamePlural.lowercased()) in the builder.")
        }
        .onAppear {
            if exercises.count == 1 && exercises.first?.name == "" && exercises.first?.isTimeBased == true && exercises.first?.sets == 1 && exercises.first?.exerciseDuration == 30 && exercises.first?.restDuration == 10 {
                loadSavedExercises()
            }
        }
        .onChange(of: exercises) { _, _ in
            persistExercises()
        }
        .onChange(of: loadRequest) { _, newValue in
            guard let request = newValue else { return }
            exercises = request.routine.exercises
            loadedRoutineID = request.isSavedRoutine ? request.routine.id : nil
            exercises.normalizeSupersets()
            persistExercises()
            if request.autoStart {
                startOrSearchForWatchConfirmed()
            }
            loadRequest = nil
        }
        .alert("Save as Routine", isPresented: $showSaveRoutineAlert) {
            TextField("Routine Name", text: $newRoutineName)
            TextField("Category (optional)", text: $newRoutineCategory)
            Button("Save") {
                let trimmed = newRoutineName.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                let trimmedCategory = newRoutineCategory.trimmingCharacters(in: .whitespaces)
                savedRoutines.append(Routine(name: trimmed, exercises: exercises, kind: kind, category: trimmedCategory.isEmpty ? nil : trimmedCategory))
                newRoutineName = ""
                newRoutineCategory = ""
            }
            Button("Cancel", role: .cancel) { newRoutineName = ""; newRoutineCategory = "" }
        }
#if canImport(WatchConnectivity)
        .fullScreenCover(isPresented: $isSearchingForWatch) {
            NavigationStack {
                WatchSearchView(
                    kind: kind,
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
    }

    /// HealthKit params forwarded to WatchSearchView (which launches the watch app)
    private var watchSearchHealthKitEnabled: Bool {
#if os(iOS)
        healthKitEnabled
#else
        false
#endif
    }

    private var watchSearchActivityType: String? {
#if os(iOS)
        healthKitEnabled ? activityType.rawValue : nil
#else
        nil
#endif
    }

#if os(iOS)
    @ViewBuilder
    private var workoutTrackingSection: some View {
        if kind == .workout {
            Section(footer: Text("Workouts are always recorded to Apple Health via Apple Watch.")) {
                Picker("Activity Type", selection: activityTypeBinding) {
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
                    Text(kind.startButtonLabel)
                    Spacer()
                }
                .font(.headline)
                .foregroundStyle(.green)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: { showSaveRoutineAlert = true }) {
                HStack {
                    Image(systemName: "folder.badge.plus")
                    Text("Save as Routine…")
                    Spacer()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func startOrSearchForWatch() {
#if canImport(UIKit)
        // A focused text field (exercise name/weight) can otherwise absorb this tap as a
        // keyboard-dismiss rather than a button press — resign it up front so the tap that
        // reaches here always lands cleanly. See "intermittent tap failures" in the backlog.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
#endif
        startOrSearchForWatchConfirmed()
    }

    private func startOrSearchForWatchConfirmed() {
#if canImport(WatchConnectivity)
        if WCSession.isSupported() {
            pushContextToWatch()
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
            kind: kind,
            healthKitEnabled: watchSearchHealthKitEnabled,
            activityType: watchSearchActivityType,
            workoutID: UUID()
        )
        WatchConnectivityManager.shared.sendWorkoutCommand(command)
#endif
        isWorkoutActive = true
    }

    /// Writes a mid-session reps/weight edit (see `SessionView.onExerciseAdjusted`) back to the
    /// builder's own list and, if the running session was loaded from a saved routine, to that
    /// routine too — matched by exercise id so edits land on the right exercise even if the
    /// person reordered or added exercises in the builder after loading.
    private func applyLiveAdjustment(_ adjusted: Exercise) {
        if let index = exercises.firstIndex(where: { $0.id == adjusted.id }) {
            exercises[index].weight = adjusted.weight
            exercises[index].weightUnit = adjusted.weightUnit
            exercises[index].targetReps = adjusted.targetReps
            exercises[index].targetRepsMax = adjusted.targetRepsMax
        }
        guard let loadedRoutineID,
              let routineIndex = savedRoutines.firstIndex(where: { $0.id == loadedRoutineID }),
              let exerciseIndex = savedRoutines[routineIndex].exercises.firstIndex(where: { $0.id == adjusted.id }) else { return }
        savedRoutines[routineIndex].exercises[exerciseIndex].weight = adjusted.weight
        savedRoutines[routineIndex].exercises[exerciseIndex].weightUnit = adjusted.weightUnit
        savedRoutines[routineIndex].exercises[exerciseIndex].targetReps = adjusted.targetReps
        savedRoutines[routineIndex].exercises[exerciseIndex].targetRepsMax = adjusted.targetRepsMax
    }

    private func loadSavedExercises() {
        if let data = UserDefaults.standard.data(forKey: exercisesDefaultsKey) {
            if let decoded = try? JSONDecoder().decode([Exercise].self, from: data) {
                exercises = decoded
                exercises.normalizeSupersets()
            }
        }
    }

    private func persistExercises() {
        if let data = try? JSONEncoder().encode(exercises) {
            UserDefaults.standard.set(data, forKey: exercisesDefaultsKey)
        }
        // Only the Exercises tab keeps the watch's mirrored context live on every edit — the
        // Timers tab pushes it once, right before a session actually starts (see
        // `startOrSearchForWatchConfirmed`), since a plain timer has no HealthKit/zone settings
        // to keep in sync in the background.
#if canImport(WatchConnectivity) && canImport(HealthKit)
        if kind == .workout {
            pushContextToWatch()
        }
#endif
    }

#if canImport(WatchConnectivity) && canImport(HealthKit)
    private func pushContextToWatch() {
        WatchConnectivityManager.shared.updateContext(
            exercises: exercises,
            kind: kind,
            healthKitEnabled: watchSearchHealthKitEnabled,
            activityType: watchSearchActivityType,
            hrZoneSettings: HRZoneStore.load()
        )
    }
#endif

#if canImport(WatchConnectivity)
    /// Handle workout commands received from Apple Watch — only ones matching this tab's kind.
    private func handleWatchCommand(_ command: WorkoutCommand?) {
        guard let command else { return }

        switch command {
        case .start(let exerciseList, let commandKind, _, _, _):
            guard commandKind == kind else { return }
            // Watch is starting a session — iPhone drives timers
            exercises = exerciseList
            exercises.normalizeSupersets()
            isSearchingForWatch = false
            isWorkoutActive = true

        default:
            // Other commands (stop, updatePhase, pause, resume) are handled by SessionView
            break
        }
    }
#endif
}
