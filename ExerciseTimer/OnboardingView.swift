import SwiftUI

/// A marketing version plus build number, ordered so What's New can show only newer slides.
/// Build numbers reset with each marketing version, so both parts are compared.
struct AppRelease: Comparable, Equatable {
    let version: [Int]
    let build: Int

    /// The App Store release that all What's New content is measured against.
    static let baseline = AppRelease(version: [2, 0], build: 0)

    init(version: [Int], build: Int) {
        self.version = version
        self.build = build
    }

    init(versionString: String, build: Int) {
        self.init(version: versionString.split(separator: ".").compactMap { Int($0) }, build: build)
    }

    static func < (lhs: AppRelease, rhs: AppRelease) -> Bool {
        let count = max(lhs.version.count, rhs.version.count)
        for index in 0..<count {
            let l = index < lhs.version.count ? lhs.version[index] : 0
            let r = index < rhs.version.count ? rhs.version[index] : 0
            if l != r { return l < r }
        }
        return lhs.build < rhs.build
    }

    static func == (lhs: AppRelease, rhs: AppRelease) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

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

    /// Only used for `.whatsNew`: slides introduced after this release are shown.
    var lastSeen: AppRelease = .baseline

    @Environment(\.dismiss) private var dismiss
    @State private var currentPage = 0

    private var steps: [OnboardingStep] {
        switch mode {
        case .full: return Self.fullSteps
        case .whatsNew: return Self.whatsNewSteps(since: lastSeen)
        }
    }

    /// True when at least one What's New slide was introduced after `release`.
    static func hasWhatsNew(since release: AppRelease) -> Bool {
        !whatsNewItems.filter { $0.introducedIn > release }.isEmpty
    }

