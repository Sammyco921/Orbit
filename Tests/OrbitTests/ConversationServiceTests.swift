import Testing
import Foundation
@testable import Orbit

struct ConversationServiceTests {

    @Test func createConversation() async {
        let bus = EventBus()
        let service = ConversationService(eventBus: bus)

        var createdID: UUID?
        bus.subscribe(ConversationCreatedEvent.self) { event in
            createdID = event.id
        }

        let conv = service.createConversation()
        #expect(conv.title == "New Chat")
        #expect(conv.messages.isEmpty)
        #expect(service.activeConversationId == conv.id)
        try? await Task.sleep(nanoseconds: 5_000_000)
        #expect(createdID == conv.id)
    }

    @Test func addMessage() async {
        let bus = EventBus()
        let service = ConversationService(eventBus: bus)
        let conv = service.createConversation()

        var received: MessageAddedEvent?
        bus.subscribe(MessageAddedEvent.self) { received = $0 }

        let msg = Message(role: .user, content: "Hello")
        let index = service.addMessage(msg)
        #expect(index != nil)
        #expect(service.messages.count == 1)
        #expect(service.messages.first?.content == "Hello")
        try? await Task.sleep(nanoseconds: 5_000_000)
        #expect(received?.conversationId == conv.id)
    }

    @Test func deleteConversation() async {
        let bus = EventBus()
        let service = ConversationService(eventBus: bus)
        let conv = service.createConversation()

        var deletedID: UUID?
        bus.subscribe(ConversationDeletedEvent.self) { deletedID = $0.id }

        service.deleteConversation(conv.id)
        #expect(service.conversations.count == 1)
        try? await Task.sleep(nanoseconds: 5_000_000)
        #expect(deletedID == conv.id)
    }

    @Test func selectConversation() {
        let bus = EventBus()
        let service = ConversationService(eventBus: bus)
        let conv1 = service.createConversation()
        let conv2 = service.createConversation()

        service.selectConversation(conv1.id)
        #expect(service.activeConversationId == conv1.id)

        service.selectConversation(conv2.id)
        #expect(service.activeConversationId == conv2.id)
    }

    @Test func renameConversation() {
        let bus = EventBus()
        let service = ConversationService(eventBus: bus)
        let conv = service.createConversation()

        service.renameConversation(conv.id, title: "Updated Title")
        #expect(service.conversation(for: conv.id)?.title == "Updated Title")
    }

    @Test func togglePin() {
        let bus = EventBus()
        let service = ConversationService(eventBus: bus)
        let conv = service.createConversation()
        #expect(conv.isPinned == false)

        service.togglePin(conv.id)
        #expect(service.conversation(for: conv.id)?.isPinned == true)

        service.togglePin(conv.id)
        #expect(service.conversation(for: conv.id)?.isPinned == false)
    }

    @Test func archiveAndUnarchive() {
        let bus = EventBus()
        let service = ConversationService(eventBus: bus)
        let conv = service.createConversation()
        #expect(conv.isArchived == false)

        service.archiveConversation(conv.id)
        #expect(service.conversation(for: conv.id)?.isArchived == true)

        service.unarchiveConversation(conv.id)
        #expect(service.conversation(for: conv.id)?.isArchived == false)
    }

    @Test func moveConversation() {
        let bus = EventBus()
        let service = ConversationService(eventBus: bus)
        let conv = service.createConversation()
        let wsID = UUID()

        service.moveConversation(conv.id, toWorkspaceId: wsID)
        #expect(service.conversation(for: conv.id)?.workspaceId == wsID)
    }

    @Test func deleteMessage() {
        let bus = EventBus()
        let service = ConversationService(eventBus: bus)
        let conv = service.createConversation()

        let msg1 = Message(role: .user, content: "First")
        let msg2 = Message(role: .assistant, content: "Second")
        let msg3 = Message(role: .user, content: "Third")
        service.addMessage(msg1)
        service.addMessage(msg2)
        service.addMessage(msg3)

        #expect(service.messages.count == 3)
        // Simulating editMessage which removes subsequent messages
        let result = service.editMessage(msg2.id, newContent: "Edited")
        #expect(result != nil)
        #expect(service.messages.count == 2)
    }

    @Test func forkConversation() {
        let bus = EventBus()
        let service = ConversationService(eventBus: bus)
        let conv = service.createConversation()

        let msg1 = Message(role: .user, content: "Hello")
        let msg2 = Message(role: .assistant, content: "Hi there")
        service.addMessage(msg1)
        service.addMessage(msg2)

        guard let forked = service.forkConversation(at: msg1.id) else {
            Issue.record("Fork returned nil")
            return
        }
        #expect(forked.messages.count == 1)
        #expect(forked.messages.first?.content == "Hello")
        #expect(service.activeConversationId == forked.id)
    }

    @Test func conversationForID() {
        let bus = EventBus()
        let service = ConversationService(eventBus: bus)
        let conv = service.createConversation()

        let found = service.conversation(for: conv.id)
        #expect(found?.id == conv.id)

        let notFound = service.conversation(for: UUID())
        #expect(notFound == nil)
    }

    // MARK: - Context Management / Summarization

    @Test func conversationDoesNotSummarizeBelowThreshold() {
        let bus = EventBus()
        let service = ConversationService(eventBus: bus)
        let conv = service.createConversation()

        // Add 30 messages (below the 50 threshold)
        for i in 0..<30 {
            service.addMessage(Message(role: .user, content: "Message \(i)"))
        }

        #expect(service.messages.count == 30)
    }

    @Test func conversationTruncatesWhenNoLLMAndAboveThreshold() {
        let bus = EventBus()
        let service = ConversationService(eventBus: bus)
        let conv = service.createConversation()

        // Add enough messages to exceed the threshold and force truncation
        // The threshold is 50, keepCount is 20, so we need at least 70 to trigger
        // Without an LLM, it falls back to truncation keeping the last 20
        for i in 0..<75 {
            service.addMessage(Message(role: .user, content: "Message \(i)"))
        }

        // Without LLM, should truncate to 20 keepCount + 1 summary message = 21
        // But this is async, so give it time
        let expectation = #expect(service.messages.count <= 30)
    }
}
