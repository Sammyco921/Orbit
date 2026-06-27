import Foundation

/// Unified error type covering all Orbit subsystems.
///
/// Replaces previously separate ToolError, VisualError, AgentError,
/// PluginError, PluginRegistryError, PlatformError, EmbeddingError,
/// ScriptError, and LocalEmbeddingError types.
enum OrbitError: Error, LocalizedError, Equatable {
    // Tools
    case toolNotFound(String)
    case toolRequiresApproval(String)
    case toolCallFailed(String)

    // Visual / Screen
    case screenCaptureFailed
    case elementNotFound(String)
    case ocrFailed(String)
    case formFillFailed(String)

    // Agents
    case subGoalFailed(String, String)
    case replanFailed(String)
    case noSuitableAgent
    case executionFailed(String)

    // Plugins
    case missingEntryPoint(String)
    case processNotRunning
    case pluginToolCallFailed(String)

    // Plugin Registry
    case fetchFailed(String)
    case parseFailed(String)
    case downloadFailed(String)
    case extractFailed(String)
    case unsupportedFormat(String)

    // Platform
    case unsupportedOnPlatform(String)

    // Embeddings
    case modelUnavailable(String)
    case embeddingFailed(String)

    // Workflow
    case workflowNotFound(String)
    case stepFailed(String, String)
    case variableMissing(String)

    // Execution
    case timeout
    case cancelled
    case invalidInput(String)
    case securityBlocked(String)

    // Database
    case databaseCorruption(String)

    var errorDescription: String? {
        switch self {
        case .toolNotFound(let name): return "Tool '\(name)' not found"
        case .toolRequiresApproval(let name): return "Tool '\(name)' requires approval"
        case .toolCallFailed(let msg): return "Tool call failed: \(msg)"
        case .screenCaptureFailed: return "Failed to capture screen"
        case .elementNotFound(let desc): return "No element found: \(desc)"
        case .ocrFailed(let msg): return "OCR failed: \(msg)"
        case .formFillFailed(let msg): return "Form fill failed: \(msg)"
        case .subGoalFailed(let goal, let err): return "Sub-goal failed: '\(goal)' — \(err)"
        case .replanFailed(let goal): return "Could not re-plan: \(goal)"
        case .noSuitableAgent: return "No suitable agent available"
        case .executionFailed(let msg): return "Execution failed: \(msg)"
        case .missingEntryPoint(let path): return "Missing entry point: \(path)"
        case .processNotRunning: return "Plugin process not running"
        case .pluginToolCallFailed(let msg): return "Plugin tool call failed: \(msg)"
        case .fetchFailed(let msg): return "Fetch failed: \(msg)"
        case .parseFailed(let msg): return "Parse failed: \(msg)"
        case .downloadFailed(let msg): return "Download failed: \(msg)"
        case .extractFailed(let msg): return "Extract failed: \(msg)"
        case .unsupportedFormat(let fmt): return "Unsupported format: \(fmt)"
        case .unsupportedOnPlatform(let feature): return "'\(feature)' not supported"
        case .modelUnavailable(let msg): return "Model unavailable: \(msg)"
        case .embeddingFailed(let msg): return "Embedding failed: \(msg)"
        case .timeout: return "Operation timed out"
        case .cancelled: return "Operation cancelled"
        case .invalidInput(let msg): return "Invalid input: \(msg)"
        case .workflowNotFound(let id): return "Workflow '\(id)' not found"
        case .stepFailed(let step, let reason): return "Step '\(step)' failed: \(reason)"
        case .variableMissing(let name): return "Required variable '\(name)' is missing"
        case .securityBlocked(let msg): return "Security blocked: \(msg)"
        case .databaseCorruption(let msg): return "Database corruption: \(msg)"
        }
    }
}
