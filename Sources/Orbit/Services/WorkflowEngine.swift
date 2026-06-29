import Foundation
import OSLog
import os

private let log = Logger(subsystem: "com.orbit", category: "engine")

// MARK: - DAG Execution Types

enum TaskState: String, Codable, Sendable {
    case pending
    case ready
    case running
    case succeeded
    case failed
    case skipped
}

final class TaskNode: Identifiable {
    let id: UUID
    let stepIndex: Int
    var dependencies: [UUID]
    var state: TaskState
    var retryCount: Int

    init(stepIndex: Int, dependencies: [UUID] = []) {
        self.id = UUID()
        self.stepIndex = stepIndex
        self.dependencies = dependencies
        self.state = .pending
        self.retryCount = 0
    }
}

final class TaskGraph {
    private(set) var nodes: [UUID: TaskNode] = [:]
    private var indexMap: [Int: UUID] = [:]

    @discardableResult
    func addNode(for stepIndex: Int, dependencies: [Int] = []) -> UUID {
        let depIDs = dependencies.compactMap { indexMap[$0] }
        let node = TaskNode(stepIndex: stepIndex, dependencies: depIDs)
        nodes[node.id] = node
        indexMap[stepIndex] = node.id
        return node.id
    }

    var readyNodes: [TaskNode] {
        nodes.values.filter { node in
            guard node.state == .pending || node.state == .ready else { return false }
            return node.dependencies.allSatisfy { nodes[$0]?.state == .succeeded }
        }
    }

    var isComplete: Bool {
        nodes.values.allSatisfy { $0.state == .succeeded || $0.state == .failed || $0.state == .skipped }
    }

    var hasFailed: Bool {
        nodes.values.contains { $0.state == .failed }
    }

    func transition(_ id: UUID, to state: TaskState) {
        nodes[id]?.state = state
        if state == .failed {
            skipDependents(of: id)
        }
    }

    private func skipDependents(of id: UUID) {
        for node in nodes.values
        where node.dependencies.contains(id) && (node.state == .pending || node.state == .ready) {
            node.state = .skipped
            skipDependents(of: node.id)
        }
    }

    static func sequential(_ stepCount: Int) -> TaskGraph {
        let graph = TaskGraph()
        for i in 0..<stepCount {
            graph.addNode(for: i, dependencies: i > 0 ? [i - 1] : [])
        }
        for node in graph.nodes.values where node.dependencies.isEmpty {
            node.state = .ready
        }
        return graph
    }
}

// MARK: - Step Execution Services

struct StepServices {
    let research: ResearchService?
    let document: DocumentService?
    let memory: MemoryService?
    let llmProvider: LLMProvider?
    let llmParameters: ModelParameters?
    let messages: [Message]
    let conversationId: String?
    let workspaceId: String?
    let workspaceName: String?
    let workspacePath: String?
    let workspaceKBIds: [String]?
    let sanitizeFilename: (String) -> String
    let onToken: (String) -> Void
    let onProgress: (String) -> Void
    let flushTokens: () -> Void

    init(
        research: ResearchService? = nil,
        document: DocumentService? = nil,
        memory: MemoryService? = nil,
        llmProvider: LLMProvider? = nil,
        llmParameters: ModelParameters? = nil,
        messages: [Message] = [],
        conversationId: String? = nil,
        workspaceId: String? = nil,
        workspaceName: String? = nil,
        workspacePath: String? = nil,
        workspaceKBIds: [String]? = nil,
        sanitizeFilename: @escaping (String) -> String = { $0 },
        onToken: @escaping (String) -> Void = { _ in },
        onProgress: @escaping (String) -> Void = { _ in },
        flushTokens: @escaping () -> Void = {}
    ) {
        self.research = research
        self.document = document
        self.memory = memory
        self.llmProvider = llmProvider
        self.llmParameters = llmParameters
        self.messages = messages
        self.conversationId = conversationId
        self.workspaceId = workspaceId
        self.workspaceName = workspaceName
        self.workspacePath = workspacePath
        self.workspaceKBIds = workspaceKBIds
        self.sanitizeFilename = sanitizeFilename
        self.onToken = onToken
        self.onProgress = onProgress
        self.flushTokens = flushTokens
    }
}

