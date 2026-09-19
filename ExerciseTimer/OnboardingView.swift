import SwiftUI

private struct OnboardingStep {
    let symbol: String
    let color: Color
    let title: String
    let description: String
}

struct OnboardingView: View {
    enum Mode: Equatable {
        /// The full walkthrough shown on first launch, or on demand from the main screen.
        case full
        /// A condensed set of steps highlighting only what changed in the latest update.
        case whatsNew
    }

    var mode: Mode = .full

    @Environment(\.dismiss) private var dismiss
    @State private var currentPage = 0

    private var steps: [OnboardingStep] {
        switch mode {
        case .full: return Self.fullSteps
        case .whatsNew: return Self.whatsNewSteps
        }
    }

    private static var fullSteps: [OnboardingStep] {
        #if os(macOS)
        let readyDescription = "Tap \"Start Workout\" to begin. The timer guides you through each exercise and rest period."
        let audioSettingsDescription = "A sound plays when each exercise or rest period ends. Reopen this guide anytime from the gear icon in the toolbar."
        #else
        let readyDescription = "Tap \"Start Workout\" to begin. The timer guides you through each exercise and rest period. You can also start and control your workout from an Apple Watch."
        let audioSettingsDescription = "A sound plays when each exercise or rest period ends. Turn on Background Audio in Settings to keep that cue — and any music or podcast you're playing — going when your screen locks or you switch apps. Keep Screen Awake lives there too. Reopen this guide anytime from the gear icon in the toolbar."
        #endif

        return [
            OnboardingStep(
                symbol: "star.circle.fill",
                color: .blue,
                title: "Welcome to Exercise Timer",
                description: "Build custom workouts from scratch or load saved routines. This guide walks through everything you need to get started."
            ),
            OnboardingStep(
                symbol: "plus.circle.fill",
                color: .green,
                title: "Build Your Workout",
                description: "Tap \"Add Exercise\" to create a new entry, then tap the row to expand it and set the name, sets, and duration. Use the Exercise Type picker to switch between Time-Based (an automatic countdown) and Rep-Based (you mark each set complete manually), and tap \"Add weight\" to log what you're lifting with the LB/KG toggle."
            ),
            OnboardingStep(
                symbol: "link",
                color: .pink,
                title: "Supersets & Repeat Chains",
                description: "Swipe an exercise right (or long-press it) and tap \"Superset\" to link it with the exercise above, pairing moves back-to-back with no rest — even a mix of timed and rep-based. Linked exercises share one round counter: the first shows a \"Repeat Chain\" stepper to set how many rounds the group performs, with the last exercise's Rest Duration applying once per round."
            ),
            OnboardingStep(
                symbol: "folder.fill",
                color: .teal,
                title: "Save, Load & Share Routines",
                description: "Browse built-in routines like Athlean-X's Perfect PPL Split anytime from the folder icon, or tap \"Save as Routine…\" to save your current list under a custom name. Tap the share icon (↑) to export your exercises as a JSON file for backups or sharing, and the download icon (↓) to import them."
            ),
            OnboardingStep(
                symbol: "speaker.wave.2.fill",
                color: .indigo,
                title: "Sound & Settings",
                description: audioSettingsDescription
            ),
            OnboardingStep(
                symbol: "play.circle.fill",
                color: .green,
                title: "Ready to Train!",
                description: readyDescription
            )
        ]
    }

