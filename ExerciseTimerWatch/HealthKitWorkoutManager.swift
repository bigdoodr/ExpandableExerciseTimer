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
    @Published var authorizationRequested = false
    
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    
    func requestAuthorization() async {
        guard !authorizationRequested else { return }
        let typesToShare: Set<HKSampleType> = [HKObjectType.workoutType()]
        let typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
        ]
        do {
            try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
            authorizationRequested = true
        } catch {
            print("HealthKit authorization failed: \(error)")
        }
    }
    
    func startWorkoutSession(with configuration: HKWorkoutConfiguration) async {
        // Force-clean any stale session from a previous workout
        if workoutSession != nil {
            await endWorkout()
        }
        do {
            workoutSession = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            workoutBuilder = workoutSession?.associatedWorkoutBuilder()
            workoutBuilder?.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )
            workoutSession?.delegate = self
            workoutBuilder?.delegate = self
            
            let startDate = Date()
            workoutSession?.startActivity(with: startDate)
            try await workoutBuilder?.beginCollection(at: startDate)
            isWorkoutActive = true
        } catch {
            print("Failed to start workout session: \(error)")
        }
    }
    
    func pauseWorkout() {
        workoutSession?.pause()
    }
    
    func resumeWorkout() {
        workoutSession?.resume()
    }
    
    func endWorkout() async {
        let session = workoutSession
        let builder = workoutBuilder
        
        // Clear references first to prevent stale state
        workoutSession = nil
        workoutBuilder = nil
        isWorkoutActive = false
        heartRate = 0
        activeCalories = 0
        
        // Then attempt graceful shutdown
        session?.end()
        if let builder {
            do {
                try await builder.endCollection(at: Date())
                try await builder.finishWorkout()
            } catch {
                print("Failed to end workout: \(error)")
            }
        }
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