    private static var fullSteps: [OnboardingStep] {
        // On Mac there's no Health tracking, Apple Watch, or screen-lock behavior, and input is
        // pointer-based — so wording and feature mentions differ from iPhone/iPad.
        #if os(macOS)
        let welcomeDescription = "Two tabs, two purposes. Use Exercises for strength-style workouts with weight and target reps. Use Timers for plain countdowns and prompts."
        let buildDescription = "Click \"Add Exercise\", then click the row to set the name, sets, and duration. Choose Time-Based (automatic countdown) or Rep-Based (you mark each set complete), and optionally add weight. Right-click an exercise and choose \"Superset\" to chain it with the one above."
        let routinesDescription = "The Routines tab holds built-in programs and your saved routines, organized in folders. Click \"Save as Routine…\" to keep your list, click a saved routine to edit it, or right-click it to export. Siri and Shortcuts can start saved routines hands-free."
        let readyDescription = "Click \"Start Workout\" to begin — click weight or target reps during a workout to adjust them on the fly. A sound plays when each exercise or rest ends. Reopen this guide anytime from the Settings tab."
        #else
        let welcomeDescription = "Two tabs, two purposes. Exercises is for workouts — it tracks weight and reps and sends your stats to the Health app. Timers is for non-exercise activities like stretching, cooking, or study intervals — plain countdowns and prompts, never recorded to Health."
        let buildDescription = "Tap \"Add Exercise\", then tap the row to set the name, sets, and duration. Choose Time-Based (automatic countdown) or Rep-Based (you mark each set complete), and optionally add weight. Swipe an exercise right (or long-press it) and tap \"Superset\" to chain it with the one above."
        let routinesDescription = "The Routines tab holds built-in programs and your saved routines, organized in folders. Tap \"Save as Routine…\" to keep your list, tap a saved routine to edit it, or swipe it to export. Siri and Shortcuts can start saved routines hands-free."
        let readyDescription = "Tap \"Start Workout\" to begin — tap weight or target reps during a workout to adjust them on the fly. Run it from your Apple Watch too: press and hold \"Reps Complete\" to confirm a set. Background Audio, Keep Screen Awake, and Heart Rate Zones live in Settings, where you can reopen this guide anytime."
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
                title: "Build & Link Exercises",
                description: buildDescription
            ),
            OnboardingStep(
                symbol: "folder.fill",
                color: .teal,
                title: "Save, Share & Launch Routines",
                description: routinesDescription
            ),
            OnboardingStep(
                symbol: "play.circle.fill",
                color: .green,
                title: "Ready to Train!",
                description: readyDescription
            )
        ]
    }

    /// One What's New slide plus the release that introduced it, so returning users only see
    /// what changed since the last release they saw.
    private struct WhatsNewItem {
        let introducedIn: AppRelease
        let step: OnboardingStep
    }

    /// Add new slides to the end, tagged with the version/build that introduces them. Everything
    /// here is newer than the App Store's 2.0 baseline.
    private static var whatsNewItems: [WhatsNewItem] {
        #if os(macOS)
        let tabsDescription = "Exercises, Timers, Routines, and Settings are now tabs instead of toolbar buttons and sheets. The Timers tab runs plain countdown or prompt-based timers — no weight or rep prompts — for anything that isn't a workout."
        let foldersDescription = "Built-in programs and your saved routines now drill into folders from the Routines tab. Click a saved routine — or right-click it and choose Edit or Export — to rename it or change its exercises without starting over."
        let progressDescription = "Click weight or target reps during a workout to adjust them on the fly — edits save back to the routine too. Recaps now break down Active vs. Rest time and any exercises or rests you skipped."
        #else
        let tabsDescription = "Exercises, Timers, Routines, and Settings are now tabs instead of toolbar buttons and sheets. The Timers tab runs plain countdown or prompt-based timers — no Health tracking, no weight or rep prompts — for anything that isn't a workout."
        let foldersDescription = "Built-in programs and your saved routines now drill into folders from the Routines tab. Tap a saved routine — or swipe it and tap Edit — to rename it or change its exercises without starting over."
        let progressDescription = "Tap weight or target reps during a workout to adjust them on the fly — edits save back to the routine too. Recaps now break down Active vs. Rest time and any exercises or rests you skipped, plus a \"Resting\" heart-rate tier pulled from Health."
        #endif

        var items: [WhatsNewItem] = [
            WhatsNewItem(
                introducedIn: AppRelease(version: [2, 1], build: 1),
                step: OnboardingStep(
                    symbol: "dumbbell.fill",
                    color: .purple,
                    title: "Mid-Session Edits & Deeper Recaps",
                    description: progressDescription
                )
            ),
            WhatsNewItem(
                introducedIn: AppRelease(version: [2, 2], build: 1),
                step: OnboardingStep(
                    symbol: "square.grid.2x2.fill",
                    color: .green,
                    title: "Tabs, Plus a New Timers Tab",
                    description: tabsDescription
                )
            ),
            WhatsNewItem(
                introducedIn: AppRelease(version: [2, 2], build: 1),
                step: OnboardingStep(
                    symbol: "folder.fill",
                    color: .teal,
                    title: "Routine Folders & In-Place Editing",
                    description: foldersDescription
                )
            ),
            WhatsNewItem(
                introducedIn: AppRelease(version: [2, 3], build: 1),
                step: OnboardingStep(
                    symbol: "link",
                    color: .pink,
                    title: "Timed Supersets Get a Whole-Chain Budget",
                    description: "A chain's first exercise can carry a shared Time Budget — choose \"Per Round\" to re-arm it every round, or the new \"Whole Chain\" option to run one deadline across every round, perfect for an AMRAP-style MetCon like 15 minutes for 10 rounds of burpees and goblet squats. Chains can also rest between individual exercises now, not just after the last one each round."
                )
            )
        ]

        // Mac has no Health tracking or Apple Watch, so these two are iPhone/iPad only.
        #if !os(macOS)
        items.append(
            WhatsNewItem(
                introducedIn: AppRelease(version: [2, 1], build: 1),
                step: OnboardingStep(
                    symbol: "heart.text.square.fill",
                    color: .red,
                    title: "Deeper Heart Rate Zone Controls",
                    description: "Settings > Heart Rate Zones shows the age Health provides for your estimate (or explains why it can't), lists the resulting five zones, and lets you override them manually. The app now defers to whatever zones you've set in Health, matching what you'd see there."
                )
            )
        )
        items.append(
            WhatsNewItem(
                introducedIn: AppRelease(version: [2, 3], build: 3),
                step: OnboardingStep(
                    symbol: "applewatch",
                    color: .indigo,
                    title: "Hold to Confirm on Apple Watch",
                    description: "\"Reps Complete\" on the Watch now needs a press-and-hold, so a stray tap from a wrist-wrapped glove or sweaty wrist can't skip your set."
                )
            )
        )
        #endif

        return items.sorted { $0.introducedIn < $1.introducedIn }
    }

    private static func whatsNewSteps(since release: AppRelease) -> [OnboardingStep] {
        let newItems = whatsNewItems.filter { $0.introducedIn > release }
        let intro = OnboardingStep(
            symbol: "sparkles",
            color: .blue,
            title: "What's New",
            description: release == .baseline
                ? "A lot has changed since version 2.0 — here's a look at everything new."
                : "Here's what's changed since the last version you used."
        )
        return [intro] + newItems.map(\.step)
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

