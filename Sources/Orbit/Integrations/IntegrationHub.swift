import Foundation

final class IntegrationHub {
    private var connectors: [String: Connector] = [:]
    weak var toolRegistry: ToolRegistry?

    func register(_ connector: Connector) {
        connectors[connector.id] = connector
    }

    func connector(id: String) -> Connector? {
        connectors[id]
    }

    func allConnectors() -> [Connector] {
        Array(connectors.values)
    }

    func registerTools() {
        guard let registry = toolRegistry else { return }
        for connector in connectors.values {
            for tool in connector.tools {
                registry.register(tool)
            }
        }
    }

    func tools(connectorId: String) -> [Tool] {
        connectors[connectorId]?.tools ?? []
    }
}
