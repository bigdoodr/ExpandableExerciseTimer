import Foundation

#if os(iOS) || os(watchOS)
import WatchConnectivity

@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()
    
    @Published var receivedExercises: [Exercise] = []
    @Published var receivedCommand: WorkoutCommand?
    @Published var isWatchReachable = false
    
    private var session: WCSession?
    
    override init() {
        super.init()
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }
    
    /// Send a workout command to the counterpart (used by iOS to control watch)
    func sendWorkoutCommand(_ command: WorkoutCommand) {
        guard let session, session.activationState == .activated else { return }
        guard let data = try? JSONEncoder().encode(command) else { return }
        let message: [String: Any] = [WCContextKey.workoutCommand: data]
        
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { error in
                print("WC sendMessage failed: \(error.localizedDescription)")
                // Fallback to transferUserInfo for reliability
                session.transferUserInfo(message)
            }
        } else {
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
        
        if let commandData = message[WCContextKey.workoutCommand] as? Data,
           let command = try? JSONDecoder().decode(WorkoutCommand.self, from: commandData) {
            Task { @MainActor in
                self.receivedCommand = command
                // Also extract exercises from start command
                if case .start(let exercises, _, _) = command {
                    self.receivedExercises = exercises
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
