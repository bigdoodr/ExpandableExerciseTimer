import Foundation
internal import Combine

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

#if canImport(WatchConnectivity)

@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {

    static let shared = WatchConnectivityManager()
    
    @Published var receivedExercises: [Exercise] = []
    @Published var receivedCommand: WorkoutCommand?
    /// Increments on every received command, even ones identical to the last (e.g. repeated
    /// `.repsComplete` taps for consecutive sets). Views observe this instead of `receivedCommand`
    /// directly, since two back-to-back assignments of an *equal* enum value in the same run-loop
    /// tick get coalesced by SwiftUI's onChange and never fire.
    @Published var commandSequence = 0
    @Published var isWatchReachable = false
    @Published var receivedHealthKitEnabled = false
    @Published var receivedActivityType: String?
    /// Time-in-zone forwarded from the watch once it ends the HealthKit session it owns.
    /// Lives here rather than in a view's `@State` because it arrives *after* the recap has
    /// replaced the workout view — any `onChange` attached to that view is torn down by then.
    @Published var completedZoneSummary: [HRZoneRecapEntry] = []
    /// The workout currently in progress (or most recently started). Used to reject a
    /// `.zoneSummary` that was computed for a *previous* workout but arrives late — see
    /// `WorkoutCommand.zoneSummary`.
    @Published private(set) var currentWorkoutID: UUID?

    private var session: WCSession?
    
    override init() {
        super.init()
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }
    
    /// Send a workout command to the counterpart
    func sendWorkoutCommand(_ command: WorkoutCommand) {
        // A new workout invalidates the previous workout's zone breakdown.
        if case .start(_, _, _, let workoutID) = command {
            currentWorkoutID = workoutID
            completedZoneSummary = []
        }
        guard let session, session.activationState == .activated else { return }
        guard let data = try? JSONEncoder().encode(command) else { return }
        let message: [String: Any] = [WCContextKey.workoutCommand: data]

        // Zone summaries are computed only once the HealthKit session has finished, which
        // routinely lands while the counterpart is backgrounded or mid-transition.
        // transferUserInfo queues reliably and delivers regardless of reachability;
        // sendMessage would silently drop it.
        if case .zoneSummary = command {
            session.transferUserInfo(message)
            return
        }

        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { error in
                print("WC sendMessage failed: \(error.localizedDescription)")
                // Only queue commands that are safe to deliver out-of-order later.
                // Never queue time-sensitive or idempotent-breaking commands.
                switch command {
                case .healthData, .stop, .pause, .resume, .repsComplete, .skipPhase, .wake: return
                default: break
                }
                session.transferUserInfo(message)
            }
        } else {
            // When counterpart is unreachable, only queue durable setup commands.
            switch command {
            case .healthData, .stop, .pause, .resume, .repsComplete, .skipPhase, .wake: return
            default: break
            }
            session.transferUserInfo(message)
        }
    }
    
    /// Update application context with exercise list (reliable, persisted delivery)
    func updateContext(exercises: [Exercise], healthKitEnabled: Bool, activityType: String?) {
        guard let session, session.activationState == .activated else { return }
        guard let exerciseData = try? JSONEncoder().encode(exercises) else { return }
        
        var context: [String: Any] = [
            WCContextKey.exercises: exerciseData,
            WCContextKey.healthKitEnabled: healthKitEnabled
        ]
        if let activityType {
            context[WCContextKey.activityType] = activityType
        }
        
        try? session.updateApplicationContext(context)
    }
    
    private func handleReceivedMessage(_ message: [String: Any]) {
        if let exerciseData = message[WCContextKey.exercises] as? Data,
           let exercises = try? JSONDecoder().decode([Exercise].self, from: exerciseData) {
            Task { @MainActor in
                self.receivedExercises = exercises
            }
        }
        
        // Extract HealthKit settings from context
        if let hkEnabled = message[WCContextKey.healthKitEnabled] as? Bool {
            Task { @MainActor in
                self.receivedHealthKitEnabled = hkEnabled
            }
        }
        if let actType = message[WCContextKey.activityType] as? String {
            Task { @MainActor in
                self.receivedActivityType = actType
            }
        }
        
        if let commandData = message[WCContextKey.workoutCommand] as? Data,
           let command = try? JSONDecoder().decode(WorkoutCommand.self, from: commandData) {
            Task { @MainActor in
                self.receivedCommand = command
                self.commandSequence += 1
                // Also extract exercises from start command
                if case .start(let exercises, _, _, let workoutID) = command {
                    self.receivedExercises = exercises
                    self.currentWorkoutID = workoutID
                    // A new workout invalidates the previous workout's zone breakdown.
                    self.completedZoneSummary = []
                }
                // Stored on the manager rather than in a view's @State: this arrives after the
                // recap has replaced the workout view, so an onChange on that view is already gone.
                // Only accepted if it matches the workout currently in progress — `.zoneSummary` is
                // sent via `transferUserInfo` (queued, best-effort) and can arrive after a later
                // workout has already started, in which case it's stale and must be discarded.
                if case .zoneSummary(let zones, let workoutID) = command, workoutID == self.currentWorkoutID {
                    self.completedZoneSummary = zones
                }
            }
        }
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        Task { @MainActor in
            self.isWatchReachable = session.isReachable
        }
    }
    
    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
    
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            self.handleReceivedMessage(message)
        }
    }
    
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.handleReceivedMessage(applicationContext)
        }
    }
    
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            self.handleReceivedMessage(userInfo)
        }
    }
    
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isWatchReachable = session.isReachable
        }
    }
}
#endif
