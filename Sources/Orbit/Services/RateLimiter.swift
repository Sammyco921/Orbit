import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "rate-limiter")

final class RateLimiter {
    private let maxTokens: Int
    private let refillInterval: TimeInterval
    private var tokens: Int
    private var lastRefill: Date
    private let label: String
    private let lock = NSLock()

    init(maxRequestsPerSecond: Int = 20, label: String = "default") {
        self.maxTokens = maxRequestsPerSecond
        self.refillInterval = 1.0
        self.tokens = maxRequestsPerSecond
        self.lastRefill = Date()
        self.label = label
    }

    func acquire() -> Bool {
        lock.lock()
        refill()
        guard tokens > 0 else {
            log.warning("Rate limit exceeded for \(self.label)")
            lock.unlock()
            return false
        }
        tokens -= 1
        lock.unlock()
        return true
    }

    private func refill() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastRefill)
        if elapsed >= refillInterval {
            let newTokens = Int(elapsed / refillInterval) * maxTokens
            tokens = min(maxTokens, tokens + newTokens)
            lastRefill = now
        }
    }

    func reset() {
        lock.lock()
        tokens = maxTokens
        lastRefill = Date()
        lock.unlock()
    }
}
