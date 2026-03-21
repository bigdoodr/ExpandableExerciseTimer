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
    
    private var workoutSession: HKWorkoutSession?
    
    // iOS 26+ uses HKLiveWorkoutBuilder
    // Note: Stored as Any? to avoid @available on stored property
    private var liveWorkoutBuilder: Any?
    
    // Pre-iOS 26 uses HKWorkoutBuilder
    private var legacyWorkoutBuilder: Any?
    
    func requestAuthorization() async {
        // Check if HealthKit is available on this device
        guard HKHealthStore.isHealthDataAvailable() else {
            print("HealthKit is not available on this device")
            startError = "HealthKit not available"
            isAuthorized = false
            return
        }
        
        let typesToShare: Set<HKSampleType> = [HKObjectType.workoutType()]
        let typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
        ]
        
        do {
            try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
            
            // For write permissions (workouts), we can check authorization status
            // For read permissions (heart rate), iOS may not reveal authorization status for privacy
            // So we'll check write permissions and assume success if no error was thrown
            let workoutType = HKObjectType.workoutType()
            let writeStatus = healthStore.authorizationStatus(for: workoutType)
            
            // If we can write workouts, consider it authorized
            // (Read permissions may show as .notDetermined for privacy even if granted)
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
    }
    
    func startWorkoutSession(with configuration: HKWorkoutConfiguration) async {
        startError = nil
        
        // Force-clean any stale session from a previous workout
        if workoutSession != nil {
            await cleanupSession()
        }
        
        do {
            if #available(iOS 26.0, *) {
                // iOS 26+ modern API
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
                // Legacy API for iOS versions before 26
                // Note: HKWorkoutSession and related APIs are available from iOS 10+
                // but the specific initializer and methods may vary
                startError = "Workout sessions require iOS 26.0 or later"
                print("HealthKit workout sessions require iOS 26.0+")
            }
        } catch {
            print("Failed to start workout session: \(error)")
            startError = error.localizedDescription
            // Clean up on failure
            workoutSession?.end()
            workoutSession = nil
            liveWorkoutBuilder = nil
            legacyWorkoutBuilder = nil
        }
    }
    
    private func cleanupSession() async {
        let session = workoutSession
        workoutSession = nil
        isWorkoutActive = false
        
        session?.end()
        
        if #available(iOS 26.0, *) {
            if let builder = liveWorkoutBuilder as? HKLiveWorkoutBuilder {
                liveWorkoutBuilder = nil
                do {
                    try await builder.endCollection(at: Date())
                    _ = try await builder.finishWorkout()
                } catch {
                    print("Error cleaning up iOS 26+ session: \(error)")
                }
            }
        }
        
        // Clear legacy builder if it exists
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
        
        // Clear references first to prevent stale state
        workoutSession = nil
        isWorkoutActive = false
        heartRate = 0
        activeCalories = 0
        
        // Then attempt graceful shutdown
        session?.end()
        
        if #available(iOS 26.0, *) {
            if let builder = liveWorkoutBuilder as? HKLiveWorkoutBuilder {
                liveWorkoutBuilder = nil
                do {
                    try await builder.endCollection(at: Date())
                    _ = try await builder.finishWorkout()
                } catch {
                    print("Failed to end workout: \(error)")
                }
            }
        }
        
        // Clear legacy builder if it exists
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

// MARK: - iOS 26+ Live Workout Builder Delegate

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

