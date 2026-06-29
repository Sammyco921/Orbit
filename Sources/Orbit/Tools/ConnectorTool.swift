import Foundation

final class ConnectorStatusTool: Tool {
    var definition = ToolDefinition(
        id: "connectorStatus",
        name: "Connector Status",
        description: "List all available service connectors and their connection status",
        inputSchema: ToolSchema(parameters: [])
    )

    var integrationHub: IntegrationHub?

    func run(input: [String: String]) async throws -> String {
        guard let hub = integrationHub else {
            return "Integration hub not available."
        }
        let connectors = hub.allConnectors()
        guard !connectors.isEmpty else {
            return "No connectors registered."
        }
        var result = "**Connectors:**\n"
        for connector in connectors {
            result += "- \(connector.name) (\(connector.id)): \(connector.tools.count) tool(s)\n"
        }
        return result
    }
}
