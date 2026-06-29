import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "events")

protocol Event: Sendable {}

final class EventBus: @unchecked Sendable {
    // All mutable state is guarded by an OSAllocatedUnfairLock.
    // @unchecked Sendable remains until Swift 6 can verify the lock guarantees.
    private struct Handler {
        let id: UUID
        let block: (Any) -> Void
        let queue: DispatchQueue
    }
    private let lock = OSAllocatedUnfairLock(initialState: [ObjectIdentifier: [Handler]]())

    func publish<T: Event>(_ event: T) {
        let typeId = ObjectIdentifier(T.self)
        let targets = lock.withLock { $0[typeId] ?? [] }
        for handler in targets {
            handler.queue.async { handler.block(event) }
        }
    }

    @discardableResult
    func subscribe<T: Event>(_ type: T.Type, handler: @escaping (T) -> Void) -> () -> Void {
        let id = UUID()
        let queue = DispatchQueue(label: "com.orbit.eventbus.\(id.uuidString.prefix(8))", qos: .userInitiated)
        let box: (Any) -> Void = { event in
            guard let typed = event as? T else { return }
            handler(typed)
        }
        lock.withLock { $0[ObjectIdentifier(type), default: []].append(Handler(id: id, block: box, queue: queue)) }
        return { [weak self] in
            guard let self else { return }
            self.lock.withLock { $0[ObjectIdentifier(type)]?.removeAll { $0.id == id } }
        }
    }
}

struct ConversationCreatedEvent: Event { let id: UUID; let title: String }
struct MessageAddedEvent: Event { let conversationId: UUID; let message: Message }
struct ConversationDeletedEvent: Event { let id: UUID }
struct MemoryStoredEvent: Event { let conversationId: String }
struct ToolExecutedEvent: Event { let toolName: String; let result: String }
