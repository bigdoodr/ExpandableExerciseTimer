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
        // On Mac there's no Health tracking, Apple Watch, or screen-lock behavior, and input is
        // pointer-based — so wording and feature mentions differ from iPhone/iPad.
        #if os(macOS)
        let welcomeDescription = "Build custom workouts from scratch or load saved routines on the Exercises tab, or switch to Timers for plain countdowns and prompts. This guide walks through everything you need to get started."
        let buildDescription = "Click \"Add Exercise\" to create a new entry, then click the row to expand it and set the name, sets, and duration. Use the Exercise Type picker to switch between Time-Based (an automatic countdown) and Rep-Based (you mark each set complete manually), and click \"Add weight\" to log what you're lifting with the LB/KG toggle."
        let supersetDescription = "Swipe an exercise right with two fingers on your trackpad (or right-click it) and choose \"Superset\" to link it with the exercise above, pairing moves back-to-back — even a mix of timed and rep-based — with an optional \"Rest Before Next Exercise\" between them. Linked exercises share one round counter: the first shows a \"Repeat Chain\" stepper for rounds and a Time Budget you can scope \"Per Round\" (re-arms every round) or \"Whole Chain\" (one deadline shared across all rounds, ideal for an AMRAP-style MetCon)."
        let routinesDescription = "Switch to the Routines tab to browse built-in programs like Athlean-X's Perfect PPL Split, organized into folders — or click \"Save as Routine…\" here to save your current list under a custom name and category. Click a saved routine to rename it or edit its exercises in place, right-click (or swipe) it to export it as a JSON file, or use Import to bring one back in. Saved routines can also be started hands-free with Siri or the Shortcuts app."
        let settingsTitle = "Sound & Guide"
        let settingsDescription = "A sound plays when each exercise or rest period ends. Reopen this guide anytime from the Settings tab."
        let readyDescription = "Click \"Start Workout\" to begin. The timer guides you through each exercise and rest period — click weight or target reps during a workout to adjust them on the fly."
        #else
        let welcomeDescription = "Build custom workouts from scratch or load saved routines on the Exercises tab, or switch to Timers for plain countdowns and prompts that don't need Health tracking. This guide walks through everything you need to get started."
        let buildDescription = "Tap \"Add Exercise\" to create a new entry, then tap the row to expand it and set the name, sets, and duration. Use the Exercise Type picker to switch between Time-Based (an automatic countdown) and Rep-Based (you mark each set complete manually), and tap \"Add weight\" to log what you're lifting with the LB/KG toggle."
        let supersetDescription = "Swipe an exercise right (or long-press it) and tap \"Superset\" to link it with the exercise above, pairing moves back-to-back — even a mix of timed and rep-based — with an optional \"Rest Before Next Exercise\" between them. Linked exercises share one round counter: the first shows a \"Repeat Chain\" stepper for rounds and a Time Budget you can scope \"Per Round\" (re-arms every round) or \"Whole Chain\" (one deadline shared across all rounds, ideal for an AMRAP-style MetCon)."
        let routinesDescription = "Switch to the Routines tab to browse built-in programs like Athlean-X's Perfect PPL Split, organized into folders — or tap \"Save as Routine…\" here to save your current list under a custom name and category. Tap a saved routine (or swipe it) to rename it or edit its exercises in place, swipe to export it as a JSON file, or use Import to bring one back in. Saved routines can also be started hands-free with Siri or the Shortcuts app."
        let settingsTitle = "Sound & Settings"
        let readyDescription = "Tap \"Start Workout\" to begin. The timer guides you through each exercise and rest period — tap weight or target reps during a workout to adjust them on the fly. You can also start and control your workout from an Apple Watch, Skip button included."
        let settingsDescription = "A sound plays when each exercise or rest period ends. Turn on Background Audio in Settings to keep that cue — and any music or podcast you're playing — going when your screen locks or you switch apps. Keep Screen Awake lives there too, along with Heart Rate Zones, which shows the age Health provides (or explains why it can't) and lets you override your zones manually. Reopen this guide anytime from the Settings tab."
        #endif

        return [
            OnboardingStep(
                symbol: "star.circle.fill",
                color: .blue,
                title: "Welcome to Exercise Timer",
                description: welcomeDescription
            ),
            OnboardingStep(
                symbol: "plus.circle.fill",
                color: .green,
                title: "Build Your Workout",
                description: buildDescription
            ),
            OnboardingStep(
                symbol: "link",
                color: .pink,
                title: "Supersets, Circuits & Timed Budgets",
                description: supersetDescription
            ),
            OnboardingStep(
                symbol: "folder.fill",
                color: .teal,
                title: "Organize, Share & Launch Routines",
                description: routinesDescription
            ),
            OnboardingStep(
                symbol: "speaker.wave.2.fill",
                color: .indigo,
                title: settingsTitle,
                description: settingsDescription
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
        // The Apple Watch Skip button/persisted-settings step depends on WatchConnectivity,
        // which doesn't exist on macOS — so that step doesn't apply there.
        #if os(macOS)
        let introDescription = "A lot has changed since version 2.0 — here's a look at everything new, from a dedicated Timers tab to Timed Supersets with a whole-chain budget."
        #else
        let introDescription = "A lot has changed since version 2.0 — here's a look at everything new, from a dedicated Timers tab to Timed Supersets with a whole-chain budget and deeper Heart Rate Zone controls."
        #endif

        // Mac has no Health tracking, so the Heart Rate Zones step is iPhone/iPad only.
        #if !os(macOS)
        let zonesDescription = "Settings > Heart Rate Zones shows the age Health provides for your estimate (or explains why it can't), lists the resulting five zones, and lets you override them manually. The app now defers to whatever zones you've set in Health, matching what you'd see there."
        #endif

        #if os(macOS)
        let progressDescription = "Click weight or target reps during a workout to adjust them on the fly — edits save back to the routine too. Recaps now break down Active vs. Rest time and any exercises or rests you skipped."
        #else
        let progressDescription = "Tap weight or target reps during a workout to adjust them on the fly — edits save back to the routine too. Recaps now break down Active vs. Rest time and any exercises or rests you skipped, plus a \"Resting\" heart-rate tier pulled from Health."
        #endif

        #if os(macOS)
        let tabsDescription = "Exercises, Timers, Routines, and Settings are now tabs instead of toolbar buttons and sheets. The Timers tab runs plain countdown or prompt-based timers — no weight or rep prompts — for anything that isn't a workout."
        let foldersDescription = "Built-in programs and your saved routines now drill into folders from the Routines tab instead of a flat list. Click a saved routine — or right-click it and choose Edit or Export — to rename it or change its exercises without starting over, and start any saved routine hands-free with Siri or the Shortcuts app."
        #else
        let tabsDescription = "Exercises, Timers, Routines, and Settings are now tabs instead of toolbar buttons and sheets. The Timers tab runs plain countdown or prompt-based timers — no Health tracking, no weight or rep prompts — for anything that isn't a workout."
        let foldersDescription = "Built-in programs and your saved routines now drill into folders from the Routines tab instead of a flat list. Tap a saved routine — or swipe it and tap Edit — to rename it or change its exercises without starting over, and start any saved routine hands-free with Siri or the Shortcuts app."
        #endif

        var steps: [OnboardingStep] = [
            OnboardingStep(
                symbol: "sparkles",
                color: .blue,
                title: "What's New in 2.3",
                description: introDescription
            ),
            OnboardingStep(
                symbol: "square.grid.2x2.fill",
                color: .green,
                title: "Tabs, Plus a New Timers Tab",
                description: tabsDescription
            ),
            OnboardingStep(
                symbol: "folder.fill",
                color: .teal,
                title: "Routine Folders & In-Place Editing",
                description: foldersDescription
            ),
            OnboardingStep(
                symbol: "link",
                color: .pink,
                title: "Timed Supersets Get a Whole-Chain Budget",
                description: "A chain's first exercise can carry a shared Time Budget — choose \"Per Round\" to re-arm it every round, or the new \"Whole Chain\" option to run one deadline across every round, perfect for an AMRAP-style MetCon like 15 minutes for 10 rounds of burpees and goblet squats. Chains can also rest between individual exercises now, not just after the last one each round."
            )
        ]

        #if !os(macOS)
        steps.append(
            OnboardingStep(
                symbol: "heart.text.square.fill",
                color: .red,
                title: "Deeper Heart Rate Zone Controls",
                description: zonesDescription
            )
        )
        steps.append(
            OnboardingStep(
                symbol: "applewatch",
                color: .indigo,
                title: "Apple Watch Gets a Skip Button",
                description: "The Watch now has its own Skip button to match iPhone's, and Keep Screen Awake / Background Audio settings in Settings stick between launches instead of resetting."
            )
        )
        #endif

        steps.append(
            OnboardingStep(
                symbol: "dumbbell.fill",
                color: .purple,
                title: "Mid-Session Edits & Deeper Recaps",
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

