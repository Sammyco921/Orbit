import Testing
import Foundation
@testable import Orbit

struct ToolServiceTests {

    @Test func toolNotFoundError() async {
        let bus = EventBus()
        let screenService = ScreenUnderstandingService()
        let service = ToolService(eventBus: bus, screenUnderstandingService: screenService)

        await #expect(throws: OrbitError.toolNotFound("nonexistent")) {
            try await service.executeTool(named: "nonexistent", input: [:])
        }
    }

    @Test func registeredToolIsAccessible() {
        let bus = EventBus()
        let screenService = ScreenUnderstandingService()
        let service = ToolService(eventBus: bus, screenUnderstandingService: screenService)

        let tool = service.toolRegistry.tool(named: "systemInfo")
        #expect(tool != nil)
        #expect(tool?.definition.name == "System Information")
    }

    @Test func sensitiveToolsRequireApproval() async {
        let bus = EventBus()
        let screenService = ScreenUnderstandingService()
        let service = ToolService(eventBus: bus, screenUnderstandingService: screenService)

        await #expect(throws: OrbitError.toolRequiresApproval("Take Screenshot")) {
            try await service.executeTool(named: "screenshot", input: [:], approvalMode: .throwOnApproval)
        }
    }

    @Test func toolRegistryListsAllTools() {
        let bus = EventBus()
        let screenService = ScreenUnderstandingService()
        let service = ToolService(eventBus: bus, screenUnderstandingService: screenService)

        let tools = service.toolRegistry.allDefinitions
        #expect(tools.count > 30)
        #expect(tools.contains { $0.id == "systemInfo" })
        #expect(tools.contains { $0.id == "screenshot" })
    }
}
