import Testing
import Foundation
@testable import Orbit

struct EventBusTests {

    @Test func publishSubscribe() async {
        let bus = EventBus()
        var received: ConversationCreatedEvent?
        let cancel = bus.subscribe(ConversationCreatedEvent.self) { event in
            received = event
        }
        let event = ConversationCreatedEvent(id: UUID(), title: "Test")
        bus.publish(event)
        try? await Task.sleep(nanoseconds: 5_000_000)
        #expect(received?.id == event.id)
        #expect(received?.title == "Test")
        cancel()
    }

    @Test func unsubscribeStopsReceiving() async {
        let bus = EventBus()
        var count = 0
        let cancel = bus.subscribe(ConversationCreatedEvent.self) { _ in
            count += 1
        }
        bus.publish(ConversationCreatedEvent(id: UUID(), title: "A"))
        try? await Task.sleep(nanoseconds: 5_000_000)
        #expect(count == 1)
        cancel()
        bus.publish(ConversationCreatedEvent(id: UUID(), title: "B"))
        try? await Task.sleep(nanoseconds: 5_000_000)
        #expect(count == 1)
    }

    @Test func multipleSubscribers() async {
        let bus = EventBus()
        var first = 0
        var second = 0
        bus.subscribe(MessageAddedEvent.self) { _ in first += 1 }
        bus.subscribe(MessageAddedEvent.self) { _ in second += 1 }
        bus.publish(MessageAddedEvent(conversationId: UUID(), message: Message(role: .user, content: "hi")))
        try? await Task.sleep(nanoseconds: 5_000_000)
        #expect(first == 1)
        #expect(second == 1)
    }

    @Test func differentEventTypesAreIsolated() async {
        let bus = EventBus()
        var conversationEvent: ConversationCreatedEvent?
        var toolEvent: ToolExecutedEvent?
        bus.subscribe(ConversationCreatedEvent.self) { conversationEvent = $0 }
        bus.subscribe(ToolExecutedEvent.self) { toolEvent = $0 }
        bus.publish(ConversationCreatedEvent(id: UUID(), title: "Chat"))
        try? await Task.sleep(nanoseconds: 5_000_000)
        #expect(conversationEvent?.title == "Chat")
        #expect(toolEvent == nil)
        bus.publish(ToolExecutedEvent(toolName: "test", result: "ok"))
        try? await Task.sleep(nanoseconds: 5_000_000)
        #expect(toolEvent?.toolName == "test")
    }
}
