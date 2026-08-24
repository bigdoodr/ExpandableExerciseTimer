import AppIntents
import Foundation

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
        allEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [RoutineEntity] {
        allEntities()
    }

    // Built-in routines are bundled with the app and always available; user-saved
    // routines come from UserDefaults. Both are surfaced to Siri/Shortcuts, with
    // "preloaded:"/"saved:" id prefixes so StartRoutineIntent and the main app know
    // which store to resolve the identifier against.
    private func allEntities() -> [RoutineEntity] {
        let preloaded = PreloadedRoutines.all.map {
            RoutineEntity(id: "preloaded:\($0.id.uuidString)", name: $0.name)
        }
        let saved = loadSavedRoutines().map {
            RoutineEntity(id: "saved:\($0.id.uuidString)", name: $0.name)
        }
        return preloaded + saved
    }

    private func loadSavedRoutines() -> [Routine] {
        guard let data = UserDefaults.standard.data(forKey: "savedRoutines"),
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
        UserDefaults.standard.set(routine.id, forKey: "pendingRoutineStart")
        return .result()
    }
}

// MARK: - App Shortcuts Provider
// Enables Siri voice phrases (e.g. "Hey Siri, start my Morning Strength workout")
// and surfaces routines in the Shortcuts app. Works on iOS and macOS 13+ since
// this target builds for both platforms.

@available(iOS 16.4, macOS 13.0, *)
struct ExerciseTimerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartRoutineIntent(),
            phrases: [
                "Start \(\.$routine) in \(.applicationName)",
                "Start my \(\.$routine) workout in \(.applicationName)"
            ],
            shortTitle: "Start Routine",
            systemImageName: "figure.run"
        )
    }
}
