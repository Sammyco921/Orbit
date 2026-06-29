import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "scheduler")

final class SchedulerService {
    private var handlers: [String: () async -> Void] = [:]
    private var task: Task<Void, Never>?
    private let interval: TimeInterval = 30

    func registerHandler(id: String, handler: @escaping () async -> Void) {
        handlers[id] = handler
    }

    func unregisterHandler(id: String) {
        handlers.removeValue(forKey: id)
    }

    func start() {
        guard task == nil else { return }
        let tickInterval: TimeInterval = interval
        log.notice("Scheduler started (interval: \(Int(tickInterval))s, \(self.handlers.count) handlers)")
        task = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(tickInterval))
                    await self?.tick()
                } catch {
                    break
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        log.notice("Scheduler stopped")
    }

    deinit {
        task?.cancel()
        task = nil
    }

    private func tick() async {
        for (id, handler) in handlers {
            await handler()
        }
    }
}
