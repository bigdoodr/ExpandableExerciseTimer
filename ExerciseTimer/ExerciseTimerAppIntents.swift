import AppIntents
import Foundation

// UserDefaults key that the intent writes and ExerciseListView reads on foreground
private let pendingRoutineKey = "pendingRoutineStart"
private let savedRoutinesKey = "savedRoutines"

// MARK: - Routine Entity

@available(iOS 16.0, *)
struct RoutineEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Routine"
    static var defaultQuery: RoutineEntityQuery = RoutineEntityQuery()

    var id: String          // UUID string
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: name))
    }
}

// MARK: - Entity Query

@available(iOS 16.0, *)
struct RoutineEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [RoutineEntity] {
        loadRoutines()
            .filter { identifiers.contains($0.id.uuidString) }
            .map { RoutineEntity(id: $0.id.uuidString, name: $0.name) }
    }

    func suggestedEntities() async throws -> [RoutineEntity] {
        loadRoutines().map { RoutineEntity(id: $0.id.uuidString, name: $0.name) }
    }

    private func loadRoutines() -> [Routine] {
        guard let data = UserDefaults.standard.data(forKey: savedRoutinesKey),
              let routines = try? JSONDecoder().decode([Routine].self, from: data)
        else { return [] }
        return routines
    }
}

// MARK: - Start Routine Intent

@available(iOS 16.0, *)
struct StartRoutineIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Workout Routine"
    static var description = IntentDescription(
        "Opens Exercise Timer and loads a saved workout routine so you can start immediately."
    )
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Routine", description: "The saved workout routine to load")
    var routine: RoutineEntity

    func perform() async throws -> some IntentResult {
        // Signal to the app which routine to load when it comes to foreground.
        UserDefaults.standard.set(routine.id, forKey: pendingRoutineKey)
        return .result()
    }
}

// MARK: - App Shortcuts Provider
// To enable Siri voice phrases (e.g. "Hey Siri, start my Morning Strength workout"),
// add the Siri capability in Xcode and uncomment the AppShortcutsProvider below.
//
// @available(iOS 16.4, *)
// struct ExerciseTimerShortcuts: AppShortcutsProvider {
//     static var appShortcuts: [AppShortcut] {
//         AppShortcut(
//             intent: StartRoutineIntent(),
//             phrases: [
//                 "Start \(\.$routine) in \(.applicationName)",
//                 "Start my \(\.$routine) workout in \(.applicationName)"
//             ],
//             shortTitle: "Start Routine",
//             systemImageName: "figure.run"
//         )
//     }
// }
