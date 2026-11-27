#if DEBUG
import SwiftUI

extension View {
    /// Accessibility identifier the screenshot UI tests wait on. DEBUG only: every call site is
    /// wrapped in `#if DEBUG` too, so nothing of this reaches a Release build.
    func captureID(_ id: String) -> some View {
        accessibilityIdentifier(id)
    }
}
#endif
