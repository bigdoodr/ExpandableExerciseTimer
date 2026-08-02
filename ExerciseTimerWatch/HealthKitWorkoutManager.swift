import Foundation
import HealthKit
internal import Combine

@MainActor
final class HealthKitWorkoutManager: NSObject, ObservableObject {
    static let shared = HealthKitWorkoutManager()

    let healthStore = HKHealthStore()

    @Published var isWorkoutActive = false
    @Published var heartRate: Double = 0
    @Published var activeCalories: Double = 0
    @Published var startError: String?
    @Published var isAuthorized = false
    /// Estimated max heart rate derived from user's date of birth (220 − age).
    /// Falls back to 185 BPM if DOB is unavailable. Used as fallback zone boundary seed.
    @Published var maxHeartRate: Double = 185.0
    /// Zero-based index of the current HR zone, driven by HealthKit's live zone delegate.
    @Published var currentHRZoneIndex: Int? = nil
    /// The finished HKWorkout after endWorkout() completes; provides zoneGroupsByType for recap.
    @Published var finishedWorkout: HKWorkout? = nil

    /// Throttle for forwarding health data to iPhone via WatchConnectivity
    private var lastHealthDataForward: Date = .distantPast

    private var workoutSession: HKWorkoutSession?

    // Stored as Any? so the stored property doesn't require @available
    private var liveWorkoutBuilder: Any?

    // Unused legacy slot kept to avoid breaking any future migration code
    private var legacyWorkoutBuilder: Any?

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("HealthKit is not available on this device")
            startError = "HealthKit not available"
            isAuthorized = false
            return
        }

        let typesToShare: Set<HKSampleType> = [HKObjectType.workoutType()]
        let typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!
        ]

        do {
            try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)

            // Read permissions may show as .notDetermined for privacy even if granted.
            // Check write permission as a proxy for overall authorization.
            let writeStatus = healthStore.authorizationStatus(for: HKObjectType.workoutType())
            isAuthorized = (writeStatus == .sharingAuthorized)

            if !isAuthorized {
                print("HealthKit write authorization status: \(writeStatus.rawValue)")
                startError = "HealthKit permission denied. Please grant access in Settings."
            } else {
                print("HealthKit authorization granted")
                startError = nil
            }
        } catch {
            print("HealthKit authorization failed: \(error)")
            startError = "Authorization failed: \(error.localizedDescription)"
            isAuthorized = false
        }

        // Attempt DOB fetch regardless of write auth — characteristic reads are separate.
        fetchMaxHeartRate()
    }

    /// Computes max heart rate as 220 − age using the user's HealthKit date of birth.
    /// Used as the boundary seed when the person has no preferred zone config in Health Settings.
    func fetchMaxHeartRate() {
        do {
            let dob = try healthStore.dateOfBirthComponents()
            let currentYear = Calendar.current.component(.year, from: Date())
            if let birthYear = dob.year {
                let age = currentYear - birthYear
                if age > 10 && age < 100 {
                    maxHeartRate = Double(220 - age)
                }
            }
        } catch {
            // Keep default if DOB is unavailable or not granted
        }
    }

    /// Prepares a workout session without starting it, causing watchOS to surface the app on wrist raise.
    /// Call this on receipt of the `.wake` command so the Watch app is ready before the user acts.
    func prepareWorkoutSession(with configuration: HKWorkoutConfiguration) async {
        guard workoutSession == nil else { return }
#if os(watchOS)
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            session.delegate = self
            self.workoutSession = session
            session.prepare()
        } catch {
            print("Failed to prepare workout session: \(error)")
        }
