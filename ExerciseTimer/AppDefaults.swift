import Foundation

/// The UserDefaults the app reads and writes its own state from. It's always `.standard`, except
/// in DEBUG screenshot mode, which points it at a throwaway suite so seeded demo data never
/// touches the real preferences, saved routines or onboarding flags.
enum AppDefaults {
    static let store: UserDefaults = {
        #if DEBUG
        if ScreenshotMode.isActive, let suite = ScreenshotMode.defaultsSuite { return suite }
        #endif
        return .standard
    }()
}
