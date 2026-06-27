import SwiftUI

struct OnboardingFlowView: View {
    @Environment(Orchestrator.self) private var orchestrator
    @State private var currentStep = 0

    let onComplete: () -> Void

    private let steps: [OnboardingStep] = [
        OnboardingStep(
            icon: "orbit",
            title: "Welcome to Orbit",
            body: "A system that turns intent into execution. Type what you need — Orbit handles the rest."
        ),
        OnboardingStep(
            icon: "arrow.triangle.branch",
            title: "How It Works",
            body: "You give an intent. Orbit interprets your request, builds a plan, and executes it step by step — all visible to you in real time."
        ),
        OnboardingStep(
            icon: "lock.shield",
            title: "Safety Built In",
            body: "Every tool execution requires your permission. Nothing runs silently. Every action is audited and replayable from history."
        ),
        OnboardingStep(
            icon: "cpu",
            title: "Local or Cloud",
            body: "Run models locally through Ollama, or connect to OpenAI and Anthropic. Switch providers anytime in Settings."
        ),
        OnboardingStep(
            icon: "checkmark.circle.fill",
            title: "You're Ready",
            body: "Orbit is set up and waiting. Try typing \"List the files in this project\" to run your first task."
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Skip button
            HStack {
                Spacer()
                Button("Skip") {
                    complete()
                }
                .buttonStyle(.plain)
                .font(.orbitBodySmall)
                .foregroundStyle(.orbitTertiary)
                .padding(.trailing, Spacing.lg)
            }

            Spacer().frame(height: 40)

            // Card
            VStack(spacing: 28) {
                stepContent
                    .frame(maxWidth: 400)
                    .id(currentStep)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                        removal: .opacity.combined(with: .move(edge: .leading))
                    ))
            }
            .padding(32)
            .background(Color.orbitSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.orbitBorder, lineWidth: 1)
            )
            .padding(.horizontal, Spacing.lg)

            Spacer().frame(height: 32)

            // Progress dots
            HStack(spacing: 8) {
                ForEach(0..<steps.count, id: \.self) { i in
                    Circle()
                        .fill(i == currentStep ? Color.orbitAccent : Color.orbitBorder)
                        .frame(width: 8, height: 8)
                }
            }

            Spacer().frame(height: 24)

            // Navigation buttons
            HStack(spacing: 12) {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation(.easeOut(duration: 0.2)) {
                            currentStep -= 1
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                Spacer()

                Button(isLastStep ? "Enter Orbit" : "Continue") {
                    if isLastStep {
                        complete()
                    } else {
                        withAnimation(.easeOut(duration: 0.2)) {
                            currentStep += 1
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            .frame(maxWidth: 400)

            Spacer().frame(height: 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.orbitBackground)
    }

    private var isLastStep: Bool {
        currentStep == steps.count - 1
    }

    @ViewBuilder
    private var stepContent: some View {
        let step = steps[currentStep]
        VStack(spacing: 20) {
            Image(systemName: step.icon)
                .font(.system(size: 36))
                .foregroundStyle(.orbitAccent)

            Text(step.title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.orbitPrimary)
                .multilineTextAlignment(.center)

            Text(step.body)
                .font(.orbitBody)
                .foregroundStyle(.orbitSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func complete() {
        orchestrator.settings.hasCompletedOnboarding = true
        onComplete()
    }
}

private struct OnboardingStep {
    let icon: String
    let title: String
    let body: String
}
