import Foundation

func withTimeout<T>(_ seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw OrbitError.timeout
        }
        guard let result = try await group.next() else {
            group.cancelAll()
            throw CancellationError()
        }
        group.cancelAll()
        return result
    }
}