#endif
    }

    func startWorkoutSession(with configuration: HKWorkoutConfiguration) async {
        startError = nil
        finishedWorkout = nil
        currentHRZoneIndex = nil

        do {
            // On watchOS, HKWorkoutSession + HKLiveWorkoutBuilder have been available
            // since watchOS 5 — no runtime availability check is needed.
            // On iOS, this API requires iOS 26+.
#if os(watchOS)
            // Reuse a session already in .prepared state (set up by prepareWorkoutSession on .wake),
            // so the Watch app stays surfaced without a visible gap.
            let session: HKWorkoutSession
            if let existing = workoutSession, existing.state == .prepared {
                session = existing
            } else {
                if workoutSession != nil { await cleanupSession() }
                session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
                session.delegate = self
                self.workoutSession = session
            }
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )
            builder.delegate = self
            self.liveWorkoutBuilder = builder

            // Use the person's preferred HR zone config from Health Settings automatically.
            // Only set a custom fallback (5-zone, 220-age boundaries) if no preferred config exists.
            let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
            if (try? await builder.zoneConfiguration(for: hrType)) == nil {
                let bpm = HKUnit.count().unitDivided(by: .minute())
                let maxHR = maxHeartRate
                let boundaries = [0.50, 0.60, 0.70, 0.85].map {
                    HKQuantity(unit: bpm, doubleValue: maxHR * $0)
                }
                try? await builder.setCustomZoneConfiguration(
                    HKWorkoutZoneConfiguration(quantityType: hrType, zoneBoundaries: boundaries),
                    for: hrType
                )
            }

            let startDate = Date()
            session.startActivity(with: startDate)
            try await builder.beginCollection(at: startDate)
            isWorkoutActive = true
#else
            // Force-clean any stale session from a previous workout
            if workoutSession != nil {
                await cleanupSession()
            }
            if #available(iOS 26.0, *) {
                let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
                let builder = session.associatedWorkoutBuilder()
                builder.dataSource = HKLiveWorkoutDataSource(
                    healthStore: healthStore,
                    workoutConfiguration: configuration
                )
                session.delegate = self
                builder.delegate = self
                self.workoutSession = session
                self.liveWorkoutBuilder = builder
                let startDate = Date()
                session.startActivity(with: startDate)
                try await builder.beginCollection(at: startDate)
                isWorkoutActive = true
            } else {
                startError = "Workout sessions require iOS 26.0 or later"
                print("HealthKit workout sessions require iOS 26.0+")
            }
#endif
        } catch {
            print("Failed to start workout session: \(error)")
            startError = error.localizedDescription
            workoutSession?.end()
            workoutSession = nil
            liveWorkoutBuilder = nil
        }
    }

    private func cleanupSession() async {
        let session = workoutSession
        workoutSession = nil
        isWorkoutActive = false
        session?.end()

#if os(watchOS)
        if let builder = liveWorkoutBuilder as? HKLiveWorkoutBuilder {
            liveWorkoutBuilder = nil
            do {
                try await builder.endCollection(at: Date())
                _ = try await builder.finishWorkout()
            } catch {
                print("Error cleaning up session: \(error)")
            }
        }
#else
        if #available(iOS 26.0, *),
           let builder = liveWorkoutBuilder as? HKLiveWorkoutBuilder {
            liveWorkoutBuilder = nil
            do {
                try await builder.endCollection(at: Date())
                _ = try await builder.finishWorkout()
            } catch {
                print("Error cleaning up session: \(error)")
            }
        }
#endif
        legacyWorkoutBuilder = nil
    }

    func pauseWorkout() {
        workoutSession?.pause()
    }

    func resumeWorkout() {
        workoutSession?.resume()
    }

    func endWorkout() async {
        let session = workoutSession
        workoutSession = nil
        isWorkoutActive = false
        heartRate = 0
        activeCalories = 0
        currentHRZoneIndex = nil

        session?.end()

#if os(watchOS)
        if let builder = liveWorkoutBuilder as? HKLiveWorkoutBuilder {
            liveWorkoutBuilder = nil
            do {
                try await builder.endCollection(at: Date())
                finishedWorkout = try await builder.finishWorkout()
            } catch {
                print("Failed to end workout: \(error)")
            }
        }
#else
        if #available(iOS 26.0, *),
           let builder = liveWorkoutBuilder as? HKLiveWorkoutBuilder {
            liveWorkoutBuilder = nil
            do {
                try await builder.endCollection(at: Date())
                _ = try await builder.finishWorkout()
            } catch {
                print("Failed to end workout: \(error)")
            }
        }
#endif
        legacyWorkoutBuilder = nil
    }

    static func workoutConfiguration(for activityTypeName: String?) -> HKWorkoutConfiguration {
        let config = HKWorkoutConfiguration()
        config.activityType = activityType(from: activityTypeName)
        config.locationType = .indoor
        return config
    }

    private static func activityType(from name: String?) -> HKWorkoutActivityType {
        guard let name else { return .other }
        switch name {
        case WorkoutActivityOption.traditionalStrengthTraining.rawValue:
            return .traditionalStrengthTraining
        case WorkoutActivityOption.highIntensityIntervalTraining.rawValue:
            return .highIntensityIntervalTraining
        case WorkoutActivityOption.yoga.rawValue:
            return .yoga
        case WorkoutActivityOption.flexibility.rawValue:
            return .flexibility
        case WorkoutActivityOption.coreTraining.rawValue:
            return .coreTraining
        case WorkoutActivityOption.functionalStrengthTraining.rawValue:
            return .functionalStrengthTraining
        case WorkoutActivityOption.mixedCardio.rawValue:
            return .mixedCardio
        default:
            return .other
        }
    }
}

