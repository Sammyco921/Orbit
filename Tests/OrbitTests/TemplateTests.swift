import XCTest
@testable import Orbit

final class TemplateTests: XCTestCase {
    private var db: OrbitDatabase!
    private var workflowStore: WorkflowStore!
    private var templateStore: TemplateStore!
    private var registry: TemplateRegistry!

    override func setUp() {
        super.setUp()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test_templates_\(UUID().uuidString).sqlite")
        db = try! OrbitDatabase(storageURL: url)
        workflowStore = WorkflowStore(db: db.db)
        templateStore = TemplateStore(db: db.db)
        registry = TemplateRegistry(store: templateStore, workflowStore: workflowStore)
        registry.registerBuiltIn(BuiltinTemplates.all)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: db.storageURL)
        db = nil
        workflowStore = nil
        templateStore = nil
        registry = nil
        super.tearDown()
    }

    // MARK: - Template Loading

    func testBuiltInTemplatesLoad() {
        let templates = registry.allTemplates()
        XCTAssertEqual(templates.count, 4, "Should have exactly 4 built-in templates")

        let ids = Set(templates.map(\.id))
        XCTAssertTrue(ids.contains("email-digest"))
        XCTAssertTrue(ids.contains("subscription-tracker"))
        XCTAssertTrue(ids.contains("invoice-finder"))
        XCTAssertTrue(ids.contains("github-backup"))
    }

    func testBuiltInTemplatesAreMarkedBuiltIn() {
        for template in registry.allTemplates() {
            XCTAssertTrue(template.isBuiltIn, "Built-in template '\(template.id)' should have isBuiltIn = true")
        }
    }

    func testTemplateLookupById() {
        let digest = registry.template(id: "email-digest")
        XCTAssertNotNil(digest)
        XCTAssertEqual(digest?.name, "Email Digest")
        XCTAssertEqual(digest?.category, .emailDigest)

        let missing = registry.template(id: "nonexistent")
        XCTAssertNil(missing)
    }

    func testTemplatesByCategory() {
        let emailDigests = registry.templates(category: .emailDigest)
        XCTAssertEqual(emailDigests.count, 1)
        XCTAssertEqual(emailDigests.first?.id, "email-digest")

        let custom = registry.templates(category: .custom)
        XCTAssertTrue(custom.isEmpty)
    }

    func testSearchTemplates() {
        let emailResults = registry.search("email")
        XCTAssertGreaterThanOrEqual(emailResults.count, 1)
        XCTAssertTrue(emailResults.contains { $0.id == "email-digest" })

        let financeResults = registry.search("invoice")
        XCTAssertGreaterThanOrEqual(financeResults.count, 1)
        XCTAssertTrue(financeResults.contains { $0.id == "invoice-finder" })

        let emptyResults = registry.search("zzzzznotfound")
        XCTAssertTrue(emptyResults.isEmpty)
    }

    // MARK: - Template Validation

    func testBuiltInTemplatesPassValidation() throws {
        for template in registry.allTemplates() {
            XCTAssertNoThrow(try template.validate(), "Template '\(template.id)' should pass validation")
        }
    }

    func testValidationFailsOnEmptyId() {
        let invalid = WorkflowTemplate(id: "", name: "Test", description: "", steps: [Step(name: "s1", toolName: "test")])
        XCTAssertThrowsError(try invalid.validate()) { error in
            XCTAssertTrue(error is TemplateValidationError)
        }
    }

    func testValidationFailsOnEmptyName() {
        let invalid = WorkflowTemplate(id: "test", name: "", description: "", steps: [Step(name: "s1", toolName: "test")])
        XCTAssertThrowsError(try invalid.validate()) { error in
            XCTAssertTrue(error is TemplateValidationError)
        }
    }

    func testValidationFailsOnEmptySteps() {
        let invalid = WorkflowTemplate(id: "test", name: "Test", description: "", steps: [])
        XCTAssertThrowsError(try invalid.validate()) { error in
            XCTAssertTrue(error is TemplateValidationError)
        }
    }

    func testValidationFailsOnDuplicateVariables() {
        let invalid = WorkflowTemplate(
            id: "test", name: "Test", description: "",
            variables: [
                TemplateVariable(name: "email", description: "Email", required: true),
                TemplateVariable(name: "email", description: "Duplicate", required: false),
            ],
            steps: [Step(name: "s1", toolName: "test")]
        )
        XCTAssertThrowsError(try invalid.validate()) { error in
            XCTAssertTrue(error is TemplateValidationError)
        }
    }

    // MARK: - Variable Substitution

    func testSubstituteVariables() {
        let template = WorkflowTemplate(
            id: "test", name: "Hello {{name}}",
            description: "For {{name}}",
            steps: [
                Step(name: "Step 1", toolName: "searchMail", input: ["query": "from:{{email}}"]),
                Step(name: "Step 2", toolName: "sendMail", input: ["to": "{{email}}", "subject": "Hi {{name}}"]),
            ],
            triggers: [
                WorkflowTrigger(type: .scheduled, schedule: "0 {{hour}} * * *"),
            ]
        )

        let values = ["name": "Alice", "email": "alice@example.com", "hour": "8"]
        let substituted = template.substituteVariables(values)

        XCTAssertEqual(substituted.name, "Hello Alice")
        XCTAssertEqual(substituted.description, "For Alice")
        XCTAssertEqual(substituted.steps[0].input["query"], "from:alice@example.com")
        XCTAssertEqual(substituted.steps[1].input["to"], "alice@example.com")
        XCTAssertEqual(substituted.steps[1].input["subject"], "Hi Alice")
        XCTAssertEqual(substituted.triggers[0].schedule, "0 8 * * *")
    }

    func testSubstituteVariablesDoesNotModifyOriginal() {
        let template = WorkflowTemplate(
            id: "test", name: "Hello {{name}}", description: "",
            steps: [Step(name: "s1", toolName: "test", input: ["key": "{{name}}"])]
        )
        _ = template.substituteVariables(["name": "Bob"])

        XCTAssertEqual(template.name, "Hello {{name}}")
        XCTAssertEqual(template.steps[0].input["key"], "{{name}}")
    }

    func testDetectUnresolvedVariables() {
        let template = WorkflowTemplate(
            id: "test", name: "{{name}}", description: "",
            variables: [
                TemplateVariable(name: "name", description: "Name", required: true),
                TemplateVariable(name: "email", description: "Email", required: false),
            ],
            steps: [
                Step(name: "s1", toolName: "test", input: ["to": "{{email}}", "from": "{{name}}"]),
            ]
        )

        let unresolved = template.detectUnresolvedVariables(in: ["name": "Alice"])
        XCTAssertEqual(unresolved, ["email"])
    }

    func testDetectNoUnresolvedVariables() {
        let template = WorkflowTemplate(
            id: "test", name: "{{name}}", description: "",
            steps: [Step(name: "s1", toolName: "test", input: ["v": "{{val}}"])]
        )
        let unresolved = template.detectUnresolvedVariables(in: ["name": "Alice", "val": "42"])
        XCTAssertTrue(unresolved.isEmpty)
    }

    // MARK: - Conversion to WorkflowDefinition

    func testToWorkflowDefinition() {
        let template = WorkflowTemplate(
            id: "test-template", name: "Test {{color}}", description: "A test template",
            variables: [
                TemplateVariable(name: "color", description: "Color", required: true),
            ],
            steps: [Step(name: "s1", toolName: "test", input: ["c": "{{color}}"])],
            triggers: [WorkflowTrigger(type: WorkflowTrigger.TriggerType.manual)],
            isBuiltIn: true
        )

        let wf = template.toWorkflowDefinition(variableValues: ["color": "blue"])

        XCTAssertNotEqual(wf.id, template.id)
        XCTAssertEqual(wf.name, "Test blue")
        XCTAssertEqual(wf.description, "A test template")
        XCTAssertEqual(wf.steps.count, 1)
        XCTAssertEqual(wf.steps[0].input["c"], "blue")
        XCTAssertEqual(wf.triggers.count, 1)
        XCTAssertEqual(wf.triggers[0].type, WorkflowTrigger.TriggerType.manual)
        XCTAssertEqual(wf.variables.count, 1)
        XCTAssertEqual(wf.variables[0].name, "color")
        XCTAssertEqual(wf.variables[0].defaultValue, "blue")
    }

    func testToWorkflowDefinitionPreservesTags() {
        let template = WorkflowTemplate(
            id: "test", name: "Test", description: "desc", tags: ["tag1", "tag2"],
            steps: [Step(name: "s1", toolName: "test")]
        )
        let wf = template.toWorkflowDefinition(variableValues: [:])
        XCTAssertEqual(wf.tags, "tag1,tag2")
    }

    // MARK: - Install & Uninstall

    func testInstallTemplate() throws {
        let result = try registry.install(templateId: "email-digest", variableValues: [
            "deliveryEmail": "test@example.com",
            "lookbackHours": "48",
            "maxResults": "10"
        ])

        XCTAssertEqual(result.template.id, "email-digest")
        XCTAssertEqual(result.workflow.name, "Email Digest")
        XCTAssertEqual(result.resolvedVariables["deliveryEmail"], "test@example.com")
        XCTAssertEqual(result.resolvedVariables["lookbackHours"], "48")

        // Verify it was saved to workflow store
        let saved = workflowStore.definition(id: result.workflow.id)
        XCTAssertNotNil(saved)
        XCTAssertEqual(saved?.name, "Email Digest")

        // Verify installation record was created
        let installed = templateStore.installedByTemplateId("email-digest")
        XCTAssertEqual(installed.count, 1)
        XCTAssertEqual(installed.first?.workflowId, result.workflow.id)
    }

    func testInstallTemplateFailsOnMissingRequiredVariables() {
        XCTAssertThrowsError(try registry.install(templateId: "email-digest", variableValues: [:])) { error in
            XCTAssertTrue(error is TemplateError)
        }
    }

    func testInstallTemplateFailsOnNonexistentTemplate() {
        XCTAssertThrowsError(try registry.install(templateId: "nonexistent", variableValues: ["a": "b"])) { error in
            guard case TemplateError.notFound(let id) = error else {
                return XCTFail("Expected notFound error, got \(error)")
            }
            XCTAssertEqual(id, "nonexistent")
        }
    }

    func testUninstallByWorkflowId() throws {
        let result = try registry.install(templateId: "email-digest", variableValues: [
            "deliveryEmail": "test@example.com"
        ])

        let success = registry.uninstall(workflowId: result.workflow.id)
        XCTAssertTrue(success)

        // Verify workflow is deleted
        XCTAssertNil(workflowStore.definition(id: result.workflow.id))

        // Verify installation record is deleted
        XCTAssertNil(templateStore.installedByWorkflowId(result.workflow.id))
    }

    func testUninstallByTemplateId() throws {
        try registry.install(templateId: "email-digest", variableValues: ["deliveryEmail": "a@b.com"])
        try registry.install(templateId: "email-digest", variableValues: ["deliveryEmail": "c@d.com"])

        let wfIds = registry.uninstallByTemplateId("email-digest")
        XCTAssertEqual(wfIds.count, 2)

        for wfId in wfIds {
            XCTAssertNil(workflowStore.definition(id: wfId))
        }
        XCTAssertTrue(templateStore.installedByTemplateId("email-digest").isEmpty)
    }

    func testUninstallNonexistentWorkflow() {
        let result = registry.uninstall(workflowId: "nonexistent")
        XCTAssertFalse(result)
    }

    // MARK: - List Installed

    func testListInstalled() throws {
        let result1 = try registry.install(templateId: "email-digest", variableValues: [
            "deliveryEmail": "a@b.com"
        ])
        let result2 = try registry.install(templateId: "invoice-finder", variableValues: [
            "reportEmail": "c@d.com",
            "searchMonths": "6"
        ])

        let installed = registry.listInstalled()
        XCTAssertEqual(installed.count, 2)

        let templateIds = Set(installed.map(\.template.id))
        XCTAssertTrue(templateIds.contains("email-digest"))
        XCTAssertTrue(templateIds.contains("invoice-finder"))

        let workflowIds = Set(installed.map(\.record.workflowId))
        XCTAssertTrue(workflowIds.contains(result1.workflow.id))
        XCTAssertTrue(workflowIds.contains(result2.workflow.id))
    }

    func testListInstalledWhenEmpty() {
        let installed = registry.listInstalled()
        XCTAssertTrue(installed.isEmpty)
    }

    // MARK: - Export

    func testExportTemplate() throws {
        let json = try registry.export(templateId: "email-digest")
        XCTAssertFalse(json.isEmpty)

        let payload = TemplateExportPayload.decode(from: json)
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.template.id, "email-digest")
        XCTAssertEqual(payload?.template.name, "Email Digest")
        XCTAssertEqual(payload?.template.isBuiltIn, true)
    }

    func testExportNonexistentTemplate() {
        XCTAssertThrowsError(try registry.export(templateId: "nonexistent")) { error in
            guard case TemplateError.notFound = error else {
                return XCTFail("Expected notFound error")
            }
        }
    }

    // MARK: - Import

    func testImportTemplate() throws {
        let json = try registry.export(templateId: "email-digest")
        let imported = try registry.import(from: json)

        XCTAssertFalse(imported.id.isEmpty)
        XCTAssertTrue(imported.id.hasPrefix("imported_email-digest_"))
        XCTAssertEqual(imported.name, "Email Digest")
        XCTAssertFalse(imported.isBuiltIn)
        XCTAssertEqual(imported.steps.count, BuiltinTemplates.emailDigest.steps.count)

        // Should be available in the registry
        let found = registry.template(id: imported.id)
        XCTAssertNotNil(found)
    }

    func testImportAndInstallRoundTrip() throws {
        let json = try registry.export(templateId: "email-digest")
        let imported = try registry.import(from: json)

        let result = try registry.install(templateId: imported.id, variableValues: [
            "deliveryEmail": "test@roundtrip.com",
            "lookbackHours": "24",
            "maxResults": "5"
        ])

        XCTAssertEqual(result.workflow.name, "Email Digest")
        XCTAssertEqual(result.resolvedVariables["deliveryEmail"], "test@roundtrip.com")
    }

    func testImportInvalidJSON() {
        XCTAssertThrowsError(try registry.import(from: "not valid json")) { error in
            guard case TemplateError.importFailed = error else {
                return XCTFail("Expected importFailed error")
            }
        }
    }

    // MARK: - Template Encoding/Decoding

    func testTemplateExportPayloadEncodeDecode() {
        let payload = TemplateExportPayload(
            template: BuiltinTemplates.emailDigest,
            exportedAt: Date(timeIntervalSince1970: 1000),
            orbitVersion: "test"
        )

        guard let json = TemplateExportPayload.encode(payload) else {
            return XCTFail("Failed to encode")
        }

        let decoded = TemplateExportPayload.decode(from: json)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.template.id, "email-digest")
        XCTAssertEqual(decoded?.template.name, "Email Digest")
        XCTAssertEqual(decoded?.orbitVersion, "test")
        XCTAssertEqual(decoded?.exportedAt.timeIntervalSince1970 ?? 0, 1000, accuracy: 0.001)
    }

    // MARK: - Template Tools

    func testTemplateListTool() async throws {
        let tool = TemplateListTool(registry: registry)
        let output = try await tool.run(input: [:])
        XCTAssertTrue(output.contains("Email Digest"))
        XCTAssertTrue(output.contains("Subscription Tracker"))
        XCTAssertTrue(output.contains("Invoice Finder"))
        XCTAssertTrue(output.contains("GitHub Backup"))
        XCTAssertTrue(output.contains("[Built-in]"))
    }

    func testTemplateListToolWithCategoryFilter() async throws {
        let tool = TemplateListTool(registry: registry)
        let output = try await tool.run(input: ["category": "email_digest"])
        XCTAssertTrue(output.contains("Email Digest"))
        XCTAssertFalse(output.contains("Invoice Finder"))
    }

    func testTemplateListToolWithSearch() async throws {
        let tool = TemplateListTool(registry: registry)
        let output = try await tool.run(input: ["search": "invoice"])
        XCTAssertTrue(output.contains("Invoice Finder"))
        XCTAssertFalse(output.contains("Email Digest"))
    }

    func testTemplateInstallTool() async throws {
        let tool = TemplateInstallTool(registry: registry)
        let varsJSON = #"{"deliveryEmail":"tool@test.com","lookbackHours":"24","maxResults":"5"}"#
        let output = try await tool.run(input: ["templateId": "email-digest", "variables": varsJSON])

        XCTAssertTrue(output.contains("installed successfully"))
        XCTAssertTrue(output.contains("Email Digest"))
        XCTAssertTrue(output.contains("Workflow ID:"))
    }

    func testTemplateInstallToolMissingTemplateId() async throws {
        let tool = TemplateInstallTool(registry: registry)
        let output = try await tool.run(input: ["variables": "{}"])
        XCTAssertEqual(output, "No templateId specified.")
    }

    func testTemplateInstallToolInvalidVariablesJSON() async throws {
        let tool = TemplateInstallTool(registry: registry)
        let output = try await tool.run(input: ["templateId": "email-digest", "variables": "not-json"])
        XCTAssertTrue(output.contains("Invalid variables JSON"))
    }

    func testTemplateInstallToolMissingVariables() async throws {
        let tool = TemplateInstallTool(registry: registry)
        let output = try await tool.run(input: ["templateId": "email-digest", "variables": "{}"])
        // Should provide helpful message about required variables
        XCTAssertTrue(output.contains("Missing values") || output.contains("deliveryEmail"))
    }

    func testTemplateDeleteToolByWorkflowId() async throws {
        let result = try registry.install(templateId: "email-digest", variableValues: [
            "deliveryEmail": "del@test.com"
        ])

        let tool = TemplateDeleteTool(registry: registry)
        let output = try await tool.run(input: ["workflowId": result.workflow.id])
        XCTAssertTrue(output.contains("uninstalled"))
    }

    func testTemplateDeleteToolByTemplateId() async throws {
        try registry.install(templateId: "email-digest", variableValues: ["deliveryEmail": "a@b.com"])

        let tool = TemplateDeleteTool(registry: registry)
        let output = try await tool.run(input: ["templateId": "email-digest"])
        XCTAssertTrue(output.contains("Uninstalled"))
    }

    func testTemplateDeleteToolNoArgs() async throws {
        let tool = TemplateDeleteTool(registry: registry)
        let output = try await tool.run(input: [:])
        XCTAssertTrue(output.contains("Specify either"))
    }

    func testTemplateExportTool() async throws {
        let tool = TemplateExportTool(registry: registry)
        let output = try await tool.run(input: ["templateId": "email-digest"])

        // Output should be valid JSON
        let payload = TemplateExportPayload.decode(from: output)
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.template.id, "email-digest")
    }

    func testTemplateExportToolNonexistent() async throws {
        let tool = TemplateExportTool(registry: registry)
        let output = try await tool.run(input: ["templateId": "nonexistent"])
        XCTAssertTrue(output.contains("not found"))
    }

    func testTemplateImportTool() async throws {
        let json = try registry.export(templateId: "email-digest")

        let tool = TemplateImportTool(registry: registry)
        let output = try await tool.run(input: ["json": json])
        XCTAssertTrue(output.contains("imported successfully"))
        XCTAssertTrue(output.contains("Email Digest"))
    }

    func testTemplateImportToolInvalidJSON() async throws {
        let tool = TemplateImportTool(registry: registry)
        let output = try await tool.run(input: ["json": "not-valid-json"])
        XCTAssertTrue(output.contains("Import failed"))
    }

    // MARK: - Template Variable Prompts

    func testVariablePrompt() {
        let requiredVar = TemplateVariable(name: "email", description: "Email address", required: true)
        let prompt = WorkflowTemplate.variablePrompt(requiredVar)
        XCTAssertTrue(prompt.contains("Email address"))
        XCTAssertTrue(prompt.contains("(required)"))

        let optionalVar = TemplateVariable(name: "count", description: "Count", required: false, defaultValue: "10")
        let optPrompt = WorkflowTemplate.variablePrompt(optionalVar)
        XCTAssertTrue(optPrompt.contains("Count"))
        XCTAssertTrue(optPrompt.contains("(optional)"))
        XCTAssertTrue(optPrompt.contains("default: 10"))
    }
}
