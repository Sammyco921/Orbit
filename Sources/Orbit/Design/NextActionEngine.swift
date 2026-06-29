import Foundation

// MARK: - Next Action Engine

/// After every job completes, the system suggests contextual next actions
/// to reduce user drop-off and encourage continued interaction.
///
/// Actions are filtered by:
/// - Job type (conversation / tool-based / mixed)
/// - Tools used in the execution
/// - Whether artifacts were generated
/// - Whether the job succeeded or failed
struct NextActionEngine {
    // MARK: - Action Types

    enum NextAction: Identifiable, Sendable {
        case rerunWithVariation
        case refineIntent
        case saveAsWorkflow
        case inspectArtifacts
        case viewInHistory
        case exportResult
        case retryExecution

        var id: String { label }

        var label: String {
            switch self {
            case .rerunWithVariation: "Run with different input"
            case .refineIntent: "Refine your request"
            case .saveAsWorkflow: "Save as workflow"
            case .inspectArtifacts: "View generated files"
            case .viewInHistory: "Open in history"
            case .exportResult: "Export result"
            case .retryExecution: "Try again"
            }
        }

        var systemImage: String {
            switch self {
            case .rerunWithVariation: "arrow.triangle.2.circlepath"
            case .refineIntent: "pencil.and.outline"
            case .saveAsWorkflow: "flowchart"
            case .inspectArtifacts: "doc.text.magnifyingglass"
            case .viewInHistory: "clock.arrow.circlepath"
            case .exportResult: "square.and.arrow.up"
            case .retryExecution: "arrow.clockwise"
            }
        }
    }

    // MARK: - Context

    struct ExecutionContext {
        let didSucceed: Bool
        let usedToolIDs: [String]
        let hasArtifacts: Bool
        let intent: String
    }

    // MARK: - Suggestion

    static func suggestActions(for context: ExecutionContext) -> [NextAction] {
        var actions: [NextAction] = []

        if !context.didSucceed {
            actions.append(.retryExecution)
            actions.append(.refineIntent)
        } else {
            actions.append(.rerunWithVariation)
        }

        if context.hasArtifacts {
            actions.append(.inspectArtifacts)
        }

        actions.append(.viewInHistory)
        actions.append(.exportResult)

        let hasComplexTools = context.usedToolIDs.contains(where: { toolID in
            ["readFile", "writeFile", "executeCommand", "browser"].contains(toolID)
        })
        if hasComplexTools {
            actions.append(.saveAsWorkflow)
        }

        return actions
    }
}
