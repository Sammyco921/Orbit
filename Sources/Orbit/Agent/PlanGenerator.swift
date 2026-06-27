import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "planner")

struct GeneratedPlan: Codable, Sendable {
    let summary: String
    let steps: [GeneratedStep]
}

struct GeneratedStep: Codable, Sendable {
    let description: String
    let tool: String
    let input: [String: String]
    let dependencies: [Int]
}

private struct PlanResponse: Codable {
    let summary: String?
    let steps: [PlanResponseStep]?
    let action: String?
    let reason: String?
}

private struct PlanResponseStep: Codable {
    let description: String
    let tool: String?
    let input: [String: String]?
    let dependencies: [Int]?
}

enum PlanGenerationResult: Sendable {
    case plan(GeneratedPlan)
    case direct
}

final class PlanGenerator {
    private let tools: ToolRegistry
    private let llm: LLMProvider
    private let parameters: ModelParameters

    init(tools: ToolRegistry, llm: LLMProvider, parameters: ModelParameters) {
        self.tools = tools
        self.llm = llm
        self.parameters = parameters
    }

    func generatePlan(
        goal: String,
        completedSteps: [(description: String, result: String)] = [],
        failedSteps: [(description: String, error: String)] = [],
        remainingSteps: [(description: String, tool: String)] = []
    ) async throws -> PlanGenerationResult {
        let toolsJSON = toolDefinitionsJSON()

        let isReplan = !failedSteps.isEmpty || !remainingSteps.isEmpty

        let prompt: String
        if isReplan {
            let completedText = completedSteps.isEmpty ? "None yet" : completedSteps.map { "✓ \($0.description) → \($0.result)" }.joined(separator: "\n")
            let failedText = failedSteps.map { "✗ \($0.description) — \($0.error)" }.joined(separator: "\n")
            let remainingText = remainingSteps.map { "• \($0.description) (tool: \($0.tool))" }.joined(separator: "\n")

            prompt = """
            You are a task planner adapting to a failure. The original goal was:

            "\(goal)"

            Completed steps:
            \(completedText)

            Failed steps:
            \(failedText)

            Remaining work that still needs to be done:
            \(remainingText)

            Available tools:
            \(toolsJSON)

            Create a REVISED plan for the REMAINING work. The failed steps can be retried differently or replaced with alternative approaches.
            Respond with JSON only:
            {"summary":"Brief revised plan summary","steps":[{"description":"What this step does","tool":"toolName","input":{"param":"value"},"dependencies":[]}]}

            Rules:
            - Each step is ONE tool call with specific parameters
            - Steps that can run in parallel have empty dependencies
            - Dependencies reference step indices within THIS revised plan (0-based)
            - Use the exact tool names and parameter keys from the available tools
            - If the remaining work is simple enough for direct ReAct, respond with {"action":"direct","reason":"..."}
            """
        } else {
            prompt = """
            You are a task planner. Given a goal and available tools, create a step-by-step plan.

            Goal: \(goal)

            Available tools:
            \(toolsJSON)

            Respond with JSON only. Choose ONE format:

            1. Multi-step plan:
            {"summary":"Brief plan summary","steps":[{"description":"What this step does","tool":"toolName","input":{"param":"value"},"dependencies":[]}]}

            2. If the goal is simple and needs a single tool call or ReAct loop:
            {"action":"direct","reason":"Why this needs ReAct rather than a static plan"}

            Rules for plans:
            - Each step is ONE tool call with specific parameters
            - Steps that can run in parallel have empty dependencies
            - Steps that depend on previous results list those step indices as dependencies (e.g. [0] depends on step 0)
            - Dependencies must form a valid DAG (no cycles, indices are 0-based)
            - First steps must have empty dependencies
            - Use the exact tool names and parameter keys from the available tools
            """
        }

        return try await callPlanner(prompt: prompt)
    }

    func validatePlan(_ plan: GeneratedPlan) -> Bool {
        let stepCount = plan.steps.count
        guard stepCount > 0 else { return false }

        for (i, step) in plan.steps.enumerated() {
            guard tools.tool(named: step.tool) != nil else {
                log.warning("Plan step \(i): tool '\(step.tool)' not found")
                return false
            }
            for dep in step.dependencies {
                guard dep >= 0, dep < stepCount, dep != i else {
                    log.warning("Plan step \(i): invalid dependency \(dep)")
                    return false
                }
            }
        }

        var visited = Set<Int>()
        var inStack = Set<Int>()
        func hasCycle(_ i: Int) -> Bool {
            guard !visited.contains(i) else { return false }
            guard !inStack.contains(i) else { return true }
            inStack.insert(i)
            for dep in plan.steps[i].dependencies {
                if hasCycle(dep) { return true }
            }
            inStack.remove(i)
            visited.insert(i)
            return false
        }
        for i in 0..<stepCount {
            if hasCycle(i) {
                log.warning("Plan has a cycle involving step \(i)")
                return false
            }
        }

        return true
    }

    private func callPlanner(prompt: String) async throws -> PlanGenerationResult {
        let response = try await llm.complete(messages: [
            LLMMessage(role: .system, content: "You are a precise task planner. Output only valid JSON."),
            LLMMessage(role: .user, content: prompt)
        ], parameters: parameters)

        guard let data = response.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(PlanResponse.self, from: data)
        else {
            log.warning("Failed to parse planner response")
            return .direct
        }

        if parsed.action == "direct" {
            log.info("Planner chose direct ReAct: \(parsed.reason ?? "no reason")")
            return .direct
        }

        guard let summary = parsed.summary,
              let steps = parsed.steps,
              !steps.isEmpty
        else {
            log.warning("Planner returned invalid plan")
            return .direct
        }

        let generatedSteps = steps.enumerated().compactMap { (i, s) -> GeneratedStep? in
            guard let tool = s.tool, !tool.isEmpty, let input = s.input else {
                log.warning("Plan step \(i) missing tool or input")
                return nil
            }
            return GeneratedStep(
                description: s.description,
                tool: tool,
                input: input,
                dependencies: s.dependencies ?? []
            )
        }

        guard generatedSteps.count == steps.count else {
            log.warning("Some replan steps were invalid")
            return .direct
        }

        let plan = GeneratedPlan(summary: summary, steps: generatedSteps)
        guard validatePlan(plan) else {
            log.warning("Revised plan validation failed")
            return .direct
        }

        log.info("Revised plan: \(plan.summary) (\(plan.steps.count) steps)")
        return .plan(plan)
    }

    private func toolDefinitionsJSON() -> String {
        let defs = tools.allDefinitions
        guard let data = try? JSONEncoder().encode(defs),
              let str = String(data: data, encoding: .utf8)
        else { return "[]" }
        return str
    }
}
