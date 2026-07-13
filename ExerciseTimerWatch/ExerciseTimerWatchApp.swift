import SwiftUI
import HealthKit
import WatchConnectivity

@main
struct ExerciseTimerWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) var delegate
    
    @StateObject private var connectivityManager = WatchConnectivityManager.shared
    @StateObject private var healthKitManager = HealthKitWorkoutManager.shared
    
    init() {
        // Request HealthKit authorization at app launch
        Task {
            await HealthKitWorkoutManager.shared.requestAuthorization()
        }
    }
    
    var body: some Scene {
        WindowGroup {
            WatchWorkoutView()
                .environmentObject(connectivityManager)
                .environmentObject(healthKitManager)
        }
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    /// Called when the iPhone launches this app via HKHealthStore.startWatchApp(with:).
    /// Only PREPARE the session here — the user hasn't tapped Start yet, and preparing
    /// keeps the app surfaced on wrist raise. startWorkoutSession() reuses the
    /// .prepared session when the workout actually begins.
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in
            await HealthKitWorkoutManager.shared.prepareWorkoutSession(with: workoutConfiguration)
        }
    }
}
