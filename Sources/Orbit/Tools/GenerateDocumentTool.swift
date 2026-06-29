import Foundation

final class GenerateDocumentTool: Tool {
    var definition = ToolDefinition(
        id: "generateDocument",
        name: "Generate Document",
        description: "Create a .docx Word document with formatted content",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "title", description: "Document title", type: .string, required: true),
            ToolParameter(name: "content", description: "Document body content in markdown format", type: .string, required: true)
        ])
    )

    var documentService: DocumentService?

    func run(input: [String: String]) async throws -> String {
        guard let title = input["title"], !title.isEmpty else {
            return "No title provided."
        }
        guard let content = input["content"], !content.isEmpty else {
            return "No content provided."
        }
        guard let service = documentService else {
            return "Document service not available."
        }
        let url = try await service.generateDocument(title: title, content: content)
        return "Document created at: \(url.path)"
    }
}

final class GenerateSpreadsheetTool: Tool {
    var definition = ToolDefinition(
        id: "generateSpreadsheet",
        name: "Generate Spreadsheet",
        description: "Create an .xlsx spreadsheet with tabular data",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "title", description: "Spreadsheet title / filename", type: .string, required: true),
            ToolParameter(name: "csvContent", description: "CSV-formatted data for the spreadsheet", type: .string, required: true)
        ])
    )

    var documentService: DocumentService?

    func run(input: [String: String]) async throws -> String {
        guard let title = input["title"], !title.isEmpty else {
            return "No title provided."
        }
        guard let csvContent = input["csvContent"], !csvContent.isEmpty else {
            return "No CSV content provided."
        }
        guard let service = documentService else {
            return "Document service not available."
        }
        let url = try await service.generateSpreadsheet(title: title, csvContent: csvContent)
        return "Spreadsheet created at: \(url.path)"
    }
}

final class GeneratePDFTool: Tool {
    var definition = ToolDefinition(
        id: "generatePDF",
        name: "Generate PDF",
        description: "Create a PDF document with formatted content",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "title", description: "PDF document title", type: .string, required: true),
            ToolParameter(name: "content", description: "Document content in markdown format", type: .string, required: true)
        ])
    )

    var documentService: DocumentService?

    func run(input: [String: String]) async throws -> String {
        guard let title = input["title"], !title.isEmpty else {
            return "No title provided."
        }
        guard let content = input["content"], !content.isEmpty else {
            return "No content provided."
        }
        guard let service = documentService else {
            return "Document service not available."
        }
        let url = try await service.generatePDF(title: title, content: content)
        return "PDF created at: \(url.path)"
    }
}

final class GeneratePresentationTool: Tool {
    var definition = ToolDefinition(
        id: "generatePresentation",
        name: "Generate Presentation",
        description: "Create a .pptx PowerPoint presentation with slide content",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "title", description: "Presentation title / filename", type: .string, required: true),
            ToolParameter(name: "content", description: "Presentation content in markdown (--- separates slides)", type: .string, required: true)
        ])
    )

    var documentService: DocumentService?

    func run(input: [String: String]) async throws -> String {
        guard let title = input["title"], !title.isEmpty else {
            return "No title provided."
        }
        guard let content = input["content"], !content.isEmpty else {
            return "No content provided."
        }
        guard let service = documentService else {
            return "Document service not available."
        }
        let url = try await service.generatePresentation(title: title, content: content)
        return "Presentation created at: \(url.path)"
    }
}
