import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "documents")

protocol DocumentServiceProtocol {
    func generateDocument(title: String, content: String) async throws -> URL
    func generateSpreadsheet(title: String, csvContent: String) async throws -> URL
    func generatePDF(title: String, content: String) async throws -> URL
    func generateProjectFolder(title: String, content: String) async throws -> URL
    func generatePresentation(title: String, content: String) async throws -> URL
    func saveToDisk(filename: String, content: String) throws -> URL
}

final class DocumentService: DocumentServiceProtocol {
    private let documentGenerator = DocumentGenerator()
    private let spreadsheetGenerator = SpreadsheetGenerator()
    private let pdfGenerator = PDFGenerator()
    private let projectGenerator = ProjectGenerator()
    private let presentationGenerator = PresentationGenerator()
    private let artifactGenerator = ArtifactGenerator()

    func generateDocument(title: String, content: String) async throws -> URL {
        try await documentGenerator.generate(title: title, content: content)
    }

    func generateSpreadsheet(title: String, csvContent: String) async throws -> URL {
        try await spreadsheetGenerator.generate(title: title, csvContent: csvContent)
    }

    func generatePDF(title: String, content: String) async throws -> URL {
        try await pdfGenerator.generate(title: title, content: content)
    }

    func generateProjectFolder(title: String, content: String) async throws -> URL {
        try await projectGenerator.generate(title: title, content: content)
    }

    func generatePresentation(title: String, content: String) async throws -> URL {
        try await presentationGenerator.generate(title: title, content: content)
    }

    func saveToDisk(filename: String, content: String) throws -> URL {
        try artifactGenerator.saveToDisk(filename: filename, content: content)
    }
}
