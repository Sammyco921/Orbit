import Foundation
import CoreGraphics
import CoreText

final class PDFGenerator {
    private let pageWidth: CGFloat = 612
    private let pageHeight: CGFloat = 792
    private let margin: CGFloat = 72
    private var yPosition: CGFloat = 0
    private var context: CGContext?
    private var pageNumber = 0

    private var contentWidth: CGFloat {
        pageWidth - margin * 2
    }

    private lazy var inlinePattern: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "(\\*\\*\\*|\\*\\*|\\*|`|__|___)(.+?)\\1")
    }()

    private lazy var numberedPattern: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "^\\s*(\\d+)\\.\\s+")
    }()

    func generate(title: String, content: String) async throws -> URL {
        let fm = FileManager.default
        let dir = fm.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/Orbit/Artifacts")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let filename = sanitizeFilename(from: title) + ".pdf"
        let outputURL = dir.appendingPathComponent(filename)

        let blocks = parseMarkdown(content)

        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let data = CFDataCreateMutable(nil, 0),
              let consumer = CGDataConsumer(data: data),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else {
            throw NSError(domain: "PDFGenerator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create PDF context"])
        }

        context = ctx
        pageNumber = 0
        beginPage(title: title)

        for block in blocks {
            renderBlock(block)
        }

        ctx.endPDFPage()
        ctx.closePDF()

        let pdfData = data as Data
        try pdfData.write(to: outputURL)

        return outputURL
    }

    // MARK: - Page Management

    private func beginPage(title: String) {
        guard let ctx = context else { return }
        pageNumber += 1
        ctx.beginPDFPage(nil)

        yPosition = pageHeight - margin

        ctx.setStrokeColor(CGColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1))
        ctx.setLineWidth(0.5)

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: CTFontCreateWithName("Helvetica" as CFString, 8, nil),
            .foregroundColor: CGColor(gray: 0.6, alpha: 1)
        ]
        let titleStr = "\(title) — Page \(pageNumber)"
        let titleAttr = NSAttributedString(string: titleStr, attributes: titleAttrs)
        let titleLine = CTLineCreateWithAttributedString(titleAttr)
        CTLineDraw(titleLine, ctx)
    }

    private func needNewPage(for height: CGFloat) -> Bool {
        yPosition - height < margin
    }

    private func checkPageBreak(_ blockHeight: CGFloat) {
        guard let ctx = context else { return }
        if needNewPage(for: blockHeight) {
            ctx.endPDFPage()
            beginPage(title: "")
        }
    }

    // MARK: - Rendering

    private func renderBlock(_ block: Block) {
        guard let ctx = context else { return }

        switch block {
        case .heading(let text, let level):
            let fontSize: CGFloat = level == 1 ? 22 : level == 2 ? 16 : 13
            let height = fontSize * 1.6
            checkPageBreak(height)
            drawText(text, fontSize: fontSize, bold: true, color: CGColor(gray: 0.15, alpha: 1))
            yPosition -= height

        case .paragraph(let text):
            let rendered = renderInline(text, fontSize: 11)
            let constraints = CGSize(width: contentWidth, height: .greatestFiniteMagnitude)
            let framesetter = CTFramesetterCreateWithAttributedString(rendered)
            let textHeight = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(), nil, constraints, nil).height
            checkPageBreak(textHeight + 4)
            let path = CGPath(rect: CGRect(x: margin, y: yPosition - textHeight, width: contentWidth, height: textHeight), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(), path, nil)
            CTFrameDraw(frame, ctx)
            yPosition -= (textHeight + 12)

        case .bullet(let text, let indent):
            let rendered = renderInline("•  \(text)", fontSize: 11)
            let leftMargin = margin + CGFloat(indent) * 20
            let constraints = CGSize(width: pageWidth - leftMargin - margin, height: .greatestFiniteMagnitude)
            let framesetter = CTFramesetterCreateWithAttributedString(rendered)
            let textHeight = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(), nil, constraints, nil).height
            checkPageBreak(textHeight + 4)
            let path = CGPath(rect: CGRect(x: leftMargin, y: yPosition - textHeight, width: pageWidth - leftMargin - margin, height: textHeight), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(), path, nil)
            CTFrameDraw(frame, ctx)
            yPosition -= (textHeight + 6)

        case .numbered(let index, let text, let indent):
            let rendered = renderInline("\(index).  \(text)", fontSize: 11)
            let leftMargin = margin + CGFloat(indent) * 20
            let constraints = CGSize(width: pageWidth - leftMargin - margin, height: .greatestFiniteMagnitude)
            let framesetter = CTFramesetterCreateWithAttributedString(rendered)
            let textHeight = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(), nil, constraints, nil).height
            checkPageBreak(textHeight + 4)
            let path = CGPath(rect: CGRect(x: leftMargin, y: yPosition - textHeight, width: pageWidth - leftMargin - margin, height: textHeight), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(), path, nil)
            CTFrameDraw(frame, ctx)
            yPosition -= (textHeight + 6)

        case .codeBlock(let text):
            let fontSize: CGFloat = 9
            let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
            let lineHeight = fontSize * 1.5
            let totalHeight = CGFloat(lines.count) * lineHeight + 16
            checkPageBreak(totalHeight)
            yPosition -= 8
            let blockRect = CGRect(x: margin, y: yPosition - totalHeight, width: contentWidth, height: totalHeight)
            ctx.setFillColor(CGColor(gray: 0.95, alpha: 1))
            ctx.fill(blockRect)
            ctx.setStrokeColor(CGColor(gray: 0.85, alpha: 1))
            ctx.setLineWidth(0.5)
            ctx.stroke(blockRect)

            let codeFont = CTFontCreateWithName("Menlo" as CFString, fontSize, nil)
            let codeAttrs: [NSAttributedString.Key: Any] = [
                .font: codeFont,
                .foregroundColor: CGColor(gray: 0.2, alpha: 1)
            ]
            for (i, line) in lines.enumerated() {
                let attrLine = NSAttributedString(string: line, attributes: codeAttrs)
                let ctLine = CTLineCreateWithAttributedString(attrLine)
                let lineY = yPosition - 12 - CGFloat(i) * lineHeight
                ctx.textPosition = CGPoint(x: margin + 8, y: lineY)
                CTLineDraw(ctLine, ctx)
            }
            yPosition -= (totalHeight + 12)

        case .divider:
            checkPageBreak(20)
            yPosition -= 10
            ctx.setStrokeColor(CGColor(gray: 0.85, alpha: 1))
            ctx.setLineWidth(0.5)
            ctx.move(to: CGPoint(x: margin, y: yPosition))
            ctx.addLine(to: CGPoint(x: pageWidth - margin, y: yPosition))
            ctx.strokePath()
            yPosition -= 10
        }
    }

    // MARK: - Inline Rendering

    private func renderInline(_ text: String, fontSize: CGFloat) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let bodyFont = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: CGColor(gray: 0.15, alpha: 1)
        ]

        guard let pattern = inlinePattern else { return NSAttributedString(string: text, attributes: bodyAttrs) }
        let fullRange = NSRange(text.startIndex..., in: text)
        var lastEnd = text.startIndex

        let matches = pattern.matches(in: text, range: fullRange)
        for match in matches {
            guard let matchRange = Range(match.range, in: text),
                  let delimRange = Range(match.range(at: 1), in: text),
                  let innerRange = Range(match.range(at: 2), in: text)
            else { continue }

            if lastEnd < matchRange.lowerBound {
                let plain = String(text[lastEnd..<matchRange.lowerBound])
                result.append(NSAttributedString(string: plain, attributes: bodyAttrs))
            }

            let delimiter = text[delimRange]
            let innerStr = String(text[innerRange])

            var attrs = bodyAttrs
            if delimiter == "**" || delimiter == "___" {
                let boldFont = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
                attrs[.font] = boldFont
            } else if delimiter == "*" || delimiter == "_" {
                let italicFont = CTFontCreateWithName("Helvetica-Oblique" as CFString, fontSize, nil)
                attrs[.font] = italicFont
            } else if delimiter == "***" || delimiter == "___" {
                let boldItalic = CTFontCreateWithName("Helvetica-BoldOblique" as CFString, fontSize, nil)
                attrs[.font] = boldItalic
            } else if delimiter == "`" {
                let codeFont = CTFontCreateWithName("Menlo" as CFString, fontSize, nil)
                attrs[.font] = codeFont
                attrs[.foregroundColor] = CGColor(srgbRed: 0.8, green: 0.2, blue: 0.2, alpha: 1)
            }

            result.append(NSAttributedString(string: innerStr, attributes: attrs))
            lastEnd = matchRange.upperBound
        }

        if lastEnd < text.endIndex {
            let remaining = String(text[lastEnd...])
            result.append(NSAttributedString(string: remaining, attributes: bodyAttrs))
        }

        if result.length == 0 {
            result.append(NSAttributedString(string: text, attributes: bodyAttrs))
        }

        return result
    }

    private func drawText(_ text: String, fontSize: CGFloat, bold: Bool, color: CGColor) {
        guard let ctx = context else { return }
        let fontName = bold ? "Helvetica-Bold" : "Helvetica"
        let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attrStr)
        ctx.textPosition = CGPoint(x: margin, y: yPosition - fontSize)
        CTLineDraw(line, ctx)
    }

    // MARK: - Markdown Parser

    private enum Block {
        case heading(String, level: Int)
        case paragraph(String)
        case bullet(String, indent: Int)
        case numbered(Int, String, indent: Int)
        case codeBlock(String)
        case divider
    }

    private func parseMarkdown(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var inCodeBlock = false
        var codeLines: [String] = []
        var inParagraph: [String] = []

        func flushParagraph() {
            guard !inParagraph.isEmpty else { return }
            let text = inParagraph.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !text.isEmpty {
                blocks.append(.paragraph(text))
            }
            inParagraph = []
        }

        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            if line.hasPrefix("```") {
                if inCodeBlock {
                    blocks.append(.codeBlock(codeLines.joined(separator: "\n")))
                    codeLines = []
                    inCodeBlock = false
                } else {
                    flushParagraph()
                    inCodeBlock = true
                }
                continue
            }

            if inCodeBlock {
                codeLines.append(line)
                continue
            }

            let trimmed = line.isEmpty ? "" : line

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            if trimmed.hasPrefix("---") || trimmed.hasPrefix("***") {
                flushParagraph()
                blocks.append(.divider)
                continue
            }

            if let headingLevel = headingMatch(trimmed) {
                flushParagraph()
                blocks.append(.heading(stripHeading(trimmed), level: headingLevel))
                continue
            }

            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                flushParagraph()
                let indent = countIndent(trimmed)
                let content = trimmed.replacingOccurrences(of: "^[\\s]*[-*]\\s+", with: "", options: .regularExpression)
                blocks.append(.bullet(content, indent: indent))
                continue
            }

            if let numMatch = numberedMatch(trimmed) {
                flushParagraph()
                let indent = countIndent(trimmed)
                let content = trimmed.replacingOccurrences(of: "^[\\s]*\\d+\\.\\s+", with: "", options: .regularExpression)
                blocks.append(.numbered(numMatch, content, indent: indent))
                continue
            }

            inParagraph.append(trimmed)
        }

        flushParagraph()

        if inCodeBlock && !codeLines.isEmpty {
            blocks.append(.codeBlock(codeLines.joined(separator: "\n")))
        }

        return blocks
    }

    private func headingMatch(_ line: String) -> Int? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }
        var count = 0
        for ch in trimmed {
            if ch == "#" { count += 1 } else { break }
        }
        guard count >= 1 && count <= 6 else { return nil }
        let after = trimmed[trimmed.index(trimmed.startIndex, offsetBy: count)...].trimmingCharacters(in: .whitespaces)
        return after.isEmpty ? nil : count
    }

    private func stripHeading(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let firstHash = trimmed.firstIndex(of: "#") else { return trimmed }
        let after = trimmed[trimmed.index(after: firstHash)...]
        guard let lastHash = after.lastIndex(of: "#") else { return after.trimmingCharacters(in: .whitespaces) }
        if lastHash == after.startIndex { return after.trimmingCharacters(in: .whitespaces) }
        return trimmed[trimmed.index(after: lastHash)...].trimmingCharacters(in: .whitespaces)
    }

    func numberedMatch(_ line: String) -> Int? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let pattern = numberedPattern else { return nil }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = pattern.firstMatch(in: trimmed, range: range),
              let numRange = Range(match.range(at: 1), in: trimmed)
        else { return nil }
        return Int(trimmed[numRange])
    }

    func countIndent(_ line: String) -> Int {
        var count = 0
        for ch in line {
            if ch == " " { count += 1 } else { break }
        }
        return count / 2
    }

    func sanitizeFilename(from description: String) -> String {
        let words = description.components(separatedBy: .whitespaces).prefix(5)
        let base = words.joined(separator: "_").lowercased()
        let allowed = CharacterSet.alphanumerics.union(["_", "-"])
        return String(base.unicodeScalars.filter { allowed.contains($0) })
    }
}
