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
internal import Combine

fileprivate struct WorkoutUndoAction: Codable {
    let exerciseIndex: Int
    let setBefore: Int
    let wasResting: Bool
    let advancedExercise: Bool
    /// `recapActiveTime` just before this action's advance, so undo can revert the recap
    /// breakdown's double-count of the set that's being undone.
    let activeTimeBefore: TimeInterval
}

struct SessionView: View {
    let kind: SessionKind
    /// Mutable (not `let`) so weight can be adjusted for the next set/round mid-session — see `updateCurrentExerciseWeight`.
    @State private var exercises: [Exercise]
    @Binding var isActive: Bool
    /// Notifies the builder of a mid-session weight/reps edit so it can be written back to the
    /// builder's own list and the saved routine the session was loaded from, if any — see
    /// `SessionBuilderView.applyLiveAdjustment`. Defaulted so none of the custom inits below need it.
    var onExerciseAdjusted: (Exercise) -> Void = { _ in }
#if canImport(UIKit)
    @Binding var keepScreenAwake: Bool
    @Binding var enableBackgroundAudio: Bool
#endif
#if canImport(HealthKit)
    var healthKitEnabled: Bool
    var activityType: WorkoutActivityOption
#endif

    // Split into separate whole declarations per platform combo — `#if` inside a single
    // parameter list isn't reliably supported by the compiler's parser.
#if canImport(UIKit) && canImport(HealthKit)
    init(kind: SessionKind, exercises: [Exercise], isActive: Binding<Bool>, keepScreenAwake: Binding<Bool>, enableBackgroundAudio: Binding<Bool>, healthKitEnabled: Bool, activityType: WorkoutActivityOption) {
        self.kind = kind
        self._exercises = State(initialValue: exercises)
        self._isActive = isActive
        self._keepScreenAwake = keepScreenAwake
        self._enableBackgroundAudio = enableBackgroundAudio
        self.healthKitEnabled = healthKitEnabled
        self.activityType = activityType
    }
#elseif canImport(HealthKit)
    init(kind: SessionKind, exercises: [Exercise], isActive: Binding<Bool>, healthKitEnabled: Bool, activityType: WorkoutActivityOption) {
        self.kind = kind
        self._exercises = State(initialValue: exercises)
        self._isActive = isActive
        self.healthKitEnabled = healthKitEnabled
        self.activityType = activityType
    }
#else
    init(kind: SessionKind, exercises: [Exercise], isActive: Binding<Bool>) {
        self.kind = kind
        self._exercises = State(initialValue: exercises)
        self._isActive = isActive
    }
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
    /// True while `isResting` is a rest *between* two linked superset/circuit exercises (not the
    /// rest after the group's last exercise finishes a round). Set right before entering that rest
    /// phase so `timerExpired()` knows to resume at the next chain member instead of looping the group.
    @State private var restAdvancesWithinGroup = false
    /// Deadline for the current round of a Timed Superset group (`groupTimeBudget` on the group's
    /// first exercise) — re-armed in `startCurrentPhase()` whenever a fresh round begins.
    @State private var groupRoundEndDate: Date? = nil
    /// Overrides `currentExercise.restDuration` for the rest phase currently in progress, used only
    /// for a Timed Superset's between-round rest (whatever's left of the round's time budget).
    /// `nil` means the rest phase uses the exercise's own configured `restDuration`, as usual.
    @State private var currentRestDurationOverride: TimeInterval? = nil
    /// Backs the mid-session "adjust weight" sheet — see `beginEditingWeight`/`updateCurrentExerciseWeight`.
    @State private var showWeightEditor = false
    @State private var weightEditText = ""
    @State private var weightEditUnit: WeightUnit = .lbs
    /// Backs the mid-session "adjust target reps" sheet — see `beginEditingReps`/`updateCurrentExerciseReps`.
    @State private var showRepsEditor = false
    @State private var repsEditText = ""
    @State private var repsEditIsRange = false
    @State private var repsMaxEditText = ""

    /// Wall-clock timestamp of when the current phase (exercise or rest) began — used only to
    /// measure elapsed time for manual-advance exercises, which have no countdown of their own.
    @State private var phaseStartDate: Date = .now
    /// Set right before calling `timerExpired()` from `skipPhaseTapped()` so the phase-ending
    /// recorders can tell a manual skip apart from a natural completion. Cleared once read.
    @State private var isSkippingCurrentPhase = false
    /// Recap breakdown accumulators — see `recordActivePhaseEnding`/`recordRestPhaseEnding`.
    @State private var recapActiveTime: TimeInterval = 0
    @State private var recapRestTime: TimeInterval = 0
    @State private var recapExercisesSkipped = 0
    @State private var recapRestTimeSkipped: TimeInterval = 0

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