final class WorkflowEngine {
    private let store: WorkflowStore
    let toolService: ToolService
    private let eventBus: EventBus?
    private let reactLock = OSAllocatedUnfairLock(initialState: false)

    init(store: WorkflowStore, toolService: ToolService, eventBus: EventBus? = nil) {
        self.store = store
        self.toolService = toolService
        self.eventBus = eventBus
    }

    @discardableResult
    func executeDAG(
        stepCount: Int,
        dependencies: [[Int]],
        steps: inout [Step],
        services: StepServices,
        artifacts: inout [Artifact],
        maxRetries: Int = 3,
        approvalMode: ApprovalMode = .interactive,
        onStepEvent: @escaping (Int, Step.StepStatus, Int) -> Void = { _, _, _ in }
    ) async -> [Int: Error] {
        let graph = buildGraph(stepCount: stepCount, dependencies: dependencies)
        var failedSteps: [Int: Error] = [:]

        let buffer = StepBuffer(steps: steps, artifacts: artifacts)

        await Self.executeGraph(graph: graph, maxRetries: maxRetries) { [self, buffer] node in
            let index = node.stepIndex
            let attempt = node.retryCount + 1

            onStepEvent(index, .inProgress, attempt)

            do {
                try await executeStep(&buffer.steps[index], services: services, artifacts: &buffer.artifacts, approvalMode: approvalMode)
                onStepEvent(index, .completed, attempt)
            } catch {
                let isLast = node.retryCount >= maxRetries - 1
                onStepEvent(index, isLast ? .failed : .inProgress, attempt)
                throw error
            }
        }

        steps = buffer.steps
        artifacts = buffer.artifacts

        for node in graph.nodes.values {
            if node.state == .failed {
                failedSteps[node.stepIndex] = OrbitError.stepFailed("Step \(node.stepIndex)", "Exhausted \(maxRetries) retries")
            }
        }

        return failedSteps
    }

    private final class StepBuffer {
        var steps: [Step]
        var artifacts: [Artifact]
        init(steps: [Step], artifacts: [Artifact]) {
            self.steps = steps
            self.artifacts = artifacts
        }
    }

    static func executeGraph(graph: TaskGraph, maxRetries: Int = 3, stepHandler: @escaping (TaskNode) async throws -> Void) async {
        while !graph.isComplete {
            if Task.isCancelled { return }

            let ready = graph.readyNodes
            guard !ready.isEmpty else {
                try? await Task.sleep(nanoseconds: 100_000_000)
                continue
            }

            for node in ready {
                graph.transition(node.id, to: .running)
            }

            await withTaskGroup(of: (UUID, Result<Void, Error>).self) { group in
                for node in ready {
                    group.addTask {
                        do {
                            try await stepHandler(node)
                            return (node.id, .success(()))
                        } catch {
                            return (node.id, .failure(error))
                        }
                    }
                }

                for await (id, result) in group {
                    switch result {
                    case .success:
                        graph.transition(id, to: .succeeded)
                    case .failure:
                        guard let node = graph.nodes[id] else { continue }
                        node.retryCount += 1
                        if node.retryCount >= maxRetries {
                            graph.transition(id, to: .failed)
                        } else {
                            try? await Task.sleep(nanoseconds: 1_000_000_000)
                            graph.transition(id, to: .ready)
                        }
                    }
                }
            }
        }
    }

    private func buildGraph(stepCount: Int, dependencies: [[Int]]) -> TaskGraph {
        let hasDeps = dependencies.contains(where: { !$0.isEmpty })
        let graph: TaskGraph
        if hasDeps {
            graph = TaskGraph()
            for i in 0..<stepCount {
                graph.addNode(for: i, dependencies: dependencies[i])
            }
            for node in graph.nodes.values where node.dependencies.isEmpty {
                node.state = .ready
            }
        } else {
            graph = TaskGraph.sequential(stepCount)
        }
        return graph
    }

