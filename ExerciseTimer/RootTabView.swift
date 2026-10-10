import SwiftUI
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif
#if canImport(HealthKit)
import HealthKit
#endif

enum AppTab: Hashable {
    case exercises
    case timers
    case routines
    case settings
}

/// Carries a routine (or preloaded routine) into a builder tab. `isSavedRoutine` controls whether
/// the builder tracks it as a live saved routine (so mid-session weight/reps edits write back to
/// it) — preloaded routines are never editable, so they're loaded as a one-off copy instead.
struct RoutineLoadRequest: Equatable {
    let routine: Routine
    let isSavedRoutine: Bool
    let autoStart: Bool
}

/// Root of the app: a tab per session kind (Exercises, Timers), plus Routines and Settings.
/// Owns the state that's shared across tabs — saved routines, onboarding, and routing a routine
/// (from the Routines tab, or a Siri/Shortcuts request) into the correct builder tab.
struct RootTabView: View {
    @State private var selectedTab: AppTab = .exercises
    @State private var savedRoutines: [Routine] = []
    @State private var workoutLoadRequest: RoutineLoadRequest?
    @State private var timerLoadRequest: RoutineLoadRequest?

    @State private var showOnboarding = false
    @State private var onboardingMode: OnboardingView.Mode = .full

#if canImport(WatchConnectivity)
    @StateObject private var connectivity = WatchConnectivityManager.shared
#endif
#if os(iOS) && canImport(HealthKit)
    /// Drives the missing-age warning badge on the Settings tab — see `fetchMaxHeartRate()`.
    @ObservedObject private var healthKitManagerForBadge = HealthKitWorkoutManager.shared
#endif
    @Environment(\.scenePhase) private var scenePhase

    private let savedRoutinesKey = "savedRoutines"
    private let pendingRoutineKey = "pendingRoutineStart"
    private let hasSeenOnboardingKey = "hasSeenOnboarding"
    private let lastSeenAppVersionKey = "lastSeenAppVersion"

    /// True when HealthKit is available but age couldn't be read from it — always false on
    /// platforms/configurations without HealthKit (e.g. macOS), where there's nothing to warn about.
    private var ageMissingBadgeVisible: Bool {
#if os(iOS) && canImport(HealthKit)
        HKHealthStore.isHealthDataAvailable() && healthKitManagerForBadge.age == nil
#else
        false
#endif
    }

    private var currentAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(SessionKind.workout.tabTitle, systemImage: SessionKind.workout.tabIcon, value: .exercises) {
                NavigationStack {
                    SessionBuilderView(kind: .workout, savedRoutines: $savedRoutines, loadRequest: $workoutLoadRequest)
                }
            }
            Tab(SessionKind.timer.tabTitle, systemImage: SessionKind.timer.tabIcon, value: .timers) {
                NavigationStack {
                    SessionBuilderView(kind: .timer, savedRoutines: $savedRoutines, loadRequest: $timerLoadRequest)
                }
            }
            Tab("Routines", systemImage: "folder", value: .routines) {
                NavigationStack {
                    RoutinesView(savedRoutines: $savedRoutines, onLoad: loadRoutine)
                }
            }
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                SettingsView(onShowOnboarding: {
                    onboardingMode = .full
                    showOnboarding = true
                })
            }
            .badge(ageMissingBadgeVisible ? Text("!") : nil)
        }
        .onAppear {
            loadSavedRoutines()
            checkPendingRoutine()
            presentOnboardingIfNeeded()
#if os(iOS) && canImport(HealthKit)
            HealthKitWorkoutManager.shared.fetchMaxHeartRate()
#endif
        }
        .onChange(of: savedRoutines) { _, _ in
            persistRoutines()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                checkPendingRoutine()
#if os(iOS) && canImport(HealthKit)
                Task { await HealthKitWorkoutManager.shared.requestAuthorization() }
#endif
            }
        }
#if canImport(WatchConnectivity)
        .onChange(of: connectivity.commandSequence) { _, _ in
            if case .start(_, let kind, _, _, _) = connectivity.receivedCommand {
                selectedTab = kind == .workout ? .exercises : .timers
            }
        }
#endif
        .sheet(isPresented: $showOnboarding, onDismiss: {
            markOnboardingSeen()
        }) {
            OnboardingView(mode: onboardingMode)
        }
    }

    /// Routes a routine (from the Routines tab or a Siri/Shortcuts request) into the builder tab
    /// matching its kind, switching tabs to show it.
    private func loadRoutine(_ request: RoutineLoadRequest) {
        selectedTab = request.routine.kind == .workout ? .exercises : .timers
        switch request.routine.kind {
        case .workout: workoutLoadRequest = request
        case .timer: timerLoadRequest = request
        }
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

    /// Resolves a "saved:<uuid>" or "preloaded:<uuid>" identifier set by StartRoutineIntent
    /// (from Siri/Shortcuts) against the matching store. Preloaded routines are always workouts;
    /// saved routines carry their own `kind`.
    private func pendingRoutineRequest(for idStr: String) -> RoutineLoadRequest? {
        if idStr.hasPrefix("saved:") {
            let uuidStr = String(idStr.dropFirst("saved:".count))
            guard let uuid = UUID(uuidString: uuidStr),
                  let routine = savedRoutines.first(where: { $0.id == uuid }) else { return nil }
            return RoutineLoadRequest(routine: routine, isSavedRoutine: true, autoStart: true)
        } else if idStr.hasPrefix("preloaded:") {
            let uuidStr = String(idStr.dropFirst("preloaded:".count))
            guard let uuid = UUID(uuidString: uuidStr),
                  let preloaded = PreloadedRoutines.all.first(where: { $0.id == uuid }) else { return nil }
            let routine = Routine(name: preloaded.name, exercises: preloaded.exercises, kind: .workout)
            return RoutineLoadRequest(routine: routine, isSavedRoutine: false, autoStart: true)
        }
        return nil
    }

    private func checkPendingRoutine() {
        guard let idStr = UserDefaults.standard.string(forKey: pendingRoutineKey),
              let request = pendingRoutineRequest(for: idStr) else { return }
        UserDefaults.standard.removeObject(forKey: pendingRoutineKey)
        loadRoutine(request)
    }
}

#Preview {
    RootTabView()
}
