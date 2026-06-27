import Foundation

final class WorkflowTool: Tool {
    var definition = ToolDefinition(
        id: "runWorkflow",
        name: "Run Workflow",
        description: "Execute a named workflow with optional input variables. Workflows are predefined multi-step processes that chain tool calls together.",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "workflowId", description: "The ID of the workflow to execute", type: .string, required: true),
            ToolParameter(name: "variables", description: "JSON object of input variable values (e.g. {\"name\": \"value\"})", type: .string, required: false),
        ])
    )

    weak var engine: WorkflowEngine?

    func run(input: [String: String]) async throws -> String {
        guard let engine else { return "Workflow engine not available" }
        guard let workflowId = input["workflowId"], !workflowId.isEmpty else {
            return "Missing required parameter: workflowId"
        }

        var variables: [String: String] = [:]
        if let varsJSON = input["variables"], !varsJSON.isEmpty {
            guard let data = varsJSON.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
                return "Invalid variables JSON. Expected an object with string values."
            }
            variables = dict
        }

        do {
            let execution = try await engine.execute(workflowId: workflowId, inputVariables: variables)
            var summary = "Workflow execution \(execution.id.prefix(8)) completed with status: \(execution.status.rawValue)"
            if let error = execution.error {
                summary += "\nError: \(error)"
            }
            summary += "\n\nStep results:\n"
            for (stepId, result) in execution.stepResults {
                let preview = result.prefix(200)
                summary += "- Step \(stepId.prefix(8)): \(preview)\n"
            }
            return summary
        } catch {
            return "Workflow execution failed: \(error.localizedDescription)"
        }
    }
}
