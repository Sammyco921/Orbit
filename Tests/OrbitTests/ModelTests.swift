import Testing
@testable import Orbit

struct MessageTests {

    @Test func messageCreation() {
        let msg = Message(role: Message.Role.user, content: "Hello")
        #expect(msg.role == Message.Role.user)
        #expect(msg.content == "Hello")
        #expect(msg.artifacts.isEmpty)
    }

    @Test func assistantMessageWithArtifacts() {
        let artifact = Artifact(filename: "doc.md", type: .markdown, content: "# Doc")
        let msg = Message(role: .assistant, content: "Here's a doc", artifacts: [artifact])
        #expect(msg.artifacts.count == 1)
        #expect(msg.artifacts.first?.filename == "doc.md")
    }
}

struct ConversationTests {

    @Test func conversationCreation() {
        let conv = Conversation()
        #expect(!conv.title.isEmpty)
        #expect(conv.messages.isEmpty)
    }

    @Test func conversationAddMessage() {
        var conv = Conversation()
        conv.messages.append(Message(role: Message.Role.user, content: "Hello"))
        #expect(conv.messages.count == 1)
    }
}

struct PlanTests {

    @Test func planStepCreation() {
        let step = Step(name: "Search for X", stepType: .research)
        #expect(step.stepType == Step.StepType.research)
        #expect(step.name == "Search for X")
        #expect(step.status == Step.StepStatus.pending)
    }

    @Test func planStepStatusTransitions() {
        var step = Step(name: "Write code", stepType: .generate)
        step.status = Step.StepStatus.inProgress
        #expect(step.status == Step.StepStatus.inProgress)
        step.status = Step.StepStatus.completed
        #expect(step.status == Step.StepStatus.completed)
    }
}

struct ModelParametersTests {

    @Test func defaultParameters() {
        let params = ModelParameters()
        #expect(params.temperature == nil)
        #expect(params.maxTokens == nil)
        #expect(params.topP == nil)
    }

    @Test func customParameters() {
        let params = ModelParameters(temperature: 0.7, maxTokens: 2048, topP: 0.9)
        #expect(params.temperature == 0.7)
        #expect(params.maxTokens == 2048)
        #expect(params.topP == 0.9)
    }
}
