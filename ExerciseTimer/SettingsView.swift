import SwiftUI

/// App-wide preferences — now a tab in its own right rather than a sheet, so it stays visible
/// as the person switches between the Exercises and Timers tabs.
struct SettingsView: View {
#if canImport(UIKit)
    @AppStorage("keepScreenAwake", store: AppDefaults.store) private var keepScreenAwake = false
    @AppStorage("enableBackgroundAudio", store: AppDefaults.store) private var enableBackgroundAudio = false
#endif
    /// Called when the person taps "View Onboarding Guide" — presented directly over whichever
    /// tab is currently selected, since Settings is a tab rather than a sheet now.
    var onShowOnboarding: () -> Void = {}
    /// Forwarded to `HeartRateZonesView` so a manual-zone edit can re-push the exercise list (and
    /// the now-updated zone settings it's bundled with) to the watch.
    var onZoneSettingsChanged: () -> Void = {}
    @State private var showClearHistoryConfirm = false
    @State private var historyCount = WorkoutHistoryStore.shared.workouts.count

    var body: some View {
        NavigationStack {
            Form {
#if !os(macOS)
                // Mac has no Health data, so heart rate zones don't apply there.
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
#endif
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
                Section(footer: Text("Logged sets power \"Last time\" and progression suggestions. Stored only on this device.")) {
                    LabeledContent("Workouts Logged", value: "\(historyCount)")
                    Button("Clear Workout History", role: .destructive) { showClearHistoryConfirm = true }
                        .disabled(historyCount == 0)
                }
                .confirmationDialog("Clear all logged workouts?", isPresented: $showClearHistoryConfirm, titleVisibility: .visible) {
                    Button("Clear History", role: .destructive) {
                        WorkoutHistoryStore.shared.deleteAll()
                        historyCount = 0
                    }
                } message: {
                    Text("This removes every logged set. Saved routines aren't affected. This can't be undone.")
                }
                .onAppear { historyCount = WorkoutHistoryStore.shared.workouts.count }

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
