import SwiftUI
import HealthKit
import WatchConnectivity

@main
struct ExerciseTimerWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) var delegate
    
    @StateObject private var connectivityManager = WatchConnectivityManager.shared
    @StateObject private var healthKitManager = HealthKitWorkoutManager.shared
    
    var body: some Scene {
        WindowGroup {
            WatchWorkoutView()
                .environmentObject(connectivityManager)
                .environmentObject(healthKitManager)
        }
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in
            await HealthKitWorkoutManager.shared.startWorkoutSession(with: workoutConfiguration)
        }
    }
}
