import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "persistence")

// MARK: - Message Processing

extension Orchestrator {
    func sendMessage(_ text: String) async {
        if activeConversationId == nil { newConversation() }

        addMessage(Message(role: .user, content: text))
        isProcessing = true

        let refinementKeywords = ["refine", "improve", "revise", "update", "modify", "change", "edit"]
        let isRefinement = hasRecentArtifact() && refinementKeywords.contains { text.lowercased().contains($0) }

        if isRefinement {
            await handleRefinement(userInput: text)
            return
        }

        streamingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let goalDescription = text

            let planGenerator = PlanGenerator(
                tools: runtime.toolService.toolRegistry,
                llm: currentProvider(),
                parameters: activeParameters()
            )

            let planResult: PlanGenerationResult
            do {
                planResult = try await planGenerator.generatePlan(goal: text)
            } catch {
                log.warning("Plan generation failed, falling back to ReAct: \(error.localizedDescription)")
                planResult = .direct
            }

            guard !Task.isCancelled else { return }

            switch planResult {
            case .plan(let generatedPlan):
                let plan = Plan(summary: generatedPlan.summary, steps: generatedPlan.steps.map { step in
                    Step.tool(
                        name: step.description,
                        toolName: step.tool,
                        input: step.input,
                        dependencies: step.dependencies
                    )
                })
                currentPlan = plan
                addMessage(Message(role: .system, content: "📋 Generated plan: \(plan.summary) (\(plan.steps.count) steps)"))

            case .direct:
                if useMultiAgent {
                    await runMultiAgent(goal: text)
                } else {
                    await runSingleAgent(goalDescription: goalDescription, text: text)
                }
            }
        }
        await streamingTask?.value
    }

    func processFromMessage(at msgIndex: Int) async {
        guard let convIndex = conversations.firstIndex(where: { $0.id == activeConversationId }),
              msgIndex < conversations[convIndex].messages.count
        else { return }

        let userMsg = conversations[convIndex].messages[msgIndex]
        guard userMsg.role == .user else { return }

        isProcessing = true

        let text = userMsg.content
        let refinementKeywords = ["refine", "improve", "revise", "update", "modify", "change", "edit"]
        let isRefinement = hasRecentArtifact() && refinementKeywords.contains { text.lowercased().contains($0) }

        if isRefinement {
            await handleRefinement(userInput: text)
            return
        }

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
            goalDescription: text,
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

    func handleRefinement(userInput: String) async {
        streamingText = ""
        isStreaming = true

        let lastArtifact = messages.last?.artifacts.last
        guard let artifact = lastArtifact, let fileURL = artifact.fileURL else {
            streamingText += "I don't see a recent artifact to refine. Try creating something first."
            finalizeStreaming()
            return
        }

        let originalContent: String
        do {
            originalContent = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            streamingText += "Could not read the original file for refinement."
            finalizeStreaming()
            return
        }

        streamingText += "## Refining\n\nRefining \(fileURL.lastPathComponent)...\n\n"

        var revisedContent = ""
        do {
            let stream = currentProvider().completeStreaming(messages: [
                LLMMessage(role: .system, content: "You are refining an existing document. Incorporate the user's feedback while preserving the original structure and intent. Return the complete revised content."),
                LLMMessage(role: .user, content: "Original content:\n\n```\n\(originalContent)\n```\n\nRefinement request: \(userInput)")
            ], parameters: activeParameters())
            for try await token in stream {
                if Task.isCancelled { break }
                revisedContent += token
                bufferStreamingChunk(token)
            }
            flushStreamBuffer()
        } catch {
            streamingText += "\n\nRefinement failed: \(error.localizedDescription)"
        }

        let ext = fileURL.pathExtension
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let version2URL = fileURL.deletingLastPathComponent().appendingPathComponent("\(baseName)_v2.\(ext)")
        do {
            try revisedContent.write(to: version2URL, atomically: true, encoding: .utf8)
            streamingText += "\n\nUpdated: [\(version2URL.lastPathComponent)](\(version2URL.path))\n\n"
        } catch {
            streamingText += "\n\nCould not save revised file."
        }

        finalizeStreaming()
    }

    private func hasRecentArtifact() -> Bool {
        messages.last?.artifacts.last?.fileURL != nil
    }
}
