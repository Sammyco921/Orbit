import Foundation

// MARK: - Single / Multi-Agent Execution

extension Orchestrator {
    func resumeFromCheckpoint() async {
        guard let cp = pendingCheckpoint else { return }
        pendingCheckpoint = nil
        hasPendingCheckpoint = false

        if let convId = cp.conversationId, let uuid = UUID(uuidString: convId) {
            selectConversation(uuid)
        }

        addMessage(Message(role: .system, content: "🔄 Resuming previous session: \(cp.goalDescription)"))

        // Multi-agent checkpoint — restore shared memory and re-run with team
        if cp.agentStates != nil {
            if let sharedMemData = cp.sharedMemoryData {
                await runtime.agentRegistry.sharedMemory?.importState(sharedMemData)
            }
            await runMultiAgent(goal: cp.goalDescription)
            return
        }

        streamingText = ""
        isStreaming = true

        // Single-agent ReAct resume
        var contextMessages = cp.messages
        if contextMessages.first?.role == .system {
            contextMessages = Array(contextMessages.dropFirst())
        }
        let stream = runtime.workflowEngine.executeReAct(
            goalDescription: cp.goalDescription,
            maxSteps: 25,
            contextMessages: contextMessages,
            llm: currentProvider(),
            tools: runtime.toolService.toolRegistry,
            parameters: activeParameters(),
            checkpointManager: runtime.checkpointManager,
            executionId: cp.id,
            conversationId: cp.conversationId,
            approvalMode: .interactive,
            initialStepCount: cp.stepCount,
            initialToolFailures: cp.toolFailures
        )

        for await event in stream {
            switch event {
            case .thought(let thought):
                streamingText += "**Thinking:** \(thought)\n\n"
            case .toolExecution(let toolName, let input):
                let inputDesc = input.isEmpty ? "" : " with \(input)"
                streamingText += "**\(toolName):**\(inputDesc)\n\n"
            case .toolResult(_, let output):
                streamingText += "\(output)\n\n"
            case .error(let error):
                streamingText += "**Error:** \(error)\n\n"
            case .completed(let summary):
                streamingText += "\n**\(summary)**\n\n"
            }
        }

        finalizeStreaming()
    }

    func discardCheckpoint() {
        try? runtime.checkpointManager.deleteAll()
        pendingCheckpoint = nil
        hasPendingCheckpoint = false
        pendingCheckpointSummary = ""
    }

    func runSingleAgent(goalDescription: String, text: String) async {
        streamingText = ""
        isStreaming = true

        let context = await runtime.memoryService.contextMessages(
            query: text,
            recentMessages: messages,
            conversationId: activeConversationId?.uuidString,
            workspaceId: activeWorkspaceId?.uuidString,
            workspaceName: activeWorkspace?.name,
            workspacePath: activeWorkspace?.path,
            workspaceKBIds: activeWorkspace?.knowledgeBaseIds
        )

        let stream = runtime.workflowEngine.executeReAct(
            goalDescription: goalDescription,
            maxSteps: 25,
            contextMessages: context,
            llm: currentProvider(),
            tools: runtime.toolService.toolRegistry,
            parameters: activeParameters(),
            checkpointManager: runtime.checkpointManager,
            executionId: UUID().uuidString,
            conversationId: activeConversationId?.uuidString,
            approvalMode: .interactive
        )

        for await event in stream {
            switch event {
            case .thought(let thought):
                streamingText += "**Thinking:** \(thought)\n\n"
            case .toolExecution(let toolName, let input):
                let inputDesc = input.isEmpty ? "" : " with \(input)"
                streamingText += "**\(toolName):**\(inputDesc)\n\n"
            case .toolResult(_, let output):
                streamingText += "\(output)\n\n"
            case .error(let error):
                streamingText += "**Error:** \(error)\n\n"
            case .completed(let summary):
                streamingText += "\n**\(summary)**\n\n"
            }
        }

        finalizeStreaming()
    }

    func runMultiAgent(goal: String) async {
        streamingText = ""
        isStreaming = true
        streamingText += "## Multi-Agent Execution\n\n"
        streamingText += "Decomposing goal and assigning to specialized agents...\n\n"

        let team = AgentTeamTemplate.all.first { $0.id == "general" } ?? AgentTeamTemplate.all[3]
        let planner = runtime.agentRegistry.createTeam(template: team, runtime: runtime)
        guard let planner else {
            streamingText += "**Error:** Could not create agent team.\n\n"
            finalizeStreaming()
            return
        }

        runtime.agentRegistry.onLifecycleEvent = { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch event {
                case .started(let agentId):
                    if agentId != planner.id {
                        streamingText += "▶️ Agent \(agentId.prefix(8)) started\n\n"
                    }
                case .statusChanged(let agentId, let status):
                    if status == .completed && agentId != planner.id {
                        streamingText += "✅ Agent \(agentId.prefix(8)) completed\n\n"
                    } else if status == .failed {
                        streamingText += "❌ Agent \(agentId.prefix(8)) failed\n\n"
                    }
                case .messageSent(let msg):
                    if msg.type == .taskAssignment {
                        streamingText += "📋 \(msg.fromAgentId.prefix(8)) → \(msg.toAgentId?.prefix(8) ?? "?"): \(msg.content.prefix(80))...\n\n"
                    }
                case .taskCompleted(_, let result):
                    streamingText += "📄 Result: \(result.summary)\n\n"
                case .taskFailed(_, let error):
                    streamingText += "⚠️ Task failed: \(error)\n\n"
                default:
                    break
                }
            }
        }

        let context = await runtime.memoryService.contextMessages(
            query: goal,
            recentMessages: messages,
            conversationId: activeConversationId?.uuidString,
            workspaceId: activeWorkspaceId?.uuidString,
            workspaceName: activeWorkspace?.name,
            workspacePath: activeWorkspace?.path,
            workspaceKBIds: activeWorkspace?.knowledgeBaseIds
        )

        let taskContext = AgentTaskContext(
            conversationId: activeConversationId,
            relevantMessages: context.map { $0.content },
            artifacts: [:],
            additionalInstructions: nil
        )

        for await output in planner.start(goal: goal, context: taskContext) {
            streamingText += output + "\n\n"
        }

        runtime.agentRegistry.onLifecycleEvent = nil
        finalizeStreaming()
    }
}
