import SwiftUI

@main
struct ExerciseTimerApp: App {
#if DEBUG
    init() {
        // `-screenshotMode`: seed isolated demo data before any view reads it.
        ScreenshotMode.prepareIfNeeded()
    }
#endif

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
    }
}
