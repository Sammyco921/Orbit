import Foundation

// MARK: - UX State Machine (Rule 2)

enum UXState: Equatable {
    case idle
    case interpreting
    case planning
    case executing(currentStep: Int, totalSteps: Int)
    case completed
    case failed
    case cancelled
}

enum UXEvent: Equatable {
    case submitIntent
    case intentInterpreted
    case planGenerated(stepCount: Int)
    case stepCompleted
    case stepFailed(String)
    case allStepsCompleted
    case cancel
    case reset
}

extension UXState {
    var progressDescription: String {
        switch self {
        case .idle: return "Ready"
        case .interpreting: return "Interpreting request..."
        case .planning: return "Planning..."
        case .executing(let current, let total): return "Executing step \(current + 1) of \(total)"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}

// MARK: - Deterministic State Machine

struct UXStateMachine: Equatable {
    private(set) var state: UXState = .idle

    mutating func transition(_ event: UXEvent) {
        switch (state, event) {
        // Idle → Interpreting
        case (.idle, .submitIntent):
            state = .interpreting

        // Completed → Interpreting (multi-turn)
        case (.completed, .submitIntent):
            state = .interpreting

        // Interpreting → Planning
        case (.interpreting, .intentInterpreted):
            state = .planning

        // Planning → Executing
        case (.planning, .planGenerated(let count)):
            state = .executing(currentStep: 0, totalSteps: max(count, 1))

        // Executing → Executing (step advance)
        case (.executing(let current, let total), .stepCompleted):
            let next = current + 1
            if next >= total {
                state = .completed
            } else {
                state = .executing(currentStep: next, totalSteps: total)
            }

        // Executing → Completed (all done)
        case (.executing, .allStepsCompleted):
            state = .completed

        // Executing → Failed (step error)
        case (.executing, .stepFailed):
            state = .failed

        // Any state → Cancelled
        case (_, .cancel) where state != .idle && state != .completed:
            state = .cancelled

        // Any → Idle
        case (_, .reset):
            state = .idle

        // Invalid transitions are no-ops
        default:
            break
        }
    }

    var canAcceptInput: Bool {
        state == .idle || state == .completed || state == .failed || state == .cancelled
    }

    var isInterruptible: Bool {
        switch state {
        case .interpreting, .planning, .executing:
            return true
        case .idle, .completed, .failed, .cancelled:
            return false
        }
    }

    var currentProgressDescription: String {
        state.progressDescription
    }
}
