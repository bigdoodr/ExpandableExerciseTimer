import SwiftUI

/// A full-width action button that adopts Liquid Glass on iOS/macOS 26 and later — via
/// `.buttonStyle(.glassProminent)` tinted to match the button's role — falling back to the
/// app's existing filled-rounded-rectangle style on earlier OS versions.
struct GlassActionButton<Label: View>: View {
    let tint: Color
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            Button(action: action) {
                label()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.glassProminent)
            .tint(tint)
        } else {
            Button(action: action) {
                label()
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 8)
                    .background(tint)
                    .cornerRadius(12)
            }
        }
    }
}
