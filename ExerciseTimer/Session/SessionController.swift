import Foundation
import SwiftUI
internal import Combine
#if canImport(UIKit)
import UIKit
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(HealthKit)
import HealthKit
#endif

/// Owns a running session on iPhone / iPad / Mac: wraps the pure `SessionEngine` with a clock,
/// audio cues, notifications, HealthKit and watch sync. Views only read from it and call actions.
@MainActor
final class SessionController: ObservableObject {
    let kind: SessionKind
    let routineName: String?
    let planSession: PlanSessionRef?
    let workoutID: UUID

    @Published private(set) var engine: SessionEngine
    /// Ticks ~5x a second while the session is on screen; views use it for countdowns.
    @Published private(set) var now = Date()
    @Published private(set) var recap: SessionRecap?
    @Published private(set) var milestones: [Milestone] = []
    @Published var showUndoToast = false
    @Published private(set) var undoToastText = ""

    /// Called after a mid-session weight/reps edit so the builder can write it back.
    var onExerciseAdjusted: (Exercise) -> Void = { _ in }

    let history: WorkoutHistoryStore
    private let sounds = SessionSounds()
    private var ticker: AnyCancellable?
    private var revision = 0
    private var undoToastTask: Task<Void, Never>?
    private var heartRateReadings: [Double] = []

    #if canImport(HealthKit) && !os(macOS)
    let healthKitEnabled: Bool
    let activityType: WorkoutActivityOption
    private var phoneOwnsHealthKitSession = false
    #endif

    init(kind: SessionKind, exercises: [Exercise], routineName: String? = nil, planSession: PlanSessionRef? = nil,
         healthKitEnabled: Bool, activityType: WorkoutActivityOption,
         history: WorkoutHistoryStore? = nil, now: Date = Date()) {
        self.kind = kind
        self.routineName = routineName
        self.planSession = planSession
        // Not a default argument: those are evaluated outside the main actor.
        self.history = history ?? WorkoutHistoryStore.shared
        self.engine = SessionEngine(exercises: exercises, now: now)
        self.now = now
        #if canImport(WatchConnectivity)
        self.workoutID = WatchConnectivityManager.shared.currentWorkoutID ?? UUID()
        #else
        self.workoutID = UUID()
        #endif
        #if canImport(HealthKit) && !os(macOS)
        self.healthKitEnabled = healthKitEnabled
        self.activityType = activityType
        #endif
    }

    #if DEBUG
    /// Screenshot mode: wraps a prebuilt engine and never starts the ticker, so countdowns hold
    /// still at `now`. A finished engine shows its recap straight away (without touching history).
    /// With `live`, the ticker does run (for a video clip where the countdown should play).
    private(set) var isFrozen = false

    init(frozenEngine engine: SessionEngine, now: Date, kind: SessionKind, routineName: String?,
         history: WorkoutHistoryStore, live: Bool = false) {
        self.kind = kind
        self.routineName = routineName
        self.planSession = nil
        self.history = history
        self.engine = engine
        self.now = now
        self.workoutID = UUID()
        #if canImport(HealthKit) && !os(macOS)
        self.healthKitEnabled = kind == .workout
        self.activityType = .functionalStrengthTraining
        #endif
        self.isFrozen = !live
        self.hasStarted = !live
        if engine.state.isFinished {
            let summary = engine.recap(now: now)
            recap = summary
            let workout = CompletedWorkout(date: engine.state.startedAt, kind: kind, routineName: routineName,
                                           duration: summary.duration, completedNaturally: summary.completedNaturally,
                                           records: summary.records)
            milestones = Milestones.find(in: workout, history: history.workouts)
        }
    }
    #endif

    // MARK: Lifecycle

    private var hasStarted = false