    func processWebhookEvent(type: String, payload: String) async {
        let matching = store.allDefinitions().filter { def in
            def.triggers.contains { trigger in
                trigger.type == .event &&
                (trigger.eventPattern?.lowercased().contains(type.lowercased()) ?? false)
            }
        }
        for def in matching {
            do {
                try await execute(definition: def, inputVariables: ["payload": payload, "event_type": type])
            } catch {
                log.warning("Webhook-triggered workflow '\(def.name)' failed: \(error.localizedDescription)")
            }
        }
    }

    @discardableResult
    func processDueWorkflows() async {
        let due = store.dueScheduledDefinitions()
        for definition in due {
            guard !Task.isCancelled else { return }
            do {
                try await execute(definition: definition)
            } catch {
                log.warning("Scheduled workflow '\(definition.name)' failed: \(error.localizedDescription)")
            }
        }
    }

    func execute(workflowId: String, inputVariables: [String: String] = [:]) async throws -> WorkflowExecution {
        guard let definition = store.definition(id: workflowId) else {
            throw OrbitError.workflowNotFound(workflowId)
        }
        return try await execute(definition: definition, inputVariables: inputVariables)
    }

    @discardableResult
    func execute(definition: WorkflowDefinition, inputVariables: [String: String] = [:], services: StepServices = StepServices(), approvalMode: ApprovalMode = .autoApprove) async throws -> WorkflowExecution {
        let executionId = UUID().uuidString
        var variables = inputVariables
        for v in definition.variables {
            if variables[v.name] == nil {
                variables[v.name] = v.defaultValue
            }
        }

        var missingRequired = definition.variables.filter { $0.required && variables[$0.name] == nil }
            .map(\.name)
        for (key, val) in inputVariables {
            variables[key] = val
            missingRequired.removeAll { $0 == key }
        }
        if !missingRequired.isEmpty {
            throw OrbitError.variableMissing(missingRequired.joined(separator: ", "))
        }

        var execution = WorkflowExecution(
            id: executionId,
            workflowId: definition.id,
            variables: variables
        )
        store.saveExecution(execution)

        let workflowStartTime = CFAbsoluteTimeGetCurrent()
        eventBus?.publish(WorkflowStartedEvent(
            executionId: executionId, workflowId: definition.id, workflowName: definition.name,
            triggerType: definition.triggers.first?.type.rawValue ?? "manual",
            timestamp: Date()
        ))

        do {
            for (stepIndex, step) in definition.steps.enumerated() {
                guard !Task.isCancelled else {
                    execution.status = .cancelled
                    execution.completedAt = Date()
                    store.saveExecution(execution)
                    throw OrbitError.cancelled
                }

                if let condition = step.condition, !condition.isEmpty {
                    let shouldRun = evaluateCondition(condition, variables: variables)
                    if !shouldRun {
                        execution.stepResults[step.id] = "(skipped)"
                        store.saveExecution(execution)
                        continue
                    }
                }

                var toolInput: [String: String] = [:]
                for (varName, paramKey) in step.inputMapping {
                    toolInput[paramKey] = variables[varName] ?? ""
                }

                var workflowStep = step
                workflowStep.input = toolInput

                var artifacts: [Artifact] = []
                var lastError: Error?

                for attempt in 0...step.retryCount {
                    guard !Task.isCancelled else { throw OrbitError.cancelled }
                    do {
                        if attempt > 0 {
                            try await Task.sleep(for: .seconds(1))
                        }
                        let stepStart = CFAbsoluteTimeGetCurrent()
                        try await executeStep(&workflowStep, services: services, artifacts: &artifacts, approvalMode: approvalMode)
                        let stepDuration = (CFAbsoluteTimeGetCurrent() - stepStart) * 1000
                        lastError = nil
                        eventBus?.publish(WorkflowStepCompletedEvent(
                            executionId: executionId, stepName: step.name, stepIndex: stepIndex,
                            durationMs: stepDuration, outcome: "succeeded", error: nil,
                            timestamp: Date()
                        ))
                        break
                    } catch {
                        lastError = error
                        let stepDuration = 0.0
                        eventBus?.publish(WorkflowStepCompletedEvent(
                            executionId: executionId, stepName: step.name, stepIndex: stepIndex,
                            durationMs: stepDuration, outcome: "failed", error: error.localizedDescription,
                            timestamp: Date()
                        ))
                        log.warning("Step '\(step.name)' attempt \(attempt + 1) failed: \(error.localizedDescription)")
                    }
                }

                if let error = lastError {
                    execution.status = .failed
                    execution.error = "Step '\(step.name)' failed: \(error.localizedDescription)"
                    execution.completedAt = Date()
                    store.saveExecution(execution)
                    throw OrbitError.stepFailed(step.name, error.localizedDescription)
                }

                let result = workflowStep.result ?? ""
                execution.stepResults[step.id] = result

                for (outputKey, varName) in step.outputMapping {
                    variables[varName] = extractVariable(from: result, key: outputKey)
                }

                execution.variables = variables
                store.saveExecution(execution)
            }

            execution.status = .completed
            execution.completedAt = Date()
            execution.variables = variables
            store.saveExecution(execution)
            let totalDuration = (CFAbsoluteTimeGetCurrent() - workflowStartTime) * 1000
            eventBus?.publish(WorkflowCompletedEvent(
                executionId: executionId, workflowId: definition.id, status: "completed",
                totalSteps: definition.steps.count, failedSteps: 0,
                totalDurationMs: totalDuration, error: nil, timestamp: Date()
            ))
            log.notice("Workflow '\(definition.name)' completed successfully")
            return execution
        } catch {
            if execution.status != .failed && execution.status != .cancelled {
                execution.status = .failed
                execution.error = error.localizedDescription
                execution.completedAt = Date()
                store.saveExecution(execution)
            }
            let totalDuration = (CFAbsoluteTimeGetCurrent() - workflowStartTime) * 1000
            eventBus?.publish(WorkflowCompletedEvent(
                executionId: executionId, workflowId: definition.id, status: execution.status.rawValue,
                totalSteps: definition.steps.count, failedSteps: execution.status == .failed ? 1 : 0,
                totalDurationMs: totalDuration, error: execution.error, timestamp: Date()
            ))
            throw error
        }
    }