extension HealthKitWorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                     didChangeTo toState: HKWorkoutSessionState,
                                     from fromState: HKWorkoutSessionState,
                                     date: Date) {
        Task { @MainActor in
            switch toState {
            case .running:
                self.isWorkoutActive = true
            case .ended:
                if self.isWorkoutActive {
                    self.isWorkoutActive = false
                }
            default:
                break
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                     didFailWithError error: any Error) {
        print("Workout session failed: \(error)")
    }
}

// MARK: - Live Workout Builder Delegate

// On watchOS, HKLiveWorkoutBuilderDelegate is available unconditionally (watchOS 5+).
// On iOS, it requires iOS 26+.
#if os(watchOS)
extension HealthKitWorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // Events collected automatically
    }

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                                     didCollectDataOf collectedTypes: Set<HKSampleType>) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType else { continue }
            let statistics = workoutBuilder.statistics(for: quantityType)

            Task { @MainActor in
                switch quantityType {
                case HKQuantityType.quantityType(forIdentifier: .heartRate):
                    if let statistics, let quantity = statistics.mostRecentQuantity() {
                        self.heartRate = quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                    }
                case HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned):
                    if let statistics, let quantity = statistics.sumQuantity() {
                        self.activeCalories = quantity.doubleValue(for: .kilocalorie())
                    }
                default:
                    break
                }
                // Forward data to iPhone in the background (throttled to every 2s).
                // This ensures metrics arrive even when the watch screen is off.
                self.forwardHealthDataIfNeeded()
            }
        }
    }

    /// Fires when the person's HR crosses a zone boundary during an active workout.
    /// Publishes the new zero-based zone index so the view can update the display and play haptics.
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                                     didUpdateWorkoutZone zoneUpdate: HKLiveWorkoutBuilder.ZoneUpdate) {
        let newIndex = zoneUpdate.newZoneDuration?.zone.index
        Task { @MainActor in
            self.currentHRZoneIndex = newIndex
        }
    }
}

extension HealthKitWorkoutManager {
    /// Forwards current health data to iPhone via WatchConnectivity, throttled to every 2 seconds.
    func forwardHealthDataIfNeeded() {
        guard isWorkoutActive else { return }
        let now = Date()
        guard now.timeIntervalSince(lastHealthDataForward) >= 2.0 else { return }
        lastHealthDataForward = now
        WatchConnectivityManager.shared.sendWorkoutCommand(
            .healthData(heartRate: heartRate, activeCalories: activeCalories)
        )
    }
}
#else
@available(iOS 26.0, *)
extension HealthKitWorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // Events collected automatically
    }

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                                     didCollectDataOf collectedTypes: Set<HKSampleType>) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType else { continue }
            let statistics = workoutBuilder.statistics(for: quantityType)

            Task { @MainActor in
                switch quantityType {
                case HKQuantityType.quantityType(forIdentifier: .heartRate):
                    if let statistics, let quantity = statistics.mostRecentQuantity() {
                        self.heartRate = quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                    }
                case HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned):
                    if let statistics, let quantity = statistics.sumQuantity() {
                        self.activeCalories = quantity.doubleValue(for: .kilocalorie())
                    }
                default:
                    break
                }
            }
        }
    }
}
#endif
