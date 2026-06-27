import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "browser-verify")

enum VerificationDecision: String {
    case success
    case needsRetry
    case failed
}

final class BrowserVerificationService {
    private let runtime: BrowserRuntime
    private let llmProvider: (String) async throws -> String
    private let maxRetries: Int

    init(runtime: BrowserRuntime, llmProvider: @escaping (String) async throws -> String, maxRetries: Int = 2) {
        self.runtime = runtime
        self.llmProvider = llmProvider
        self.maxRetries = maxRetries
    }

    func verifyAction(description: String, context: ExecutionContext, action: () async throws -> String) async throws -> String {
        var lastError: String?
        for attempt in 0...self.maxRetries {
            if attempt > 0 {
                log.notice("Retry \(attempt)/\(self.maxRetries) for: \(description)")
            }

            let result = try await action()
            let verdict = try await checkActionResult(description: description, context: context)

            switch verdict {
            case .success:
                return result
            case .needsRetry:
                lastError = "Verification failed on attempt \(attempt + 1)"
            case .failed:
                throw BrowserVerificationError.actionFailed(description, "Action could not be completed after verification")
            }
        }
        throw BrowserVerificationError.verificationFailed(description, lastError ?? "Max retries exceeded")
    }

    private func checkActionResult(description: String, context: ExecutionContext) async throws -> VerificationDecision {
        guard runtime.isRunning else { return .success }

        let screenshotData: Data
        do {
            screenshotData = try await runtime.takeScreenshot(context: context)
        } catch {
            log.warning("Could not take screenshot for verification: \(error.localizedDescription)")
            return .success
        }

        let base64Screenshot = screenshotData.base64EncodedString()

        let prompt = """
        You are verifying whether a browser action succeeded.

        Action performed: \(description)

        Look at the screenshot and determine if the action was successful.
        A navigation action succeeds if the page loaded (not showing an error, not still on previous page).
        A click action succeeds if the expected change happened on screen.
        A type action succeeds if the text appears to have been entered in the correct field.

        Reply with exactly one word: SUCCESS, RETRY, or FAILED.
        """

        let response: String
        do {
            response = try await llmProvider(prompt)
        } catch {
            log.warning("LLM verification failed: \(error.localizedDescription)")
            return .success
        }

        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if trimmed.hasPrefix("SUCCESS") {
            return .success
        } else if trimmed.hasPrefix("RETRY") {
            return .needsRetry
        } else {
            return .failed
        }
    }
}

enum BrowserVerificationError: Error, LocalizedError {
    case actionFailed(String, String)
    case verificationFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .actionFailed(let action, let reason): return "Browser action '\(action)' failed: \(reason)"
        case .verificationFailed(let action, let reason): return "Browser verification for '\(action)' failed: \(reason)"
        }
    }
}
