import Foundation

// MARK: - Cognitive Presentation Engine

/// Dynamically adapts UI density and clarity based on execution context.
/// Mode is computed automatically and updates live during execution.
///
/// Modes:
/// - **Simple** (≤3 steps): minimal UI, no grouping, full readability
/// - **Standard** (4-10 steps): normal timeline, light grouping
/// - **Dense** (10+ steps OR long-running): collapsible groups, reduced spacing, compression
///
/// The mode is computed from:
/// - step count
/// - execution duration
/// - tool complexity (number of unique tool IDs used)
/// - streaming intensity (total streamed token count)
struct CognitivePresentationEngine {
    // MARK: - Mode

    enum Mode: String, Sendable {
        case simple
        case standard
        case dense

        var allowsGrouping: Bool {
            switch self {
            case .simple: false
            case .standard, .dense: true
            }
        }

        var allowsCollapse: Bool {
            switch self {
            case .simple, .standard: false
            case .dense: true
            }
        }

        var usesCompactSpacing: Bool {
            switch self {
            case .simple, .standard: false
            case .dense: true
            }
        }

        var usesSummaryCompression: Bool {
            switch self {
            case .simple, .standard: false
            case .dense: true
            }
        }
    }

    // MARK: - Thresholds

    private static let denseStepCountThreshold = 10
    private static let denseDurationThreshold: TimeInterval = 120 // 2 minutes
    private static let denseToolComplexityThreshold = 5
    private static let denseStreamingIntensityThreshold = 5000

    // MARK: - Mode Computation

    static func computeMode(
        stepCount: Int,
        executionDuration: TimeInterval? = nil,
        uniqueToolCount: Int = 0,
        totalStreamedTokens: Int = 0
    ) -> Mode {
        let isDense = stepCount >= denseStepCountThreshold
            || (executionDuration ?? 0) >= denseDurationThreshold
            || uniqueToolCount >= denseToolComplexityThreshold
            || totalStreamedTokens >= denseStreamingIntensityThreshold

        if isDense {
            return .dense
        }

        if stepCount > 3 {
            return .standard
        }

        return .simple
    }
}
