import Foundation
import Observation

struct ToolApprovalRequest: Identifiable, Sendable {
    let id: UUID
    let toolName: String
    let input: [String: String]
    let prompt: String
}

enum ToolApprovalResponse: Sendable {
    case allow
    case deny
    case allowOnce
    case allowForSession
}

enum ApprovalMode: Sendable {
    case interactive
    case autoApprove
    case throwOnApproval
}

@Observable
final class PendingApproval {
    static let shared = PendingApproval()

    private(set) var pendingRequest: ToolApprovalRequest?

    @ObservationIgnored private let lock = NSLock()
    @ObservationIgnored private var continuationQueue: [CheckedContinuation<ToolApprovalResponse, Never>] = []
    @ObservationIgnored private var requestQueue: [ToolApprovalRequest] = []

    func requestApproval(toolName: String, input: [String: String]) async -> ToolApprovalResponse {
        let request = ToolApprovalRequest(
            id: UUID(),
            toolName: toolName,
            input: input,
            prompt: "Allow Orbit to use \"\(toolName)\"?"
        )
        return await withCheckedContinuation { continuation in
            lock.withLock {
                continuationQueue.append(continuation)
                requestQueue.append(request)
                if pendingRequest == nil {
                    dequeueNextUnderLock()
                }
            }
        }
    }

    /// Removes a pending approval for a cancelled caller.
    /// Called by ExecutionKernel when it detects the calling task was cancelled.
    func cancelPending(for toolName: String) {
        lock.withLock {
            guard let idx = requestQueue.firstIndex(where: { $0.toolName == toolName }) else { return }
            requestQueue.remove(at: idx)
            let continuation = continuationQueue.remove(at: idx)
            continuation.resume(returning: .deny)
        }
    }

    private func dequeueNextUnderLock() {
        guard !requestQueue.isEmpty, !continuationQueue.isEmpty else {
            pendingRequest = nil
            return
        }
        pendingRequest = requestQueue.removeFirst()
    }

    func respond(_ response: ToolApprovalResponse) {
        lock.withLock {
            guard !continuationQueue.isEmpty else { return }
            let continuation = continuationQueue.removeFirst()
            if !requestQueue.isEmpty { requestQueue.removeFirst() }
            pendingRequest = nil
            continuation.resume(returning: response)
            dequeueNextUnderLock()
        }
    }

    func cancel() {
        lock.withLock {
            guard !continuationQueue.isEmpty else { return }
            let continuation = continuationQueue.removeFirst()
            if !requestQueue.isEmpty { requestQueue.removeFirst() }
            pendingRequest = nil
            continuation.resume(returning: .deny)
            dequeueNextUnderLock()
        }
    }
}
