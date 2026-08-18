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
        #else
        let readyDescription = "Tap \"Start Workout\" to begin. The timer guides you through each exercise and rest period. You can also start and control your workout from an Apple Watch."
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
                title: "Add an Exercise",
                description: "Tap \"Add Exercise\" at the bottom of the list to create a new entry. Tap the exercise row to expand it and configure the name, sets, and duration."
            ),
            OnboardingStep(
                symbol: "timer",
                color: .orange,
                title: "Time-Based or Rep-Based",
                description: "Inside any exercise, use the Exercise Type picker to switch between Time-Based (a countdown timer runs automatically) and Rep-Based (you mark each set complete manually)."
            ),
            OnboardingStep(
                symbol: "link",
                color: .pink,
                title: "Create Supersets",
                description: "Pair exercises back-to-back with no rest between them — even a mix of timed and rep-based moves. Swipe an exercise to the right (or long-press it) and tap \"Superset\" to link it with the exercise above — it'll appear as a linked, indented row."
            ),
            OnboardingStep(
                symbol: "repeat",
                color: .cyan,
                title: "Repeat a Chain",
                description: "Linked exercises share one round counter instead of separate sets. The first exercise in a chain shows a \"Repeat Chain\" stepper — set how many rounds the whole group performs. Each exercise runs once per round before the last exercise's Rest Duration activates."
            ),
            OnboardingStep(
                symbol: "dumbbell.fill",
                color: .purple,
                title: "Track Your Weights",
                description: "Tap \"Add weight\" inside any exercise to log the weight you're using. Use the LB/KG toggle to match your preferred unit."
            ),
            OnboardingStep(
                symbol: "folder.fill",
                color: .teal,
                title: "Save & Load Routines",
                description: "Browse built-in routines like Athlean-X's Perfect PPL Split anytime from the folder icon in the toolbar. Ready to build your own? Tap \"Save as Routine…\" to save your current exercise list under a custom name and load it again later."
            ),
            OnboardingStep(
                symbol: "square.and.arrow.up.fill",
                color: .indigo,
                title: "Export & Import",
                description: "Tap the share icon (↑) in the toolbar to export your exercises as a JSON file — great for backups or sharing. Tap the download icon (↓) to import exercises from a file."
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
        [
            OnboardingStep(
                symbol: "sparkles",
                color: .blue,
                title: "What's New in 2.0",
                description: "A lot has changed since version 1.4 — here's a look at everything new, from a smarter Apple Watch experience to full workout routines and circuits."
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
                description: "Link exercises so they run back-to-back with no rest — even a mix of timed and rep-based moves. The first exercise in a chain gets a \"Repeat Chain\" stepper controlling how many rounds the whole group performs before everyone rests together."
            ),
            OnboardingStep(
                symbol: "applewatch",
                color: .indigo,
                title: "A Smarter Apple Watch Experience",
                description: "The Watch app now runs natively, with live workout data synced to your iPhone in real time. Starting a workout on iPhone automatically searches for your Watch, with a one-tap \"Continue on iPhone\" fallback if it can't be found."
            ),
            OnboardingStep(
                symbol: "heart.fill",
                color: .red,
                title: "Heart Rate Zones",
                description: "See your live heart rate zone and fuel type (fat, carb, mixed) during a workout, then review a full zone breakdown with BPM ranges and time-in-zone bars in your recap."
            ),
            OnboardingStep(
                symbol: "dumbbell.fill",
                color: .purple,
                title: "Track Weight, Reps & Progress",
                description: "Log the weight and target reps for any exercise, see session elapsed time during your workout, and get a full recap — sets, duration, and heart rate — the moment you finish."
            ),
            OnboardingStep(
                symbol: "plus.square.on.square",
                color: .green,
                title: "Faster to Build",
                description: "Duplicate any exercise with a swipe or long-press, and revisit this guide anytime from the question-mark button on the main screen."
            )
        ]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    ForEach(steps.indices, id: \.self) { index in
                        OnboardingPageView(step: steps[index])
                            .tag(index)
                    }
                }
                #if os(macOS)
                .tabViewStyle(.automatic)
                #else
                .tabViewStyle(.page(indexDisplayMode: .always))
                #endif

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
