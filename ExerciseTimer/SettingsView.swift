import SwiftUI

/// App-wide preferences that don't need to live in the exercise builder's main list —
/// moved here to keep that list focused on exercises themselves.
struct SettingsView: View {
#if canImport(UIKit)
    @Binding var keepScreenAwake: Bool
    @Binding var enableBackgroundAudio: Bool
#endif
    /// Set to true and dismissed by this view when the user taps "View Onboarding Guide" —
    /// the parent is responsible for actually presenting the guide once this sheet closes,
    /// since two sheets can't be presented from the same view at once.
    @Binding var requestOnboarding: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
#if canImport(UIKit)
                Section(footer: Text("Prevents the display from sleeping while a workout is active. This does not keep the app running in the background.")) {
                    Toggle(isOn: $keepScreenAwake) {
                        HStack {
                            Image(systemName: keepScreenAwake ? "moon.zzz.fill" : "moon.zzz")
                            Text("Keep Screen Awake")
                        }
                    }
                    .toggleStyle(.switch)
                }

                Section(footer: Text("Keeps a low-level audio session active so timers and sounds continue while the screen is locked or the app is backgrounded. May increase battery usage.")) {
                    Toggle(isOn: $enableBackgroundAudio) {
                        HStack {
                            Image(systemName: enableBackgroundAudio ? "speaker.wave.2.fill" : "speaker.slash")
                            Text("Background Audio")
                        }
                    }
                    .toggleStyle(.switch)
                }
#endif
                Section {
                    Button {
                        requestOnboarding = true
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "questionmark.circle")
                            Text("View Onboarding Guide")
                        }
                    }
                }
            }
            .navigationTitle("Settings")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
#else
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            // See RoutineManagerSheet for why macOS sheets need an explicit size.
            .frame(minWidth: 420, idealWidth: 460, minHeight: 320, idealHeight: 360)
#endif
        }
    }
}
