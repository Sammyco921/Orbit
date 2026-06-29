import AppKit
import Foundation
import CryptoKit
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "runtime")

public final class OrbitRuntime {
    let eventBus = EventBus()
    public let hotkeyService: GlobalHotkeyService
    let workspaceService: WorkspaceService
    let conversationService: ConversationService
    let llmService: LLMService
    let toolService: ToolService
    let memoryService: MemoryService
    let researchService: ResearchService
    let documentService: DocumentService
    let api: OrbitAPI
    let pluginManager: PluginManager
    let agentRegistry: AgentRegistry
    let screenUnderstandingService: ScreenUnderstandingService
    let contextAwarenessService: ContextAwarenessService
    private(set) var knowledgeBaseService: KnowledgeBaseService?

    let database: OrbitDatabase
    let auditService: AuditService
    let goalStore: GoalStore
    let autonomyService: AutonomyService
    let schedulerService: SchedulerService
    let workflowStore: WorkflowStore
    let workflowEngine: WorkflowEngine
    let checkpointManager: CheckpointManager
    let browserRuntime: BrowserRuntime
    let oauthProviderRegistry: OAuthProviderRegistry
    let tokenStore: TokenStore
    let oauthService: OAuthService
    let integrationHub: IntegrationHub
    let webhookService: WebhookService
    let discoveryStore: DiscoveryStore
    let classificationService: ClassificationService
    let discoveryService: DiscoveryService
    let searchService: SearchService
    let monitoringService: MonitoringService
    let templateStore: TemplateStore
    let templateRegistry: TemplateRegistry
    private var backgroundTasks: [Task<Void, Never>] = []
    private var startTask: Task<Void, Never>?
    private var sleepObservers: [NSObjectProtocol] = []

    deinit {
        startTask?.cancel()
        for task in backgroundTasks { task.cancel() }
        for observer in sleepObservers { NotificationCenter.default.removeObserver(observer) }
        let ctx = ExecutionContext(executionId: UUID().uuidString, conversationId: nil, workspaceId: nil, source: .internal, timeout: nil, createdAt: Date())
        browserRuntime.close(context: ctx)
    }

    init(settings: AppSettings) {
        database = Self.createDatabase(settings: settings)
        auditService = AuditService(db: database.db)
        goalStore = GoalStore(db: database.db)
        workflowStore = WorkflowStore(db: database.db)
        oauthProviderRegistry = OAuthProviderRegistry()
        tokenStore = TokenStore(db: database.db)
        oauthService = OAuthService(tokenStore: tokenStore, providerRegistry: oauthProviderRegistry)
        integrationHub = IntegrationHub()
        webhookService = WebhookService()
        workspaceService = WorkspaceService()
        conversationService = ConversationService(eventBus: eventBus)
        llmService = LLMService(settingsProvider: { settings })
        discoveryStore = DiscoveryStore(db: database.db)
        classificationService = ClassificationService(llmProvider: llmService.currentProvider())
        discoveryService = DiscoveryService(store: discoveryStore, classification: classificationService)
        searchService = SearchService(discoveryService: discoveryService)
        screenUnderstandingService = ScreenUnderstandingService()
        contextAwarenessService = ContextAwarenessService()
        toolService = ToolService(eventBus: eventBus, screenUnderstandingService: screenUnderstandingService, auditService: auditService)
        workflowEngine = WorkflowEngine(store: workflowStore, toolService: toolService, eventBus: eventBus)
        memoryService = MemoryService(eventBus: eventBus)
        checkpointManager = CheckpointManager(db: database.db)
        autonomyService = AutonomyService(goalStore: goalStore, workflowEngine: workflowEngine, toolService: toolService, memoryService: memoryService, llmService: llmService, checkpointManager: checkpointManager, eventBus: eventBus)
        monitoringService = MonitoringService(db: database.db, eventBus: eventBus)
        templateStore = TemplateStore(db: database.db)
        templateRegistry = TemplateRegistry(store: templateStore, workflowStore: workflowStore)
        schedulerService = SchedulerService()
        researchService = ResearchService()
        documentService = DocumentService()
        api = OrbitAPI()
        pluginManager = PluginManager(toolService: toolService)
        pluginManager.isDevelopmentMode = settings.isDevelopmentMode
        let sharedMemory = SharedMemoryService()
        let commService = AgentCommunicationService(eventBus: eventBus)
        agentRegistry = AgentRegistry()
        agentRegistry.sharedMemory = sharedMemory
        agentRegistry.communicationService = commService
        hotkeyService = GlobalHotkeyService()
        browserRuntime = BrowserRuntime()
        browserRuntime.sessionStore = BrowserSessionStore(db: database.db)
        api.configure(runtime: self, apiKey: settings.apiKey)

        registerShellTools()
        registerAITools()
        registerBrowserTools()
        registerOAuthTools()
        registerIntegrationTools()

        workspaceService.configure(database: database)
        conversationService.configure(database: database, llmService: llmService)
        memoryService.configure(database: database, openAIKey: settings.openAIKey, preferLocal: settings.useLocalEmbeddings, llmService: llmService, enableCrossConversationMemory: settings.enableCrossConversationMemory, auditService: auditService)
        if let embedder = memoryService.embeddingService {
            let kbs = KnowledgeBaseService(db: database.db, embedder: embedder)
            knowledgeBaseService = kbs
            memoryService.setKnowledgeBaseService(kbs)
        }
        conversationService.loadConversations()
    }

