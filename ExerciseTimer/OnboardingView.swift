import SwiftUI

private struct OnboardingStep {
    let symbol: String
    let color: Color
    let title: String
    let description: String
}

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentPage = 0

    private var steps: [OnboardingStep] {
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
                symbol: "dumbbell.fill",
                color: .purple,
                title: "Track Your Weights",
                description: "Tap \"Add weight\" inside any exercise to log the weight you're using. Use the LB/KG toggle to match your preferred unit."
            ),
            OnboardingStep(
                symbol: "folder.fill",
                color: .teal,
                title: "Save & Load Routines",
                description: "Tap \"Save as Routine…\" to save your current exercise list under a custom name. Open the folder icon in the toolbar anytime to load a saved routine."
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
                    Button("Skip") {
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
                Text("Get Started")
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