    private func evaluateCondition(_ condition: String, variables: [String: String]) -> Bool {
        if condition.hasPrefix("$") {
            let varName = String(condition.dropFirst())
            return variables[varName] != nil && !(variables[varName]?.isEmpty ?? true)
        }
        if condition.contains("==") {
            let parts = condition.components(separatedBy: "==").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { return true }
            let left = resolveValue(parts[0], variables: variables)
            let right = resolveValue(parts[1], variables: variables)
            return left == right
        }
        if condition.contains("!=") {
            let parts = condition.components(separatedBy: "!=").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { return true }
            let left = resolveValue(parts[0], variables: variables)
            let right = resolveValue(parts[1], variables: variables)
            return left != right
        }
        return true
    }

    private func resolveValue(_ expression: String, variables: [String: String]) -> String {
        if expression.hasPrefix("$") {
            return variables[String(expression.dropFirst())] ?? ""
        }
        return expression
    }

    private func extractVariable(from result: String, key: String) -> String {
        if key == "_output" || key.isEmpty {
            return result
        }
        if let data = result.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let value = json[key] {
            return "\(value)"
        }
        return result
    }

    // MARK: - Unified Step Execution

    func executeStep(_ step: inout Step, services: StepServices, artifacts: inout [Artifact], approvalMode: ApprovalMode = .interactive, sessionId: String? = nil, conversationId: String? = nil) async throws {
        switch step.stepType {
        case .research:
            guard let research = services.research, let llm = services.llmProvider else {
                throw OrbitError.stepFailed(step.name, "Research requires ResearchService and LLM provider")
            }
            let params = services.llmParameters ?? ModelParameters()

            let desc = step.name.lowercased()
            let isDeep = desc.contains("deep research") || desc.contains("thorough") || desc.contains("comprehensive") || desc.contains("in-depth")

            if step.retryCount == 0 {
                if isDeep { services.onProgress("## Deep Research\n\n") } else { services.onProgress("## Research\n\n") }
                services.onProgress("Searching the web...\n\n")
            }

            let webContent: String
            if isDeep {
                if step.retryCount == 0 { services.onProgress("Running multi-step investigation...\n\n") }
                webContent = try await research.deepSearch(query: step.name, provider: llm)
            } else {
                if step.retryCount == 0 { services.onProgress("Fetching full page content...\n\n") }
                webContent = try await research.searchWithPageContent(query: step.name)
            }

            if step.retryCount == 0 { services.onProgress("Found relevant results. Analyzing...\n\n") }

            var researchMessages = [LLMMessage]()
            if let memory = services.memory {
                researchMessages.append(contentsOf: await memory.contextMessages(
                    query: step.name,
                    recentMessages: services.messages,
                    conversationId: services.conversationId,
                    workspaceId: services.workspaceId,
                    workspaceName: services.workspaceName,
                    workspacePath: services.workspacePath,
                    workspaceKBIds: services.workspaceKBIds
                ))
            }
            researchMessages.append(LLMMessage(role: .system, content: "Synthesize the following search results into a comprehensive, well-structured answer. Include specific details, dates, and context. Cite sources using [1], [2], etc. when referencing information from specific sources."))
            researchMessages.append(LLMMessage(role: .user, content: "Query: \(step.name)\n\nSearch Results:\n\(webContent)"))

            let stream = llm.completeStreaming(messages: researchMessages, parameters: params)
            for try await token in stream {
                if Task.isCancelled { break }
                services.onToken(token)
            }
            services.flushTokens()

            services.onProgress("\n\n---\n\n**Key Facts:**\n\n")
            do {
                let facts = try await research.extractFacts(from: webContent, provider: llm)
                services.onProgress(facts)
            } catch {
                log.warning("Fact extraction failed: \(error.localizedDescription)")
                services.onProgress("Unable to extract structured facts.")
            }
            services.onProgress("\n\n")

        case .generate:
            guard let document = services.document, let llm = services.llmProvider else {
                throw OrbitError.stepFailed(step.name, "Generate requires DocumentService and LLM provider")
            }
            let params = services.llmParameters ?? ModelParameters()

            services.onProgress("## Generated Content\n\n")

            let outputType = step.outputType ?? .markdown
            let systemPrompt: String
            switch outputType {
            case .presentation:
                systemPrompt = "Create presentation content in markdown. Use ## for each slide title. Include bullet points and text for slide body content."
            case .document:
                systemPrompt = "Create a well-formatted document in markdown. Use proper headings, paragraphs, and structure."
            case .spreadsheet:
                systemPrompt = "Create CSV-formatted data. Include headers in the first row. Use commas as delimiters. Return ONLY the CSV data."
            case .markdown:
                systemPrompt = "Create high-quality content based on the request. Use markdown formatting."
            case .pdf:
                systemPrompt = "Create content suitable for a PDF document. Use markdown formatting."
            case .folder:
                systemPrompt = "Create a multi-file project. Use FILE: path/to/file markers before each file's content."
            case .code:
                systemPrompt = "Generate source code files. Use FILE: path/to/file markers before each file's content."
            }

            var genMessages = [LLMMessage(role: .system, content: systemPrompt)]
            let userMsgs = services.messages.filter { $0.role == .user }.map { msg in
                LLMMessage(role: .user, content: msg.content, images: msg.images)
            }
            genMessages.append(contentsOf: userMsgs)
            genMessages.append(LLMMessage(role: .user, content: step.name))

            let genStream = llm.completeStreaming(messages: genMessages, parameters: params)
            var generatedContent = ""
            for try await token in genStream {
                if Task.isCancelled { break }
                generatedContent += token
                services.onToken(token)
            }
            services.flushTokens()

            let baseFilename = services.sanitizeFilename(step.name)
            let fileURL: URL
            let artifactType: Artifact.ArtifactType

            switch outputType {
            case .presentation:
                artifactType = .presentation
                let url = try await document.generatePresentation(title: step.name, content: generatedContent)
                services.onProgress("\n\nCreated presentation: [\(url.lastPathComponent)](\(url.path))\n\n")
                fileURL = url
            case .document:
                artifactType = .document
                let url = try await document.generateDocument(title: step.name, content: generatedContent)
                services.onProgress("\n\nCreated document: [\(url.lastPathComponent)](\(url.path))\n\n")
                fileURL = url
            case .spreadsheet:
                artifactType = .spreadsheet
                let url = try await document.generateSpreadsheet(title: step.name, csvContent: generatedContent)
                services.onProgress("\n\nCreated spreadsheet: [\(url.lastPathComponent)](\(url.path))\n\n")
                fileURL = url
            case .markdown:
                artifactType = .markdown
                let url = try document.saveToDisk(filename: baseFilename + ".md", content: generatedContent)
                services.onProgress("\n\nCreated: [\(url.lastPathComponent)](\(url.path))\n\n")
                fileURL = url
            case .pdf:
                artifactType = .pdf
                let url = try await document.generatePDF(title: step.name, content: generatedContent)
                services.onProgress("\n\nCreated PDF: [\(url.lastPathComponent)](\(url.path))\n\n")
                fileURL = url
            case .folder:
                artifactType = .folder
                let url = try await document.generateProjectFolder(title: step.name, content: generatedContent)
                services.onProgress("\n\nCreated project folder: [\(url.lastPathComponent)](\(url.path))\n\n")
                fileURL = url
            case .code:
                artifactType = .code
                let url = try await document.generateProjectFolder(title: step.name, content: generatedContent)
                services.onProgress("\n\nCreated code project: [\(url.lastPathComponent)](\(url.path))\n\n")
                fileURL = url
            }

            let artifact = Artifact(filename: fileURL.lastPathComponent, type: artifactType, content: "", fileURL: fileURL)
            artifacts.append(artifact)
            step.result = fileURL.lastPathComponent

        case .action:
            let actionResult: String
            if let toolName = step.toolName {
                actionResult = try await toolService.executeTool(named: toolName, input: step.input, approvalMode: approvalMode, sessionId: sessionId, conversationId: conversationId)
            } else {
                actionResult = "[Action noted: \(step.name)]"
            }
            services.onProgress("- \(actionResult)\n\n")
            step.result = actionResult

        case .screenshot:
            services.onProgress("## Screenshot\n\nCapturing screen...\n\n")
            let engine = ScreenshotEngine()
            let desc = step.name.lowercased()
            let mode: ScreenshotEngine.CaptureMode = {
                if desc.contains("window") || desc.contains("active") || desc.contains("frontmost") { return .activeWindow }
                if desc.contains("all") || desc.contains("every") { return .allDisplays }
                if desc.contains("select") || desc.contains("region") || desc.contains("area") || desc.contains("drag") { return .selection }
                return .mainDisplay
            }()
            let artifactsDir = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Orbit/Artifacts", isDirectory: true)
            try? FileManager.default.createDirectory(at: artifactsDir, withIntermediateDirectories: true)

            if let url = engine.captureAndSave(mode: mode, to: artifactsDir) {
                services.onProgress("Captured: [\(url.lastPathComponent)](\(url.path))\n\n")
                let artifact = Artifact(filename: url.lastPathComponent, type: .markdown, content: "", fileURL: url)
                artifacts.append(artifact)
                step.result = url.lastPathComponent

                if desc.contains("analyze") || desc.contains("describe") || desc.contains("what") || desc.contains("see") {
                    guard let llm = services.llmProvider else {
                        throw OrbitError.stepFailed(step.name, "Screenshot analysis requires LLM provider")
                    }
                    let params = services.llmParameters ?? ModelParameters()

                    services.onProgress("Analyzing screenshot...\n\n")
                    let imageData = (try? Data(contentsOf: url)) ?? Data()
                    let base64 = imageData.base64EncodedString()
                    let ext = url.pathExtension
                    let mimeType = ext == "png" ? "image/png" : "image/jpeg"
                    let attachment = ImageAttachment(mimeType: mimeType, base64Data: base64)
                    var analysisMessages = [LLMMessage]()
                    if let memory = services.memory {
                        analysisMessages.append(contentsOf: await memory.contextMessages(
                            query: step.name,
                            recentMessages: services.messages,
                            conversationId: services.conversationId,
                            workspaceId: services.workspaceId,
                            workspaceName: services.workspaceName,
                            workspacePath: services.workspacePath,
                            workspaceKBIds: services.workspaceKBIds
                        ))
                    }
                    analysisMessages.append(LLMMessage(role: .system, content: "Analyze what's shown in this screenshot. Describe what you see in detail, including any text, UI elements, windows, or content visible."))
                    analysisMessages.append(LLMMessage(role: .user, content: "Analyze this screenshot: \(step.name)", images: [attachment]))
                    let analysisStream = llm.completeStreaming(messages: analysisMessages, parameters: params)
                    services.onProgress("\n\n### Analysis\n\n")
                    for try await token in analysisStream {
                        if Task.isCancelled { break }
                        services.onToken(token)
                    }
                    services.flushTokens()
                    services.onProgress("\n\n")
                }
            } else {
                services.onProgress("Failed to capture screenshot.\n\n")
            }

        case .llm:
            guard let llm = services.llmProvider else {
                throw OrbitError.stepFailed(step.name, "LLM step requires LLM provider")
            }
            let params = services.llmParameters ?? ModelParameters()

            services.onProgress("## Processing\n\n")
            var llmMessages = [LLMMessage(role: .system, content: "Complete the following task.")]
            let userMsgs = services.messages.filter { $0.role == .user }.map { msg in
                LLMMessage(role: .user, content: msg.content, images: msg.images)
            }
            llmMessages.append(contentsOf: userMsgs)
            llmMessages.append(LLMMessage(role: .user, content: step.name))
            let stream = llm.completeStreaming(messages: llmMessages, parameters: params)
            for try await token in stream {
                if Task.isCancelled { break }
                services.onToken(token)
            }
            services.onProgress("\n\n")
        }
    }

