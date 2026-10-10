import SwiftUI
#if canImport(HealthKit)
import HealthKit
#endif

// MARK: - Watch Search View

#if canImport(WatchConnectivity)
struct WatchSearchView: View {
    let kind: SessionKind
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
                    Text("Tap \(kind.startButtonLabel) on your Apple Watch to begin.")
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
        .navigationTitle(kind == .workout ? "Starting Workout" : "Starting Timer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
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
            if case .start(_, _, _, _, _) = connectivity.receivedCommand {
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
            .start(exercises: exercises, kind: kind, healthKitEnabled: healthKitEnabled, activityType: activityType, workoutID: UUID())
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
