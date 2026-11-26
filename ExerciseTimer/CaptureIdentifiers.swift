import SwiftUI

extension View {
    /// Accessibility identifier the screenshot UI tests wait on. Compiled out of Release builds,
    /// so nothing here ships.
    @ViewBuilder
    func captureID(_ id: String) -> some View {
        #if DEBUG
        accessibilityIdentifier(id)
        #else
        self
        #endif
    }
}
