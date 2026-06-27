import Testing
@testable import Orbit

struct PDFGeneratorTests {

    @Test func sanitizeFilenameTrimsToFiveWords() {
        let gen = PDFGenerator()
        let result = gen.sanitizeFilename(from: "How to build a great application in Swift")
        let parts = result.split(separator: "_")
        #expect(parts.count == 5)
    }

    @Test func sanitizeFilenameRemovesSpecialChars() {
        let gen = PDFGenerator()
        let result = gen.sanitizeFilename(from: "Hello! @World #2024")
        #expect(!result.contains("!"))
        #expect(!result.contains("@"))
        #expect(!result.contains("#"))
    }

    @Test func sanitizeFilenameLowercases() {
        let gen = PDFGenerator()
        let result = gen.sanitizeFilename(from: "Hello World")
        #expect(result == result.lowercased())
    }

    @Test func sanitizeFilenameAllowsHyphens() {
        let gen = PDFGenerator()
        let result = gen.sanitizeFilename(from: "swift-ui-guide")
        #expect(result.contains("-"))
    }

    @Test func numberedMatchDetectsNumberedLines() {
        let gen = PDFGenerator()
        #expect(gen.numberedMatch("1. First item") == 1)
        #expect(gen.numberedMatch("  2. Second item") == 2)
        #expect(gen.numberedMatch("10. Tenth item") == 10)
    }

    @Test func numberedMatchReturnsNilForNonNumberedLines() {
        let gen = PDFGenerator()
        #expect(gen.numberedMatch("Plain text") == nil)
        #expect(gen.numberedMatch("- bullet") == nil)
        #expect(gen.numberedMatch("") == nil)
    }

    @Test func countIndentCountsTwoSpaceUnits() {
        let gen = PDFGenerator()
        #expect(gen.countIndent("") == 0)
        #expect(gen.countIndent("text") == 0)
        #expect(gen.countIndent("  text") == 1)
        #expect(gen.countIndent("    text") == 2)
    }
}
