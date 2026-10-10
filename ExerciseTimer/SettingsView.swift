import SwiftUI

/// App-wide preferences — now a tab in its own right rather than a sheet, so it stays visible
/// as the person switches between the Exercises and Timers tabs.
struct SettingsView: View {
#if canImport(UIKit)
    @AppStorage("keepScreenAwake") private var keepScreenAwake = false
    @AppStorage("enableBackgroundAudio") private var enableBackgroundAudio = false
#endif
    /// Called when the person taps "View Onboarding Guide" — presented directly over whichever
    /// tab is currently selected, since Settings is a tab rather than a sheet now.
    var onShowOnboarding: () -> Void = {}
    /// Forwarded to `HeartRateZonesView` so a manual-zone edit can re-push the exercise list (and
    /// the now-updated zone settings it's bundled with) to the watch.
    var onZoneSettingsChanged: () -> Void = {}

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        HeartRateZonesView(onSettingsChanged: onZoneSettingsChanged)
                    } label: {
                        HStack {
                            Image(systemName: "heart.fill")
                            Text("Heart Rate Zones")
                        }
                    }
                }
#if canImport(UIKit)
                Section(footer: Text("Prevents the display from sleeping while a session is active. This does not keep the app running in the background.")) {
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
                        onShowOnboarding()
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
#endif
        }
    }
}
