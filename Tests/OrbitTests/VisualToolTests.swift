import Testing
import Foundation
@testable import Orbit

struct VisualToolTests {

    @Test func agentTypesAllCases() {
        #expect(AgentType.allCases.count == 5)
    }

    @Test func agentTypeDisplayNames() {
        #expect(AgentType.planner.displayName == "Planner")
        #expect(AgentType.executor.displayName == "Executor")
        #expect(AgentType.researcher.displayName == "Researcher")
        #expect(AgentType.reviewer.displayName == "Reviewer")
        #expect(AgentType.memoryManager.displayName == "Memory Manager")
    }

    @Test func agentStatusDisplayNames() {
        #expect(AgentStatus.idle.displayName == "Idle")
        #expect(AgentStatus.running.displayName == "Running")
        #expect(AgentStatus.completed.displayName == "Completed")
        #expect(AgentStatus.failed.displayName == "Failed")
        #expect(AgentStatus.cancelled.displayName == "Cancelled")
    }

    @Test func visualElementTypeFromAXRole() {
        #expect(VisualElementType.from(axRole: "AXButton") == .button)
        #expect(VisualElementType.from(axRole: "AXTextField") == .textField)
        #expect(VisualElementType.from(axRole: "AXStaticText") == .staticText)
        #expect(VisualElementType.from(axRole: "AXCheckBox") == .checkbox)
        #expect(VisualElementType.from(axRole: "AXRadioButton") == .radioButton)
        #expect(VisualElementType.from(axRole: "AXSlider") == .slider)
        #expect(VisualElementType.from(axRole: "AXLink") == .link)
        #expect(VisualElementType.from(axRole: "AXUnknown") == .unknown)
    }

    @Test func visualElementCenter() {
        let element = VisualElement(
            id: UUID(), type: .button, label: "Submit",
            frame: CGRect(x: 100, y: 200, width: 80, height: 30),
            textContent: nil, isEnabled: true, axRole: "AXButton"
        )
        #expect(element.center.x == 140)
        #expect(element.center.y == 215)
    }

    @Test func visualElementShortDescription() {
        let withText = VisualElement(
            id: UUID(), type: .button, label: "OK",
            frame: .zero, textContent: "Click me",
            isEnabled: true, axRole: nil
        )
        #expect(withText.shortDescription.contains("Button"))
        #expect(withText.shortDescription.contains("Click me"))

        let noText = VisualElement(
            id: UUID(), type: .textField, label: "",
            frame: .zero, textContent: nil,
            isEnabled: true, axRole: nil
        )
        #expect(noText.shortDescription.contains("Text Field"))
    }

    @Test func screenSnapshotDescription() {
        let elements = [
            VisualElement(id: UUID(), type: .button, label: "Save", frame: .zero, textContent: nil, isEnabled: true, axRole: nil)
        ]
        let snapshot = ScreenSnapshot(
            timestamp: Date(), elements: elements,
            ocrText: "Hello World", frontmostApp: "TestApp"
        )
        let desc = snapshot.description
        #expect(desc.contains("TestApp"))
        #expect(desc.contains("Hello World"))
        #expect(desc.contains("1)"))
    }

    @Test func visualErrorDescriptions() {
        #expect(OrbitError.screenCaptureFailed.errorDescription == "Failed to capture screen")
        #expect(OrbitError.elementNotFound("test").errorDescription == "No element found: test")
        #expect(OrbitError.ocrFailed("bad image").errorDescription == "OCR failed: bad image")
        #expect(OrbitError.formFillFailed("no fields").errorDescription == "Form fill failed: no fields")
    }

    @Test func messageRoleRawValues() {
        #expect(Message.Role.user.rawValue == "user")
        #expect(Message.Role.assistant.rawValue == "assistant")
        #expect(Message.Role.system.rawValue == "system")
    }

    @Test func messageInitWithRole() {
        let msg = Message(role: .user, content: "Hello")
        #expect(msg.role == .user)
        #expect(msg.content == "Hello")
    }

    @Test func conversationDefaultValues() {
        let conv = Conversation()
        #expect(conv.title == "New Chat")
        #expect(conv.messages.isEmpty)
        #expect(conv.isPinned == false)
        #expect(conv.isArchived == false)
        #expect(conv.hasGeneratedTitle == false)
    }
}