    func start(backgroundAudio: Bool) {
        guard !hasStarted else { return }
        hasStarted = true
        sounds.configureSession()
        #if canImport(UIKit)
        if backgroundAudio { sounds.startBackgroundLoop() }
        #endif
        #if canImport(UserNotifications)
        #if DEBUG
        // Screenshot mode: no permission prompts over a capture or a recording.
        if !ScreenshotMode.isActive { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in } }
        #else
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        #endif
        #endif
        ticker = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()
            .sink { [weak self] date in self?.tick(date) }
        #if DEBUG
        if !ScreenshotMode.isActive { startPhoneHealthKitIfNeeded() }
        #else
        startPhoneHealthKitIfNeeded()
        #endif
        afterChange(events: .phaseChanged, playCue: false)
    }

    /// Called when the app returns to the foreground: catches up on everything that happened.
    func catchUp() {
        #if DEBUG
        if isFrozen { return }
        #endif
        tick(Date())
    }

    func setBackgroundAudio(_ enabled: Bool) {
        #if canImport(UIKit)
        enabled ? sounds.startBackgroundLoop() : sounds.stopBackgroundLoop()
        #endif
    }

    func tearDown() {
        ticker?.cancel()
        ticker = nil
        cancelNotifications()
        sounds.stopAll()
        #if canImport(HealthKit) && !os(macOS)
        let hk = HealthKitWorkoutManager.shared
        if healthKitEnabled && !phoneOwnsHealthKitSession {
            // Forwarded-from-watch values shouldn't linger into the next session.
            hk.heartRate = 0
            hk.activeCalories = 0
            hk.isWorkoutActive = false
        }
        #endif
    }

    private func tick(_ date: Date) {
        now = date
        guard recap == nil else { return }
        let events = engine.tick(now: date)
        if !events.isEmpty { afterChange(events: events) }
    }

    // MARK: Actions

    func togglePause() {
        if engine.state.isPaused {
            engine.resume(now: Date())
            #if canImport(HealthKit) && !os(macOS)
            if phoneOwnsHealthKitSession { HealthKitWorkoutManager.shared.resumeWorkout() }
            #endif
        } else {
            engine.pause(now: Date())
            #if canImport(HealthKit) && !os(macOS)
            if phoneOwnsHealthKitSession { HealthKitWorkoutManager.shared.pauseWorkout() }
            #endif
        }
        afterChange(events: [], playCue: false)
    }

    func completeSet(reps: Int? = nil, weight: Double? = nil) {
        let events = engine.completeSet(now: Date(), reps: reps, weight: weight)
        offerUndo(kind == .workout ? "Set logged" : "Done")
        afterChange(events: events)
    }

    func skip() {
        let events = engine.skip(now: Date())
        offerUndo("Skipped")
        afterChange(events: events)
    }

    func skipBlock() {
        let isSuperset = engine.currentStep.map { engine.plan.blocks[$0.block].isSuperset } ?? false
        let events = engine.skipBlock(now: Date())
        offerUndo(isSuperset ? "\(kind.supersetActionLabel) skipped" : "\(kind.itemName) skipped")
        afterChange(events: events)
    }

    func addSet() {
        let events = engine.addSetToCurrentBlock(now: Date())
        offerUndo(kind.setsAddedToastLabel)
        afterChange(events: events, playCue: false)
    }

    func undo() {
        guard engine.undo(now: Date()) else { return }
        withAnimation { showUndoToast = false }
        afterChange(events: .phaseChanged, playCue: false)
    }

    func updateWeight(exerciseIndex: Int, weight: Double?, unit: WeightUnit) {
        engine.updateExercise(at: exerciseIndex) { $0.weight = weight; $0.weightUnit = unit }
        onExerciseAdjusted(engine.exercises[exerciseIndex])
        afterChange(events: [], playCue: false)
    }

    func updateReps(exerciseIndex: Int, reps: Int?, repsMax: Int?) {
        engine.updateExercise(at: exerciseIndex) { $0.targetReps = reps; $0.targetRepsMax = repsMax }
        onExerciseAdjusted(engine.exercises[exerciseIndex])
        afterChange(events: [], playCue: false)
    }

    /// "Swap" — the equipment's taken, so do something similar instead. Only this session changes.
    func swapExercise(at index: Int, toName name: String) {
        engine.updateExercise(at: index) { $0.name = name }
        afterChange(events: [], playCue: false)
    }

    func amendLastRecord(reps: Int?, weight: Double?) {
        guard let record = engine.lastRecord else { return }
        engine.amendRecord(id: record.id, reps: reps, weight: weight)
        afterChange(events: [], playCue: false)
    }

    func endEarly() {
        engine.end(now: Date())
        afterChange(events: .finished, playCue: false)
    }

    // MARK: Helpers for views

    func lastPerformance(forExercise index: Int) -> LastPerformance? {
        guard engine.exercises.indices.contains(index), kind == .workout else { return nil }
        return history.lastPerformance(of: engine.exercises[index], before: engine.state.startedAt)
    }

    func progressionHint(forExercise index: Int) -> ProgressionHint? {
        guard engine.exercises.indices.contains(index) else { return nil }
        return Progression.hint(for: engine.exercises, at: index, last: lastPerformance(forExercise: index))
    }

    // MARK: Internals

    private func offerUndo(_ text: String) {
        undoToastText = text
        withAnimation { showUndoToast = true }
        undoToastTask?.cancel()
        undoToastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation { self?.showUndoToast = false }
        }
    }

    private func afterChange(events: EngineEvents, playCue: Bool = true) {
        revision += 1
        if engine.state.isFinished {
            finish()
            return
        }
        if playCue && events.contains(.phaseChanged) { sounds.playCue() }
        scheduleNotifications()
        sendSync()
    }

    private func finish() {
        guard recap == nil else { sendSync(); return }
        let summary = engine.recap(now: Date())
        recap = summary
        ticker?.cancel()
        cancelNotifications()
        if summary.completedNaturally { sounds.playCompletion() }
        sounds.stopAll()
        sendSync()
        #if canImport(WatchConnectivity)
        WatchConnectivityManager.shared.sendWorkoutCommand(.stop)
        #endif
        #if canImport(HealthKit) && !os(macOS)
        if phoneOwnsHealthKitSession {
            phoneOwnsHealthKitSession = false
            Task { await HealthKitWorkoutManager.shared.endWorkout() }
        }
        #endif
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = false
        #endif

        let workout = CompletedWorkout(date: engine.state.startedAt, kind: kind, routineName: routineName,
                                       duration: summary.duration, completedNaturally: summary.completedNaturally,
                                       records: summary.records,
                                       planSession: summary.setsCompleted > 0 ? planSession : nil)
        milestones = Milestones.find(in: workout, history: history.workouts)
        if kind == .workout { history.add(workout) }
    }

    private func sendSync() {
        #if canImport(WatchConnectivity)
        let sync = SessionSync(workoutID: workoutID, revision: revision, engine: engine)
        WatchConnectivityManager.shared.sendWorkoutCommand(.sync(sync))
        #endif
    }

    // MARK: Notifications
    //
    // Schedules every upcoming phase end that will happen without input (up to the next
    // rep-based set), so a locked phone still chimes for each rest and timed set — the old code
    // only ever scheduled the one in progress.

    private static let notificationPrefix = "exercisePhaseEnd"

    private func scheduleNotifications() {
        #if canImport(UserNotifications)
        cancelNotifications()
        guard !engine.state.isPaused else { return }
        let center = UNUserNotificationCenter.current()
        let reference = Date()
        var projection = engine
        for i in 0..<24 {
            guard let step = projection.currentStep,
                  let fire = projection.nextEventDate, fire > reference else { break }
            projection.tick(now: fire)
            let content = UNMutableNotificationContent()
            if step.isRest {
                content.title = kind.restCompleteNotificationTitle
                if let next = projection.currentStep, next.kind == .work {
                    content.body = "Up next: \(projection.displayName(ofExercise: next.exerciseIndex, kind: kind))"
                }
            } else {
                content.title = kind.activeCompleteNotificationTitle
                content.body = projection.state.isFinished ? kind.recapCompletedTitle : projection.phaseLabel(kind: kind).capitalized
            }
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: fire.timeIntervalSince(reference), repeats: false)
            center.add(UNNotificationRequest(identifier: "\(Self.notificationPrefix)-\(i)", content: content, trigger: trigger))
            if projection.state.isFinished { break }
        }
        #endif
    }

    private func cancelNotifications() {
        #if canImport(UserNotifications)
        let ids = (0..<24).map { "\(Self.notificationPrefix)-\($0)" } + [Self.notificationPrefix]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        #endif
    }

    // MARK: HealthKit (phone-owned session when no watch is around)

    private func startPhoneHealthKitIfNeeded() {
        #if os(iOS) && canImport(HealthKit) && canImport(WatchConnectivity)
        guard healthKitEnabled, !WatchConnectivityManager.shared.isWatchReachable else { return }
        Task {
            let hk = HealthKitWorkoutManager.shared
            await hk.requestAuthorization()
            guard hk.isAuthorized, recap == nil else { return }
            await hk.startWorkoutSession(with: HealthKitWorkoutManager.workoutConfiguration(for: activityType.rawValue))
            phoneOwnsHealthKitSession = true
        }
        #endif
    }

    var averageHeartRate: Double {
        #if canImport(HealthKit) && !os(macOS)
        if !heartRateReadings.isEmpty { return heartRateReadings.reduce(0, +) / Double(heartRateReadings.count) }
        return HealthKitWorkoutManager.shared.heartRate
        #else
        return 0
        #endif
    }

    // MARK: Watch commands

    #if canImport(WatchConnectivity)
    func handle(_ command: WorkoutCommand?) {
        guard let command else { return }
        switch command {
        case .pause:
            if !engine.state.isPaused { togglePause() } else { sendSync() }
        case .resume:
            if engine.state.isPaused { togglePause() } else { sendSync() }
        case .stop:
            if recap == nil { endEarly() }
        case .repsComplete:
            completeSet()
        case .skipPhase:
            skip()
        case .undo:
            undo()
        case .healthData(let heartRate, let activeCalories, let zone):
            #if canImport(HealthKit) && !os(macOS)
            let hk = HealthKitWorkoutManager.shared
            hk.heartRate = heartRate
            hk.activeCalories = activeCalories
            hk.currentHRZoneIndex = zone
            if heartRate > 0 { heartRateReadings.append(heartRate) }
            if !hk.isWorkoutActive { hk.isWorkoutActive = true }
            #endif
        case .start, .sync, .wake, .zoneSummary:
            // .zoneSummary is stored on WatchConnectivityManager itself (it lands after the recap shows).
            break
        }
    }
    #endif
}
