import SwiftUI

// MARK: - Animation Tokens

/// System-wide animation tokens. Every view must derive animations from these tokens.
/// No view-specific animation values unless explicitly overridden with a documented reason.
enum AnimationToken {
    // MARK: - Durations

    enum Duration {
        /// Micro-interactions: copy feedback, edit toggle, tab switch (0.15s)
        static let quick: Double = 0.15
        /// Standard toggles: expand/collapse, group reveal (0.2s)
        static let standard: Double = 0.2
        /// Medium transitions: panel show/hide, state changes (0.3s)
        static let medium: Double = 0.3
        /// Slow content appearance: step cards, streaming tokens (0.35s)
        static let slow: Double = 0.35
    }

    // MARK: - Easing Curves

    enum Ease {
        static let quickOut: Animation = .easeOut(duration: Duration.quick)
        static let standardOut: Animation = .easeOut(duration: Duration.standard)
        static let mediumOut: Animation = .easeOut(duration: Duration.medium)
        static let slowOut: Animation = .easeOut(duration: Duration.slow)
        static let mediumInOut: Animation = .easeInOut(duration: Duration.medium)
        static let slowInOut: Animation = .easeInOut(duration: Duration.slow)
    }

    // MARK: - Springs

    enum Spring {
        /// Layout changes: sidebar, inspector, resizable panels
        static let interactive: Animation = .interactiveSpring(response: 0.25, dampingFraction: 0.9)
    }

    // MARK: - Transitions

    enum Transition {
        static let `default`: AnyTransition = .opacity
        static let fadeIn: AnyTransition = .opacity
        static let slideTop: AnyTransition = .opacity.combined(with: .move(edge: .top))
        static let slideBottom: AnyTransition = .opacity.combined(with: .move(edge: .bottom))
        static let slideLeading: AnyTransition = .opacity.combined(with: .move(edge: .leading))
        static let slideTrailing: AnyTransition = .opacity.combined(with: .move(edge: .trailing))

        static func asymmetric(insertion: AnyTransition = AnimationToken.Transition.slideTop, removal: AnyTransition = AnimationToken.Transition.default) -> AnyTransition {
            .asymmetric(insertion: insertion, removal: removal)
        }

        static let onboardingStep: AnyTransition = .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .trailing)),
            removal: .opacity.combined(with: .move(edge: .leading))
        )
    }

    // MARK: - Convenience

    /// Apply the standard animation for value-driven changes.
    static func animate(_ animation: Animation = Ease.standardOut, _ body: @escaping () -> Void) {
        withAnimation(animation, body)
    }
}

// MARK: - View Extension

extension View {
    /// Apply a system token animation to a value-driven change.
    func animateToken(_ token: Animation, value: some Equatable) -> some View {
        animation(token, value: value)
    }
}