    func start(settings: AppSettings) {
        startTask = Task { [weak self] in
            guard let self else { return }
            toolService.mcpServer.startSocket()
            if settings.apiEnabled {
                try? api.start(port: settings.apiPort)
            }
            pluginManager.discover()

            // Auto-detect local LLM providers if none is configured
            if settings.openAIKey.isEmpty, settings.anthropicKey.isEmpty {
                let modelManager = LocalModelManager()
                let result = await modelManager.discoverAll()
                if !result.servers.isEmpty, let server = result.servers.first {
                    settings.localModelURL = server.baseURL
                    settings.localAPIType = server.apiType.rawValue
                    if let model = server.detectedModel {
                        settings.localModelName = model
                    }
                    settings.providerType = .local
                    llmService.resetProvider()
                    log.notice("Auto-detected local LLM at \(server.baseURL) (\(server.apiType.rawValue))")
                }
            }

            hotkeyService.start()
            contextAwarenessService.start()
            monitoringService.start()

            await registerDiscoverers()
            startBackgroundTasks()
        }

        // Sleep/wake lifecycle management
        let nc = NotificationCenter.default
        sleepObservers.append(
            nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                self?.handleSleep()
            }
        )
        sleepObservers.append(
            nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.handleWake()
            }
        )
    }

    private func handleSleep() {
        log.notice("System sleeping — pausing browser runtime")
        let ctx = ExecutionContext(executionId: "sleep-\(UUID().uuidString.prefix(8))", conversationId: nil, workspaceId: nil, source: .internal, timeout: nil, createdAt: Date())
        browserRuntime.close(context: ctx)
    }

    private func handleWake() {
        log.notice("System woke — browser runtime ready for re-launch on next use")
    }

    private func startBackgroundTasks() {
        Task { await webhookService.setWorkflowHandler { [weak self] eventType, payload in
            guard let self else { return }
            let eventJSON = (try? JSONSerialization.data(withJSONObject: payload)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            await self.workflowEngine.processWebhookEvent(type: eventType, payload: eventJSON)
        }}

        schedulerService.registerHandler(id: "goals") { [weak self] in
            await self?.autonomyService.processDueGoals()
        }
        schedulerService.registerHandler(id: "workflows") { [weak self] in
            await self?.workflowEngine.processDueWorkflows()
        }
        schedulerService.start()

        let t1 = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            await self?.memoryService.startConsolidationIfNeeded()
        }
        let t2 = Task { [weak self] in
            try? await Task.sleep(for: .seconds(45))
            await self?.pluginManager.checkForUpdates()
        }
        let t3 = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard let self else { return }
            await self.discoveryService.runIncrementalIndex()
            log.notice("Initial discovery index complete")
        }
        backgroundTasks = [t1, t2, t3]
    }

    private func registerShellTools() {
        let shellTool = ScriptShellTool()
        shellTool.definition.requiredPermission = .requiresApproval
        toolService.toolRegistry.register(shellTool)
    }

    private func registerAITools() {
        let summarize = SummarizeTool()
        summarize.llmService = llmService
        toolService.toolRegistry.register(summarize)

        let explain = ExplainTool()
        explain.llmService = llmService
        toolService.toolRegistry.register(explain)

        let translate = TranslateTool()
        translate.llmService = llmService
        toolService.toolRegistry.register(translate)

        let refactor = RefactorTool()
        refactor.llmService = llmService
        toolService.toolRegistry.register(refactor)

        let wfTool = WorkflowTool()
        wfTool.engine = workflowEngine
        toolService.toolRegistry.register(wfTool)

        // Content generation tools
        let docTool = GenerateDocumentTool()
        docTool.documentService = documentService
        toolService.toolRegistry.register(docTool)

        let sheetTool = GenerateSpreadsheetTool()
        sheetTool.documentService = documentService
        toolService.toolRegistry.register(sheetTool)

        let pdfTool = GeneratePDFTool()
        pdfTool.documentService = documentService
        toolService.toolRegistry.register(pdfTool)

        let pptTool = GeneratePresentationTool()
        pptTool.documentService = documentService
        toolService.toolRegistry.register(pptTool)

        // Web search and deep research tools
        let webSearch = WebSearchTool()
        webSearch.researchService = researchService
        toolService.toolRegistry.register(webSearch)

        let deepResearch = DeepResearchTool()
        deepResearch.researchService = researchService
        deepResearch.llmService = llmService
        toolService.toolRegistry.register(deepResearch)

        // Persistent project memory tools
        let remember = RememberTool()
        remember.memoryService = memoryService
        toolService.toolRegistry.register(remember)

        let recall = RecallTool()
        recall.memoryService = memoryService
        toolService.toolRegistry.register(recall)

        // Schedule management tool
        let schedule = CreateScheduleTool()
        schedule.schedulerService = schedulerService
        toolService.toolRegistry.register(schedule)

        // Visual coding tool
        let visualCoding = VisualCodingTool()
        visualCoding.screenService = screenUnderstandingService
        visualCoding.llmService = llmService
        toolService.toolRegistry.register(visualCoding)

        // Connector status tool
        let connectorStatus = ConnectorStatusTool()
        connectorStatus.integrationHub = integrationHub
        toolService.toolRegistry.register(connectorStatus)
    }

    private func registerBrowserTools() {
        let navigate = NavigateTool(runtime: browserRuntime)
        navigate.definition.requiredPermission = .requiresApproval
        toolService.toolRegistry.register(navigate)

        let click = ClickTool(runtime: browserRuntime)
        click.definition.requiredPermission = .requiresApproval
        toolService.toolRegistry.register(click)

        let type = TypeTool(runtime: browserRuntime)
        type.definition.requiredPermission = .requiresApproval
        toolService.toolRegistry.register(type)

        let extract = ExtractTool(runtime: browserRuntime)
        extract.definition.requiredPermission = .requiresApproval
        toolService.toolRegistry.register(extract)

        let screenshot = BrowserScreenshotTool(runtime: browserRuntime)
        screenshot.definition.requiredPermission = .requiresApproval
        toolService.toolRegistry.register(screenshot)

        let js = JavaScriptTool(runtime: browserRuntime)
        js.definition.requiredPermission = .requiresApproval
        toolService.toolRegistry.register(js)

        let pageInfo = PageInfoTool(runtime: browserRuntime)
        pageInfo.definition.requiredPermission = .requiresApproval
        toolService.toolRegistry.register(pageInfo)

        let pressKey = PressKeyTool(runtime: browserRuntime)
        pressKey.definition.requiredPermission = .requiresApproval
        toolService.toolRegistry.register(pressKey)
    }

    private func registerOAuthTools() {
        let connect = ConnectServiceTool(oauthService: oauthService)
        connect.definition.requiredPermission = .requiresApproval
        toolService.toolRegistry.register(connect)

        toolService.toolRegistry.register(ListConnectionsTool(tokenStore: tokenStore))

        let disconnect = DisconnectServiceTool(oauthService: oauthService, tokenStore: tokenStore)
        disconnect.definition.requiredPermission = .requiresApproval
        toolService.toolRegistry.register(disconnect)
    }

    private func registerIntegrationTools() {
        integrationHub.toolRegistry = toolService.toolRegistry

        let gmail = GmailConnector(oauthService: oauthService, tokenStore: tokenStore, providerId: "google")
        integrationHub.register(gmail)

        let github = GitHubConnector(oauthService: oauthService, tokenStore: tokenStore, providerId: "github")
        integrationHub.register(github)

        let slack = SlackConnector(oauthService: oauthService, tokenStore: tokenStore, providerId: "slack")
        integrationHub.register(slack)

        let calendar = CalendarConnector(oauthService: oauthService, tokenStore: tokenStore, providerId: "google")
        integrationHub.register(calendar)

        let notion = NotionConnector(oauthService: oauthService, tokenStore: tokenStore, providerId: "notion")
        integrationHub.register(notion)

        let drive = GoogleDriveConnector(oauthService: oauthService, tokenStore: tokenStore, providerId: "google")
        integrationHub.register(drive)

        integrationHub.registerTools()
        registerDiscoveryTools()
        registerMonitoringTools()
        registerTemplateTools()
    }

    private func registerDiscoveryTools() {
        let indexTool = DiscoveryIndexTool(discoveryService: discoveryService)
        indexTool.definition.requiredPermission = .requiresApproval
        toolService.toolRegistry.register(indexTool)

        toolService.toolRegistry.register(DiscoverySearchTool(searchService: searchService))
        toolService.toolRegistry.register(DiscoverySummaryTool(discoveryService: discoveryService))
        toolService.toolRegistry.register(DiscoveryListTool(discoveryService: discoveryService))
    }

    private func registerDiscoverers() async {
        if let gmail = integrationHub.connector(id: "gmail") as? GmailConnector {
            await discoveryService.registerDiscoverer(GmailDiscoverer(connector: gmail))
        }
        if let drive = integrationHub.connector(id: "drive") as? GoogleDriveConnector {
            await discoveryService.registerDiscoverer(DriveDiscoverer(connector: drive))
        }
        if let github = integrationHub.connector(id: "github") as? GitHubConnector {
            await discoveryService.registerDiscoverer(GitHubDiscoverer(connector: github))
        }
        if let notion = integrationHub.connector(id: "notion") as? NotionConnector {
            await discoveryService.registerDiscoverer(NotionDiscoverer(connector: notion))
        }
        log.notice("Discovery discoverers registered")
    }

    private func registerMonitoringTools() {
        toolService.toolRegistry.register(MonitorStatusTool(monitoringService: monitoringService))
        toolService.toolRegistry.register(MonitorHistoryTool(monitoringService: monitoringService))
        toolService.toolRegistry.register(MonitorReplayTool(monitoringService: monitoringService))
        toolService.toolRegistry.register(MonitorAlertsTool(monitoringService: monitoringService))
    }

    private func registerTemplateTools() {
        templateRegistry.registerBuiltIn(BuiltinTemplates.all)
        templateRegistry.loadUserTemplates()

        toolService.toolRegistry.register(TemplateInstallTool(registry: templateRegistry))
        toolService.toolRegistry.register(TemplateListTool(registry: templateRegistry))

        let deleteTool = TemplateDeleteTool(registry: templateRegistry)
        toolService.toolRegistry.register(deleteTool)

        let exportTool = TemplateExportTool(registry: templateRegistry)
        toolService.toolRegistry.register(exportTool)

        let importTool = TemplateImportTool(registry: templateRegistry)
        toolService.toolRegistry.register(importTool)
    }

    func updateSettings(_ settings: AppSettings) {
        llmService.resetProvider()
        memoryService.configure(database: database, openAIKey: settings.openAIKey, preferLocal: settings.useLocalEmbeddings, llmService: llmService, enableCrossConversationMemory: settings.enableCrossConversationMemory, auditService: auditService)
        api.stop()
        api.configure(runtime: self, apiKey: settings.apiKey)
        if settings.apiEnabled {
            try? api.start(port: settings.apiPort)
        }
        pluginManager.isDevelopmentMode = settings.isDevelopmentMode
        if settings.isDevelopmentMode {
            pluginManager.reloadAll()
        }

        // Handle launch at login
        if settings.launchAtLogin != LaunchAtLoginService.shared.isEnabled {
            try? LaunchAtLoginService.shared.toggle()
        }
    }

    private static func createDatabase(settings: AppSettings) -> OrbitDatabase {
        var attempt: OrbitDatabase?
        var lastError: Error?

        let encKey = settings.apiKey.isEmpty
            ? nil
            : Data(SHA256.hash(data: Data(settings.apiKey.utf8))).base64EncodedString()

        for _ in 0..<2 {
            do {
                let db = try OrbitDatabase(encryptionKey: encKey)
                if db.isDegraded {
                    log.warning("Database degraded — attempting recovery")
                    if db.attemptRecovery() {
                        log.notice("Database recovered from backup")
                    } else {
                        log.warning("Running in degraded mode")
                    }
                }
                attempt = db
                break
            } catch {
                lastError = error
                log.error("Database init failed: \(error.localizedDescription)")
                try? FileManager.default.removeItem(at: OrbitDatabase.storageURL)
                log.notice("Removed corrupted database, retrying...")
            }
        }

        if let db = attempt {
            return db
        }

        log.error("Could not create database after retry: \(lastError?.localizedDescription ?? "unknown"). Attempting emergency temporary database.")
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("orbit_emergency.sqlite")
        _ = try? FileManager.default.removeItem(at: tempURL)
        if let emergencyDB = try? OrbitDatabase(storageURL: tempURL) {
            return emergencyDB
        }
        log.critical("Could not create persistent database. App will operate without storage.")
        guard let fallback = try? OrbitDatabase(storageURL: FileManager.default.temporaryDirectory.appendingPathComponent("orbit_inmemory_\(UUID().uuidString).sqlite")) else {
            fatalError("Could not create any database, including fallback.")
        }
        return fallback
    }
}