    /// Live "time left in this round" for a Timed Superset group, or nil when the group currently
    /// in progress doesn't use a shared time budget (`groupTimeBudget`).
    var groupRoundTimeRemaining: TimeInterval? {
        guard exercises[currentGroupRange.lowerBound].groupTimeBudget != nil,
              let endDate = groupRoundEndDate else { return nil }
        return max(0, endDate.timeIntervalSinceNow)
    }

    @ViewBuilder
    private func timedSupersetRoundBadge(timeRemaining: TimeInterval) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "timer")
            Text("\(formatTime(timeRemaining)) left in round")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
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
        // Timed Superset: the group shares one time budget per round instead of each member's
        // own `restDuration` — see `groupTimeBudget` and `advancePastCompletedSet`.
        let groupTimeBudget = exercises[groupRange.lowerBound].groupTimeBudget
        let remainingRoundTime = max(0, groupRoundEndDate?.timeIntervalSinceNow ?? 0)

        func nextExerciseAfterGroupText() -> String {
            let nextIndex = groupRange.upperBound + 1
            if nextIndex >= exercises.count {
                return "Up Next: \(kind.upNextCompleteLabel)"
            }
            let next = exercises[nextIndex]
            let nextName = next.name.isEmpty ? "\(kind.itemName) \(nextIndex + 1)" : next.name
            let nextSummary = next.quickSummary
            return "Up Next: \(nextName)\(nextSummary.isEmpty ? "" : " · \(nextSummary)")"
        }

        if isResting {
            if restAdvancesWithinGroup {
                // Mid-chain rest — next up is simply the next linked exercise, not a round loop.
                let nextIndex = currentExerciseIndex + 1
                let next = exercises[nextIndex]
                let nextName = next.name.isEmpty ? "\(kind.itemName) \(nextIndex + 1)" : next.name
                let nextSummary = next.quickSummary
                return "Up Next: \(nextName)\(nextSummary.isEmpty ? "" : " · \(nextSummary)")"
            }
            // Otherwise, rest happens after the last exercise in the group finishes a round.
            let nextSet = currentSet + 1
            if nextSet <= roundCount {
                // Another round — loop back to the first exercise in the group.
                let first = exercises[groupRange.lowerBound]
                let name = first.name.isEmpty ? "\(kind.itemName) \(groupRange.lowerBound + 1)" : first.name
                if first.isTimeBased {
                    return "Up Next: \(name) – Round \(nextSet)"
                } else {
                    return "Up Next: \(name) – Round \(nextSet) (\(kind == .workout ? "Reps" : "Prompt"))"
                }
            } else {
                return nextExerciseAfterGroupText()
            }
        } else if currentExerciseIndex < groupRange.upperBound {
            // More linked exercises remain this round. A timed superset always continues straight
            // into the next one — only a normal chain's own `restDuration` inserts a rest here.
            if groupTimeBudget == nil, currentExercise.restDuration > 0 {
                return "Up Next: Rest (\(formatTime(currentExercise.restDuration)))"
            }
            let nextIndex = currentExerciseIndex + 1
            let next = exercises[nextIndex]
            let nextName = next.name.isEmpty ? "\(kind.itemName) \(nextIndex + 1)" : next.name
            let nextSummary = next.quickSummary
            return "Up Next: \(nextName)\(nextSummary.isEmpty ? "" : " · \(nextSummary)")"
        } else if currentSet < roundCount {
            // Last exercise in the group, but more rounds remain
            if groupTimeBudget != nil {
                return remainingRoundTime > 0 ? "Up Next: Rest (\(formatTime(remainingRoundTime)))" : "Up Next: Round \(currentSet + 1)"
            } else if currentExercise.restDuration > 0 {
                return "Up Next: Rest (\(formatTime(currentExercise.restDuration)))"
            } else {
                return "Up Next: Round \(currentSet + 1)"
            }
        } else {
            // Final round of the final exercise in the group
            if groupTimeBudget != nil {
                return remainingRoundTime > 0 ? "Up Next: Rest (\(formatTime(remainingRoundTime)))" : nextExerciseAfterGroupText()
            } else if currentExercise.restDuration > 0 {
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
        .alert(kind.endAlertTitle, isPresented: $showCancelConfirmation) {
            Button(kind.endButtonLabel, role: .destructive) {
                captureRecap(completedNaturally: false)
                beginExit()
                showRecap = true
            }
            Button("Keep Going", role: .cancel) {}
        } message: {
            Text(kind.endAlertMessage)
        }
        .sheet(isPresented: $showWeightEditor) {
            weightEditorSheet
        }
        .sheet(isPresented: $showRepsEditor) {
            repsEditorSheet
        }
    }

    // Combines the phase label with the exercise counter on one line, freeing up the vertical
    // space the counter used to take above the exercise title.
    private func phaseHeader(label: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.title)
                .bold()
                .foregroundStyle(color)
            Text("•")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("\(kind.itemName) \(displayExerciseNumber) of \(totalExercises)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
                    Text(currentExercise.name.isEmpty ? "\(kind.itemName) \(displayExerciseNumber)" : currentExercise.name)
                        .font(.largeTitle)
                        .bold()

                    Text(currentGroupRange.count > 1 ? "Round \(currentSet) of \(exercises.roundCount(for: currentGroupRange))" : "\(kind.setUnitSingular) \(currentSet) of \(currentExercise.sets)")
                        .font(.title2)
                        .foregroundStyle(.secondary)

                    // Reps and weight share one line (e.g. "10 reps @ 50 LB") rather than stacking separately.
                    // Timers never carry target reps or weight, so this whole line is workout-only.
                    if kind == .workout {
                        HStack(spacing: 6) {
                            if !currentExercise.isTimeBased {
                                if let reps = currentExercise.targetReps {
                                    // Tappable so target reps can be adjusted mid-session, same as weight below — see `updateCurrentExerciseReps`.
                                    Button {
                                        beginEditingReps()
                                    } label: {
                                        HStack(spacing: 4) {
                                            Text(repsRangeText(reps: reps, repsMax: currentExercise.targetRepsMax))
                                                .font(.title3)
                                                .bold()
                                                .foregroundStyle(.purple)
                                            Image(systemName: "pencil.circle.fill")
                                                .font(.caption)
                                                .foregroundStyle(.purple.opacity(0.6))
                                        }
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    Button("Set Target Reps") {
                                        beginEditingReps()
                                    }
                                    .font(.subheadline)
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.purple)
                                }
                            }

                            if let weight = currentExercise.weight {
                                if !currentExercise.isTimeBased, currentExercise.targetReps != nil {
                                    Text("@")
                                        .font(.title3)
                                        .foregroundStyle(.secondary)
                                }
                                // Tappable so weight can be adjusted mid-session (e.g. a set turns out too heavy/light)
                                // without ending the workout — see `updateCurrentExerciseWeight`.
                                Button {
                                    beginEditingWeight()
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(String(format: weight.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f \(currentExercise.weightUnit.rawValue)" : "%.1f \(currentExercise.weightUnit.rawValue)", weight))
                                            .font(.title3)
                                            .bold()
                                            .foregroundStyle(.blue)
                                        Image(systemName: "pencil.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.blue.opacity(0.6))
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding()

                if isResting {
                    VStack(spacing: 20) {
                        phaseHeader(label: kind.restPhaseLabel, color: .orange)

                        Text(formatTime(timeRemaining))
                            .font(.system(size: 72, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                    .padding()
                } else if currentExercise.isTimeBased {
                    VStack(spacing: 20) {
                        phaseHeader(label: kind.activePhaseLabel, color: .green)

                        Text(formatTime(timeRemaining))
                            .font(.system(size: 72, weight: .bold, design: .rounded))
                            .monospacedDigit()

                        if let roundTimeRemaining = groupRoundTimeRemaining {
                            timedSupersetRoundBadge(timeRemaining: roundTimeRemaining)
                        }
                    }
                    .padding()
                } else {
                    VStack(spacing: 20) {
                        phaseHeader(label: kind.manualPhaseLabel, color: .blue)

                        if let roundTimeRemaining = groupRoundTimeRemaining {
                            timedSupersetRoundBadge(timeRemaining: roundTimeRemaining)
                        }

                        if kind == .workout, currentExercise.targetReps == nil {
                            Text("Complete your reps")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        
                        GlassActionButton(tint: .blue, action: manualAdvanceTapped) {
                            Text(kind.manualAdvanceButtonLabel)
                                .font(.headline)
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
                            HStack(spacing: 8) {
                                pauseResumeButton
                                skipButton
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
                            skipButton
                            cancelButton
                            awakeButton
                            backgroundAudioButton
                        }
                    }
                }
                .padding(.horizontal)
#else
                HStack(spacing: 8) {
                    pauseResumeButton
                    skipButton
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
                    Text(kind.setsAddedToastLabel)
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
                        
                        Text(recapCompletedNaturally ? kind.recapCompletedTitle : kind.recapEndedTitle)
                            .font(.title)
                            .bold()
                    }
                    .padding(.top)
                    
                    // Stats
                    VStack(spacing: 16) {
                        recapRow(icon: "clock", color: .blue, label: "Duration", value: formatTime(recapDuration))
                        
                        Divider()
                        
                        recapRow(icon: kind.recapItemsIcon, color: .green,
                                 label: kind.recapItemsLabel, value: "\(recapExercisesCompleted) of \(exercises.count)")
                        
                        Divider()
                        
                        let totalSets = exercises.indices.reduce(0) { $0 + effectiveSets(at: $1) }
                        recapRow(icon: kind.recapSetsIcon, color: .purple,
                                 label: kind.recapSetsLabel, value: "\(recapSetsCompleted) of \(totalSets)")

                        Divider()

                        recapRow(icon: kind.recapActiveIcon, color: .green,
                                 label: kind.recapActiveLabel, value: formatTime(recapActiveTime))

                        Divider()

                        recapRow(icon: kind.recapRestIcon, color: .blue,
                                 label: kind.recapRestLabel, value: formatTime(recapRestTime))

                        if recapExercisesSkipped > 0 {
                            Divider()
                            recapRow(icon: "forward.end.fill", color: .orange,
                                     label: kind.recapItemsSkippedLabel, value: "\(recapExercisesSkipped)")
                        }

                        if recapRestTimeSkipped > 0 {
                            Divider()
                            recapRow(icon: "forward.end.fill", color: .orange,
                                     label: kind.recapRestSkippedLabel, value: formatTime(recapRestTimeSkipped))
                        }

#if canImport(HealthKit)
                        if kind == .workout {
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
                            // A 6th (lowest) zone means HealthKitWorkoutManager prepended a resting-HR
                            // boundary — show it as a distinct "Resting" tier rather than "Zone 1".
                            // (A person's own custom Health-app zone config could coincidentally also
                            // have 6 zones; this only affects the label, not the underlying data.)
                            let hasRestingZone = zoneEntries.count == 6
                            ForEach(zoneEntries, id: \.zoneIndex) { entry in
                                if entry.zoneIndex > 0 { Divider() }
                                let isRestingZone = hasRestingZone && entry.zoneIndex == 0
                                let zoneNum = hasRestingZone ? entry.zoneIndex : entry.zoneIndex + 1
                                let color = isRestingZone ? Color.gray : hrZoneColor(zoneNum)
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
                                            Text(isRestingZone ? "Resting" : "Zone \(zoneNum)")
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
                        } else if recapHeartRate > 0 {
#if os(iOS)
                            // Zone data lands after HealthKit finishes processing the workout —
                            // a few seconds on-device, longer if a watch session has to sync it
                            // over first. Let the user know it's still coming rather than looking
                            // like the feature silently failed.
                            Divider()
                            Text("Heart Rate Zones")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("Calculating your zone breakdown — this can take a few seconds to appear.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
#endif
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
                    
                    GlassActionButton(tint: .green, action: {
                        showRecap = false
                        isActive = false
                    }) {
                        Text("Done")
                            .font(.headline)
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
        // `finishedWorkout` lives on the shared HealthKitWorkoutManager singleton and is only
        // reset by startWorkoutSession() — a workout that never enables HealthKit never calls
        // that, so without this check a *previous* HealthKit-tracked workout's zones would
        // still be sitting there and get shown here as if they belonged to this one.
        if #available(iOS 27.0, *),
           healthKitEnabled,
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

        if !completedNaturally {
            // Count whatever time had already elapsed in the in-progress phase before the
            // workout was cut short — otherwise Active + Rest Time would fall short of Duration.
            if isResting {
                recapRestTime += max(0, (currentRestDurationOverride ?? currentExercise.restDuration) - timeRemaining)
            } else if currentExercise.isTimeBased {
                recapActiveTime += max(0, currentExercise.exerciseDuration - timeRemaining)
            } else {
                recapActiveTime += max(0, Date().timeIntervalSince(phaseStartDate))
            }
        }

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
            // Watch started the workout, already handled in SessionBuilderView
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
            // Watch user tapped the manual-advance button — advance and send state back
            manualAdvanceTapped()

        case .skipPhase:
            // Watch user tapped "Skip" — advance and send state back, same as the iPhone's own Skip button
            skipPhaseTapped()
            
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

        case .zoneSummary(let zones, let workoutID):
            // Forwarded from the watch once it ends the HealthKit session it owns. Only accept
            // it if it belongs to the workout currently running — see WatchConnectivityManager's
            // matching guard on `completedZoneSummary` for why a stale one can arrive here at all.
            guard workoutID == connectivity.currentWorkoutID else { return }
            recapZoneSummary = zones

        case .wake:
            break

        case .updateWeight, .updateTargetReps:
            // iPhone/Mac is the source of truth for weight/reps changes — it never receives these from the watch.
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
        phaseStartDate = Date()
        if !isResting {
            // Any rest-duration override only applies to the rest phase it was computed for.
            currentRestDurationOverride = nil
            // Re-arm the Timed Superset round deadline whenever a fresh round begins.
            let groupRange = currentGroupRange
            if currentExerciseIndex == groupRange.lowerBound, let budget = exercises[groupRange.lowerBound].groupTimeBudget {
                groupRoundEndDate = Date().addingTimeInterval(budget)
            }
        }
        var duration: TimeInterval = 0
        if isResting {
            duration = currentRestDurationOverride ?? currentExercise.restDuration
        } else if currentExercise.isTimeBased {
            duration = currentExercise.exerciseDuration
        } else {
            // Manual-advance: no countdown; nothing to schedule
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
            recordRestPhaseEnding()
            isResting = false
            if restAdvancesWithinGroup {
                // Rest was between two linked exercises, not after the group's last one —
                // just move on to the next chain member, no round-loop logic involved.
                restAdvancesWithinGroup = false
                currentExerciseIndex += 1
                startCurrentPhase()
            } else {
                advancePastRest(groupRange: currentGroupRange)
            }
        } else {
            advancePastCompletedSet()
        }
    }

    /// Manually skip the current phase — an exercise's active timer/set, or a rest period —
    /// and advance immediately. Reuses `timerExpired()` so behavior (including its guards
    /// against skipping while exiting or already completed) matches a phase finishing naturally.
    func skipPhaseTapped() {
        isSkippingCurrentPhase = true
        timerExpired()
#if canImport(WatchConnectivity)
        sendStateToWatch()
#endif
    }

    /// Records the rest phase that's about to end (naturally or via skip) toward the recap
    /// breakdown. Must run before `isResting`/`currentExerciseIndex` change, while `currentExercise`
    /// still refers to the exercise this rest followed.
    private func recordRestPhaseEnding() {
        let wasSkipped = isSkippingCurrentPhase
        isSkippingCurrentPhase = false
        let configuredDuration = currentRestDurationOverride ?? currentExercise.restDuration
        recapRestTime += max(0, configuredDuration - timeRemaining)
        if wasSkipped {
            recapRestTimeSkipped += max(0, timeRemaining)
        }
    }

    /// Records the exercise phase that's about to end (naturally, via skip, or via the manual-advance
    /// button) toward the recap breakdown. Must run before `currentExerciseIndex`/`currentSet` change.
    /// Timed exercises measure elapsed time from the countdown (which already accounts for pauses);
    /// manual-advance exercises have no countdown, so wall-clock time since the phase started is used instead.
    private func recordActivePhaseEnding() {
        let wasSkipped = isSkippingCurrentPhase
        isSkippingCurrentPhase = false
        if currentExercise.isTimeBased {
            recapActiveTime += max(0, currentExercise.exerciseDuration - timeRemaining)
        } else {
            recapActiveTime += max(0, Date().timeIntervalSince(phaseStartDate))
        }
        if wasSkipped {
            recapExercisesSkipped += 1
        }
    }

    /// Called when the current exercise's work phase finishes (a timer expiring, or a manual-advance tap).
    /// Superset/circuit partners each use their own `restDuration` between them (0 means continue
    /// straight into the next one); the group's last exercise separately rests between rounds.
    private func advancePastCompletedSet() {
        recordActivePhaseEnding()
        let groupRange = currentGroupRange
        // Timed Superset: the group shares one time budget per round instead of each member's own
        // `restDuration` — members always run back-to-back, and any budget left over once the last
        // one finishes becomes the round's rest. See `groupTimeBudget`.
        let groupTimeBudget = exercises[groupRange.lowerBound].groupTimeBudget

        if currentExerciseIndex < groupRange.upperBound {
            // More linked exercises remain this round.
            if groupTimeBudget == nil, currentExercise.restDuration > 0 {
                isResting = true
                restAdvancesWithinGroup = true
                startCurrentPhase()
            } else {
                currentExerciseIndex += 1
                isResting = false
                startCurrentPhase()
            }
            return
        }

        // Finished the last exercise in the group for this round.
        if let groupTimeBudget {
            let remaining = max(0, groupRoundEndDate?.timeIntervalSinceNow ?? groupTimeBudget)
            if remaining > 0 {
                currentRestDurationOverride = remaining
                isResting = true
                startCurrentPhase()
            } else {
                advancePastRest(groupRange: groupRange)
            }
        } else if currentExercise.restDuration > 0 {
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
    
    func manualAdvanceTapped() {
        // immediate advance for manual-advance exercises, with undo capture
        guard !currentExercise.isTimeBased else { return }
        let prevExerciseIndex = currentExerciseIndex
        let prevSet = currentSet
        let prevWasResting = isResting
        let prevActiveTime = recapActiveTime
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
        undoAction = WorkoutUndoAction(exerciseIndex: prevExerciseIndex, setBefore: prevSet, wasResting: prevWasResting, advancedExercise: willAdvanceExercise, activeTimeBefore: prevActiveTime)
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
        // Undo the recap breakdown's contribution from the set that's being undone.
        recapActiveTime = action.activeTimeBefore
        phaseStartDate = Date()

        // For manual-advance, return to pre-rest state (no active timer)
        timeRemaining = 0
        // Clear undo and hide toast
        undoAction = nil
        withAnimation { showUndoToast = false }
    }

    /// Opens the mid-session weight-adjustment sheet, seeded with the current exercise's weight.
    func beginEditingWeight() {
        weightEditUnit = currentExercise.weightUnit
        if let weight = currentExercise.weight {
            weightEditText = weight.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(weight))" : String(format: "%.1f", weight)
        } else {
            weightEditText = ""
        }
        showWeightEditor = true
    }

    /// Applies a mid-session weight change to the exercise currently in progress (e.g. a set turned
    /// out too heavy/light), mirrors it to the watch (which otherwise has no way to learn about it),
    /// and reports it back to the builder/saved routine via `onExerciseAdjusted`.
    func updateCurrentExerciseWeight(_ weight: Double?, unit: WeightUnit) {
        let safeIndex = min(max(0, currentExerciseIndex), max(0, exercises.count - 1))
        guard exercises.indices.contains(safeIndex) else { return }
        exercises[safeIndex].weight = weight
        exercises[safeIndex].weightUnit = unit
#if canImport(WatchConnectivity)
        WatchConnectivityManager.shared.sendWorkoutCommand(.updateWeight(exerciseIndex: safeIndex, weight: weight, weightUnit: unit))
#endif
        onExerciseAdjusted(exercises[safeIndex])
    }

    /// Opens the mid-session target-reps-adjustment sheet, seeded with the current exercise's reps.
    func beginEditingReps() {
        if let reps = currentExercise.targetReps {
            repsEditText = "\(reps)"
            if let repsMax = currentExercise.targetRepsMax, repsMax != reps {
                repsEditIsRange = true
                repsMaxEditText = "\(repsMax)"
            } else {
                repsEditIsRange = false
                repsMaxEditText = ""
            }
        } else {
            repsEditText = ""
            repsEditIsRange = false
            repsMaxEditText = ""
        }
        showRepsEditor = true
    }

    /// Applies a mid-session target-reps change to the exercise currently in progress, mirrors it to
    /// the watch, and reports it back to the builder/saved routine via `onExerciseAdjusted`.
    func updateCurrentExerciseReps(_ reps: Int?, repsMax: Int?) {
        let safeIndex = min(max(0, currentExerciseIndex), max(0, exercises.count - 1))
        guard exercises.indices.contains(safeIndex) else { return }
        exercises[safeIndex].targetReps = reps
        exercises[safeIndex].targetRepsMax = repsMax
#if canImport(WatchConnectivity)
        WatchConnectivityManager.shared.sendWorkoutCommand(.updateTargetReps(exerciseIndex: safeIndex, reps: reps, repsMax: repsMax))
#endif
        onExerciseAdjusted(exercises[safeIndex])
    }

    /// Formats target reps as "10 reps" or, when a range's upper bound differs, "8–10 reps".
    func repsRangeText(reps: Int, repsMax: Int?) -> String {
        if let repsMax, repsMax != reps {
            return "\(reps)–\(repsMax) reps"
        }
        return "\(reps) reps"
    }

    private var weightEditorSheet: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 8) {
                        TextField("0", text: $weightEditText)
#if os(iOS)
                            .keyboardType(.decimalPad)
#endif
                        Picker("Unit", selection: $weightEditUnit) {
                            Text("LB").tag(WeightUnit.lbs)
                            Text("KG").tag(WeightUnit.kg)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 120)
                    }
                }
            }
            .navigationTitle("Adjust Weight")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showWeightEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let parsed = Double(weightEditText)
                        updateCurrentExerciseWeight(parsed.map { max(0, $0) }, unit: weightEditUnit)
                        showWeightEditor = false
                    }
                }
            }
        }
    }

    private var repsEditorSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("0", text: $repsEditText)
#if os(iOS)
                        .keyboardType(.numberPad)
#endif
                    Toggle("Range", isOn: $repsEditIsRange)
                    if repsEditIsRange {
                        TextField("Max reps", text: $repsMaxEditText)
#if os(iOS)
                            .keyboardType(.numberPad)
#endif
                    }
                }
            }
            .navigationTitle("Adjust Target Reps")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showRepsEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let reps = Int(repsEditText).map { max(0, $0) }
                        let repsMax = repsEditIsRange ? Int(repsMaxEditText).map { max(0, $0) } : nil
                        // A max below the lower bound isn't a valid range — drop it rather than swap,
                        // so "Save" never silently reinterprets what was typed.
                        let validatedMax = (reps != nil && repsMax != nil && repsMax! >= reps!) ? repsMax : nil
                        updateCurrentExerciseReps(reps, repsMax: validatedMax)
                        showRepsEditor = false
                    }
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
        GlassActionButton(tint: keepScreenAwake ? .green : .gray, action: { keepScreenAwake.toggle() }) {
            HStack {
                Image(systemName: keepScreenAwake ? "bolt.fill" : "bolt.slash")
                Text(keepScreenAwake ? "Awake On" : "Awake Off")
            }
            .font(.headline)
        }
    }

    private var backgroundAudioButton: some View {
        GlassActionButton(tint: enableBackgroundAudio ? .green : .gray, action: { enableBackgroundAudio.toggle() }) {
            HStack {
                Image(systemName: enableBackgroundAudio ? "speaker.wave.2.fill" : "speaker.slash")
                Text(enableBackgroundAudio ? "BG Audio On" : "BG Audio Off")
            }
            .font(.headline)
        }
    }
#endif

    private var pauseResumeButton: some View {
        GlassActionButton(tint: .orange, action: {
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .font(.headline)
        }
    }

    private var cancelButton: some View {
        GlassActionButton(tint: .red, action: { showCancelConfirmation = true }) {
            HStack {
                Image(systemName: "xmark.circle.fill")
                Text("Cancel")
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .font(.headline)
        }
    }

    /// Skips the rest of the current exercise timer/set, or the current rest period, and
    /// advances immediately — same effect a natural completion would have.
    private var skipButton: some View {
        GlassActionButton(tint: .orange, action: skipPhaseTapped) {
            HStack {
                Image(systemName: "forward.end.fill")
                Text("Skip")
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .font(.headline)
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
        content.title = isResting ? kind.restCompleteNotificationTitle : kind.activeCompleteNotificationTitle
        content.body = isResting
            ? "Time to start the next \(kind.setUnitSingular.lowercased())."
            : (currentExercise.isTimeBased ? "Move to \(kind.restPhaseLabel.lowercased()) or next \(kind.itemName.lowercased())." : "")
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