    private static var whatsNewSteps: [OnboardingStep] {
        // The Watch app and Heart Rate Zones both depend on WatchConnectivity/HealthKit,
        // neither of which exist on macOS — so those two steps don't apply there.
        #if os(macOS)
        let introDescription = "A lot has changed since version 1.4 — here's a look at everything new, from full workout routines and circuits to Siri and Shortcuts support."
        #else
        let introDescription = "A lot has changed since version 1.4 — here's a look at everything new, from a smarter Apple Watch experience to full workout routines and circuits."
        #endif

        var steps: [OnboardingStep] = [
            OnboardingStep(
                symbol: "sparkles",
                color: .blue,
                title: "What's New in 2.0",
                description: introDescription
            ),
            OnboardingStep(
                symbol: "books.vertical.fill",
                color: .teal,
                title: "Built-In & Custom Routines",
                description: "Save your own routines and load them anytime from the folder icon — or browse built-in programs like Athlean-X's Perfect PPL Split and Arnold's circuit workout. You can also start any saved routine hands-free with Siri or the Shortcuts app."
            ),
            OnboardingStep(
                symbol: "link",
                color: .pink,
                title: "Supersets & Circuits",
                description: "Link exercises so they run back-to-back with no rest — even a mix of timed and rep-based moves. The first exercise in a chain gets a \"Repeat Chain\" stepper to set how many rounds the whole group performs, and only the last exercise's Rest Duration applies, once per round."
            )
        ]

        #if !os(macOS)
        steps.append(
            OnboardingStep(
                symbol: "applewatch",
                color: .indigo,
                title: "A Smarter Apple Watch Experience",
                description: "The Watch app now runs natively, with live workout data synced to your iPhone in real time — starting a workout on iPhone automatically searches for your Watch, with a one-tap \"Continue on iPhone\" fallback if it can't be found. During a workout, see your live heart rate zone and fuel type, then review a full zone breakdown in your recap."
            )
        )
        #endif

        #if os(macOS)
        let progressDescription = "Log the weight and target reps for any exercise, see session elapsed time during your workout, and get a full recap — sets and duration — the moment you finish. Duplicate any exercise with a swipe or long-press, and revisit this guide anytime from the question-mark button on the main screen."
        #else
        let progressDescription = "Log the weight and target reps for any exercise, see session elapsed time during your workout, and get a full recap — sets, duration, and heart rate — the moment you finish. Duplicate any exercise with a swipe or long-press, and revisit this guide anytime from the question-mark button on the main screen."
        #endif

        steps.append(
            OnboardingStep(
                symbol: "dumbbell.fill",
                color: .purple,
                title: "Track Progress & Build Faster",
                description: progressDescription
            )
        )

        return steps
    }

    var body: some View {
        NavigationStack {
            #if os(macOS)
            // TabView's automatic style injects a native segmented page
            // switcher above the content whose visibility depends on how
            // tall the current page's text is, which shifts the Next button.
            // Switching pages by hand instead avoids that control entirely.
            // The button is then pinned via an overlay rather than sequential
            // VStack layout, because a page's own Spacer-driven centering can
            // still consume a different amount of total height depending on
            // how many lines its description wraps to — an overlay anchors
            // the button to a fixed position regardless of what the page
            // above it does with its space.
            OnboardingPageView(step: steps[currentPage])
                .id(currentPage)
                .transition(.opacity)
                // Reserves room so the overlaid button below never sits on
                // top of a long description.
                .padding(.bottom, 90)
                .frame(width: 480, height: 500)
                .overlay(alignment: .bottom) {
                    actionButton
                        .padding(.horizontal, 32)
                        .padding(.bottom, 32)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(mode == .whatsNew ? "Close" : "Skip") {
                            dismiss()
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            #else
            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    ForEach(steps.indices, id: \.self) { index in
                        OnboardingPageView(step: steps[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                actionButton
                    .padding(.horizontal, 32)
                    .padding(.bottom, 32)
                    .padding(.top, 16)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(mode == .whatsNew ? "Close" : "Skip") {
                        dismiss()
                    }
                    .foregroundStyle(.secondary)
                }
            }
            #endif
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if currentPage < steps.count - 1 {
            Button {
                withAnimation {
                    currentPage += 1
                }
            } label: {
                Text("Next")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        } else {
            Button {
                dismiss()
            } label: {
                Text(mode == .whatsNew ? "Done" : "Get Started")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}

private struct OnboardingPageView: View {
    let step: OnboardingStep

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            ZStack {
                Circle()
                    .fill(step.color.opacity(0.12))
                    .frame(width: 150, height: 150)

                Image(systemName: step.symbol)
                    .font(.system(size: 70))
                    .foregroundStyle(step.color)
                    .symbolRenderingMode(.hierarchical)
            }

            VStack(spacing: 16) {
                Text(step.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text(step.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 28)
    }
}