    // MARK: - ReAct Execution

    private struct AgentDecision: Codable, Sendable {
        let action: String
        let tool: String?
        let input: [String: String]?
        let summary: String?
        let thought: String?
    }

    func executeReAct(
        goalDescription: String,
        maxSteps: Int = 25,
        contextMessages: [LLMMessage],
        llm: LLMProvider,
        tools: ToolRegistry,
        parameters: ModelParameters,
        checkpointManager: CheckpointManager?,
        executionId: String,
        conversationId: String?,
        approvalMode: ApprovalMode,
        initialStepCount: Int = 0,
        initialToolFailures: [String: Int] = [:],
        eventBus: EventBus? = nil
    ) -> AsyncStream<AgentEvent> {
        AsyncStream { continuation in
            let alreadyExecuting = reactLock.withLock { current in
                guard !current else { return true }
                current = true
                return false
            }
            guard !alreadyExecuting else {
                log.warning("ReAct already executing — rejecting concurrent request")
                continuation.finish()
                return
            }
            Task {
                defer { reactLock.withLock { $0 = false } }
                var messages = contextMessages
                let toolsJSON = toolDefinitionsJSON(tools: tools)
                var stepCount = initialStepCount
                var toolFailures = initialToolFailures

                let systemPrompt = """
                You are an autonomous agent. Your goal: \(goalDescription)

                Available tools:
                \(toolsJSON)

                You MUST respond with JSON only. Choose one:

                {"action":"tool","tool":"<name>","input":{...}}
                {"action":"complete","summary":"What was done"}
                {"action":"think","thought":"Your reasoning"}

                Rules:
                - Execute ONE tool at a time
                - After each tool result, decide the next action
                - If a tool fails, try a different approach
                - Call "complete" when the goal is achieved
                - Do NOT call a tool more than 3 times if it keeps failing
                - For open-ended tasks like research, gather information first then synthesize
                """

                messages.insert(LLMMessage(role: .system, content: systemPrompt), at: 0)

                while stepCount < maxSteps {
                    if Task.isCancelled { break }
                    stepCount += 1

                    do {
                        let response = try await llm.complete(messages: messages, parameters: parameters)

                        guard let data = response.data(using: .utf8),
                              let decision = try? JSONDecoder().decode(AgentDecision.self, from: data)
                        else {
                            messages.append(LLMMessage(role: .user, content: "Your response was not valid JSON. Respond with one of the valid JSON formats."))
                            continue
                        }

                        switch decision.action {
                        case "complete":
                            let summary = decision.summary ?? goalDescription
                            continuation.yield(.completed(summary))
                            continuation.finish()
                            eventBus?.publish(AgentActionEvent(executionId: executionId, actionType: "complete", toolName: nil, detail: summary, timestamp: Date()))
                            log.info("Agent completed goal: \(summary)")
                            return

                        case "think":
                            let thought = decision.thought ?? "..."
                            continuation.yield(.thought(thought))
                            eventBus?.publish(AgentActionEvent(executionId: executionId, actionType: "think", toolName: nil, detail: thought, timestamp: Date()))
                            messages.append(LLMMessage(role: .assistant, content: "[Thinking: \(thought)]"))
                            saveCheckpoint(goalDescription: goalDescription, maxSteps: maxSteps, messages: messages, stepCount: stepCount, toolFailures: toolFailures, executionId: executionId, conversationId: conversationId, checkpointManager: checkpointManager)

                        case "tool":
                            let toolName = decision.tool ?? ""
                            let input = decision.input ?? [:]

                            guard tools.tool(named: toolName) != nil else {
                                let available = tools.allToolNames.joined(separator: ", ")
                                let errorMsg = "Tool '\(toolName)' not found. Available tools: \(available)"
                                continuation.yield(.error(errorMsg))
                                messages.append(LLMMessage(role: .user, content: errorMsg))
                                continue
                            }

                            let failures = toolFailures[toolName, default: 0]
                            if failures >= 3 {
                                messages.append(LLMMessage(role: .user, content: "Tool '\(toolName)' has failed \(failures) times. Do not use it again. Try a completely different approach."))
                                continue
                            }

                            continuation.yield(.toolExecution(toolName: toolName, input: input))
                            eventBus?.publish(AgentActionEvent(executionId: executionId, actionType: "tool_execution", toolName: toolName, detail: nil, timestamp: Date()))

                            var toolStep = Step(name: toolName, stepType: .action, toolName: toolName, input: input)
                            var reactArtifacts: [Artifact] = []
                            let reactServices = StepServices()

                            do {
                                try await executeStep(&toolStep, services: reactServices, artifacts: &reactArtifacts, approvalMode: approvalMode, sessionId: executionId, conversationId: conversationId)
                                let result = toolStep.result ?? ""
                                continuation.yield(.toolResult(toolName: toolName, output: result))
                                messages.append(LLMMessage(role: .assistant, content: "[\(toolName) result: \(result)]"))
                            } catch {
                                toolFailures[toolName, default: 0] += 1
                                let errorMsg = "Tool '\(toolName)' failed: \(error.localizedDescription)"
                                continuation.yield(.error(errorMsg))
                                eventBus?.publish(AgentActionEvent(executionId: executionId, actionType: "error", toolName: toolName, detail: errorMsg, timestamp: Date()))
                                messages.append(LLMMessage(role: .user, content: errorMsg + "\n\nTry a different approach or tool."))
                            }
                            saveCheckpoint(goalDescription: goalDescription, maxSteps: maxSteps, messages: messages, stepCount: stepCount, toolFailures: toolFailures, executionId: executionId, conversationId: conversationId, checkpointManager: checkpointManager)

                        default:
                            messages.append(LLMMessage(role: .user, content: "Unknown action '\(decision.action)'. Valid actions: tool, complete, think"))
                        }
                    } catch {
                        continuation.yield(.error("Agent loop error: \(error.localizedDescription)"))
                        break
                    }
                }

                let summary = stepCount >= maxSteps
                    ? "Reached maximum steps (\(maxSteps))"
                    : "Goal incomplete"
                continuation.yield(.completed(summary))
                continuation.finish()
            }
        }
    }

    private func toolDefinitionsJSON(tools: ToolRegistry) -> String {
        let defs = tools.allDefinitions
        guard let data = try? JSONEncoder().encode(defs),
              let str = String(data: data, encoding: .utf8)
        else { return "[]" }
        return str
    }

    private func saveCheckpoint(goalDescription: String, maxSteps: Int, messages: [LLMMessage], stepCount: Int, toolFailures: [String: Int], executionId: String, conversationId: String?, checkpointManager: CheckpointManager?) {
        guard let checkpointManager else { return }
        let checkpoint = ExecutionCheckpoint(
            id: executionId,
            goalDescription: goalDescription,
            messages: messages,
            stepCount: stepCount,
            toolFailures: toolFailures,
            conversationId: conversationId,
            createdAt: Date()
        )
        try? checkpointManager.save(checkpoint)
    }
}
