import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "tools")

final class ToolService {
    let toolRegistry = ToolRegistry()
    let kernel: ExecutionKernel
    let permissionGate: PermissionGate
    let mcpServer: MCPServer

    private let screenService: ScreenUnderstandingService

    init(eventBus: EventBus, screenUnderstandingService: ScreenUnderstandingService, auditService: AuditService? = nil) {
        self.screenService = screenUnderstandingService

        let permissionGate = PermissionGate(permissionManager: PermissionManager())
        self.permissionGate = permissionGate
        let eventCommitter = EventCommitter(auditService: auditService, eventBus: eventBus)
        kernel = ExecutionKernel(
            toolRegistry: toolRegistry,
            permissionGate: permissionGate,
            eventCommitter: eventCommitter
        )

        mcpServer = MCPServer(toolRegistry: toolRegistry)
        registerDefaultTools()
        mcpServer.toolService = self
    }

    private func registerDefaultTools() {
        toolRegistry.register(OpenApplicationTool())

        let screenshot = ScreenshotTool()
        screenshot.definition.requiredPermission = .requiresApproval
        toolRegistry.register(screenshot)

        let writeFile = FileWriteTool()
        writeFile.definition.requiredPermission = .requiresApproval
        toolRegistry.register(writeFile)

        let clipboard = ClipboardTool()
        clipboard.definition.requiredPermission = .requiresApproval
        toolRegistry.register(clipboard)

        toolRegistry.register(SystemInfoTool())
        let openURL = OpenURLTool()
        openURL.definition.requiredPermission = .requiresApproval
        toolRegistry.register(openURL)

        let volume = VolumeControlTool()
        volume.definition.requiredPermission = .requiresApproval
        toolRegistry.register(volume)

        toolRegistry.register(NotificationSendTool())
        let finderSearch = FinderSearchTool()
        finderSearch.definition.requiredPermission = .requiresApproval
        toolRegistry.register(finderSearch)
        toolRegistry.register(DiskUsageTool())
        toolRegistry.register(BatteryStatusTool())
        toolRegistry.register(SpeakTool())
        toolRegistry.register(FrontmostAppTool())
        toolRegistry.register(ProcessesTool())

        let killApp = KillAppTool()
        killApp.definition.requiredPermission = .requiresApproval
        toolRegistry.register(killApp)

        let listDir = ListDirectoryTool()
        listDir.definition.requiredPermission = .requiresApproval
        toolRegistry.register(listDir)

        let readFile = ReadFileTool()
        readFile.definition.requiredPermission = .requiresApproval
        toolRegistry.register(readFile)

        let createFolder = CreateFolderTool()
        createFolder.definition.requiredPermission = .requiresApproval
        toolRegistry.register(createFolder)

        toolRegistry.register(NetworkInfoTool())
        toolRegistry.register(DateTimeTool())

        let terminalRun = TerminalRunTool()
        terminalRun.definition.requiredPermission = .requiresApproval
        toolRegistry.register(terminalRun)

        let calendar = CalendarEventTool()
        calendar.definition.requiredPermission = .requiresApproval
        toolRegistry.register(calendar)

        let contacts = ContactLookupTool()
        contacts.definition.requiredPermission = .requiresApproval
        toolRegistry.register(contacts)

        let music = MusicControlTool()
        music.definition.requiredPermission = .requiresApproval
        toolRegistry.register(music)

        let brightness = BrightnessControlTool()
        brightness.definition.requiredPermission = .requiresApproval
        toolRegistry.register(brightness)

        let keyboard = KeyboardTypeTool()
        keyboard.definition.requiredPermission = .requiresApproval
        toolRegistry.register(keyboard)

        let mouse = MouseClickTool()
        mouse.definition.requiredPermission = .requiresApproval
        toolRegistry.register(mouse)

        let dock = DockActionTool()
        dock.definition.requiredPermission = .requiresApproval
        toolRegistry.register(dock)

        let accessibility = AccessibilityActionTool()
        accessibility.definition.requiredPermission = .requiresApproval
        toolRegistry.register(accessibility)

        let fileDelete = FileDeleteTool()
        fileDelete.definition.requiredPermission = .requiresApproval
        toolRegistry.register(fileDelete)

        let fileMove = FileMoveTool()
        fileMove.definition.requiredPermission = .requiresApproval
        toolRegistry.register(fileMove)

        // Git tools
        toolRegistry.register(GitStatusTool())
        toolRegistry.register(GitDiffTool())
        toolRegistry.register(GitLogTool())

        let commit = GitCommitTool()
        commit.definition.requiredPermission = .requiresApproval
        toolRegistry.register(commit)

        let branch = GitBranchTool()
        branch.definition.requiredPermission = .requiresApproval
        toolRegistry.register(branch)

        let push = GitPushTool()
        push.definition.requiredPermission = .requiresApproval
        toolRegistry.register(push)

        let pull = GitPullTool()
        pull.definition.requiredPermission = .requiresApproval
        toolRegistry.register(pull)

        let stash = GitStashTool()
        stash.definition.requiredPermission = .requiresApproval
        toolRegistry.register(stash)

        let initTool = GitInitTool()
        initTool.definition.requiredPermission = .requiresApproval
        toolRegistry.register(initTool)

        let clone = GitCloneTool()
        clone.definition.requiredPermission = .requiresApproval
        toolRegistry.register(clone)

        // Visual tools
        toolRegistry.register(ScreenDescribeTool(screenService: screenService))
        toolRegistry.register(VisualClickTool(screenService: screenService))
        toolRegistry.register(VisualTypeTool(screenService: screenService))
        toolRegistry.register(VisualFormFillTool(screenService: screenService))
    }

    func executeTool(named name: String, input: [String: String], approvalMode: ApprovalMode = .interactive, sessionId: String? = nil, conversationId: String? = nil) async throws -> String {
        let intent = ExecutionIntent(
            action: .tool(name),
            input: input,
            sessionId: sessionId,
            conversationId: conversationId,
            source: .agent,
            approvalMode: approvalMode
        )
        let result = try await kernel.execute(intent: intent)
        return result.output
    }
}
