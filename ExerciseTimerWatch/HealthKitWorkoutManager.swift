import Foundation
import HealthKit

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
    
    func startWorkoutSession(with configuration: HKWorkoutConfiguration) {
        guard workoutSession == nil else { return }
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
            Task {
                do {
                    try await workoutBuilder?.beginCollection(at: startDate)
                } catch {
                    print("Failed to begin collection: \(error)")
                }
            }
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
        guard let session = workoutSession, let builder = workoutBuilder else { return }
        session.end()
        do {
            try await builder.endCollection(at: Date())
            try await builder.finishWorkout()
        } catch {
            print("Failed to end workout: \(error)")
        }
        workoutSession = nil
        workoutBuilder = nil
        isWorkoutActive = false
        heartRate = 0
        activeCalories = 0
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
    
    private func updateHeartRate(from statistics: HKStatistics?) {
        guard let statistics else { return }
        guard let quantity = statistics.mostRecentQuantity() else { return }
        let bpm = quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        Task { @MainActor in
            self.heartRate = bpm
        }
    }
    
    private func updateActiveCalories(from statistics: HKStatistics?) {
        guard let statistics else { return }
        guard let quantity = statistics.sumQuantity() else { return }
        let cal = quantity.doubleValue(for: .kilocalorie())
        Task { @MainActor in
            self.activeCalories = cal
        }
    }
}

extension HealthKitWorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                     didChangeTo toState: HKWorkoutSessionState,
                                     from fromState: HKWorkoutSessionState,
                                     date: Date) {
        // State changes handled via commands from iOS
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
                    self.updateHeartRate(from: statistics)
                case HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned):
                    self.updateActiveCalories(from: statistics)
                default:
                    break
                }
            }
        }
    }
}
