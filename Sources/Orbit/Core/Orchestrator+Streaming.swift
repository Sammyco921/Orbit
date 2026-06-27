import Foundation

// MARK: - Streaming / Buffer

extension Orchestrator {
    func bufferStreamingChunk(_ token: String) {
        streamBuffer += token
        if streamFlushTask == nil {
            streamFlushTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 50_000_000)
                await MainActor.run {
                    guard let self else { return }
                    streamingText += streamBuffer
                    streamBuffer = ""
                    streamFlushTask = nil
                }
            }
        }
    }

    func flushStreamBuffer() {
        if !streamBuffer.isEmpty {
            streamingText += streamBuffer
            streamBuffer = ""
        }
        streamFlushTask?.cancel()
        streamFlushTask = nil
    }

    func finalizeStreaming(with artifacts: [Artifact] = []) {
        flushStreamBuffer()
        let finalText = streamingText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !finalText.isEmpty {
            addMessage(Message(role: .assistant, content: finalText, artifacts: artifacts))
        }

        Task { [weak self] in
            guard let self else { return }
            await runtime.memoryService.storeExchange(
                messages: messages,
                conversationId: activeConversationId?.uuidString
            )
        }

        if let plan = currentPlan {
            let succeeded = plan.steps.allSatisfy { $0.status == .completed }
            let summary = plan.summary
            if succeeded {
                NotificationManager.shared.send(title: "Orbit: Complete", body: summary)
            } else {
                let failedCount = plan.steps.filter { $0.status == .failed }.count
                NotificationManager.shared.send(title: "Orbit: \(failedCount) step(s) failed", body: summary)
            }
        }

        try? runtime.checkpointManager.deleteAll()

        streamingText = ""
        isStreaming = false
        currentPlan = nil
        isProcessing = false
    }
}
