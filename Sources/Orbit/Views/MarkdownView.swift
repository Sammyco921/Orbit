import SwiftUI

struct MarkdownView: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(blocks.indices, id: \.self) { i in
                blockView(blocks[i])
            }
        }
    }

    private var blocks: [Block] {
        parseBlocks(content)
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .heading1(let text):
            Text(text).font(.largeTitle).fontWeight(.bold).padding(.top, 4)
        case .heading2(let text):
            Text(text).font(.title2).fontWeight(.bold).padding(.top, 4)
        case .heading3(let text):
            Text(text).font(.title3).fontWeight(.semibold).padding(.top, 2)
        case .code(let text):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
        case .bullet(let items, let checked):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items.indices, id: \.self) { i in
                    HStack(alignment: .top, spacing: 6) {
                        if let checked {
                            Image(systemName: checked[i] ? "checkmark.square.fill" : "square")
                                .foregroundColor(checked[i] ? .accentColor : .secondary)
                                .font(.subheadline)
                        } else {
                            Text("\u{2022}").font(.subheadline)
                        }
                        inlineText(items[i])
                    }
                }
            }
        case .numbered(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items.indices, id: \.self) { i in
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(i + 1).").font(.subheadline)
                        inlineText(items[i])
                    }
                }
            }
        case .paragraph(let text):
            if text.trimmingCharacters(in: .whitespaces).isEmpty {
                Spacer().frame(height: 4)
            } else {
                inlineText(text)
            }
        case .quote(let text):
            HStack {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 3)
                    .cornerRadius(1.5)
                inlineText(text)
                    .foregroundColor(.secondary)
                    .italic()
            }
            .padding(.leading, 4)
        case .table(let headers, let rows):
            VStack(alignment: .leading, spacing: 0) {
                Grid(horizontalSpacing: 8, verticalSpacing: 4) {
                    GridRow {
                        ForEach(headers, id: \.self) { header in
                            Text(header)
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color(nsColor: .separatorColor).opacity(0.15))

                    Divider()

                    ForEach(rows.indices, id: \.self) { rowIndex in
                        GridRow {
                            ForEach(rows[rowIndex].indices, id: \.self) { colIndex in
                                inlineText(rows[rowIndex][colIndex])
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.vertical, 3)
                        .padding(.horizontal, 8)
                        if rowIndex < rows.count - 1 {
                            Divider()
                        }
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
        case .ruler:
            Divider()
                .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func inlineText(_ text: String) -> some View {
        if let attributed = try? AttributedString(markdown: text) {
            Text(attributed)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Block Parsing

private enum Block {
    case heading1(String)
    case heading2(String)
    case heading3(String)
    case code(String)
    case bullet([String], checked: [Bool]?)
    case numbered([String])
    case paragraph(String)
    case quote(String)
    case table(headers: [String], rows: [[String]])
    case ruler
}

private func parseBlocks(_ text: String) -> [Block] {
    let lines = text.components(separatedBy: .newlines)
    var blocks: [Block] = []
    var i = 0

    while i < lines.count {
        let line = lines[i]

        if line.hasPrefix("```") {
            var codeLines: [String] = []
            i += 1
            while i < lines.count && !lines[i].hasPrefix("```") {
                codeLines.append(lines[i])
                i += 1
            }
            i += 1
            let code = codeLines.joined(separator: "\n")
            if !code.isEmpty {
                blocks.append(.code(code))
            }
            continue
        }

        if line.hasPrefix("### ") {
            blocks.append(.heading3(String(line.dropFirst(4))))
            i += 1
            continue
        }
        if line.hasPrefix("## ") {
            blocks.append(.heading2(String(line.dropFirst(3))))
            i += 1
            continue
        }
        if line.hasPrefix("# ") {
            blocks.append(.heading1(String(line.dropFirst(2))))
            i += 1
            continue
        }

        if line.hasPrefix("---") || line.hasPrefix("***") || line.hasPrefix("___") {
            blocks.append(.ruler)
            i += 1
            continue
        }

        if line.hasPrefix("> ") {
            var quoteLines: [String] = []
            while i < lines.count {
                let l = lines[i]
                if l.hasPrefix("> ") {
                    quoteLines.append(String(l.dropFirst(2)))
                } else if l == ">" {
                    quoteLines.append("")
                } else {
                    break
                }
                i += 1
            }
            blocks.append(.quote(quoteLines.joined(separator: "\n")))
            continue
        }

        if line.hasPrefix("|") {
            var tableLines: [String] = []
            while i < lines.count && lines[i].hasPrefix("|") {
                tableLines.append(lines[i])
                i += 1
            }
            if tableLines.count >= 2 {
                let parsed = parseTable(tableLines)
                if let (headers, rows) = parsed {
                    blocks.append(.table(headers: headers, rows: rows))
                    continue
                }
            }
            for tLine in tableLines {
                let cell = tLine.trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                    .trimmingCharacters(in: .whitespaces)
                if !cell.isEmpty {
                    blocks.append(.paragraph(tLine))
                }
            }
            continue
        }

        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            var items: [String] = []
            var checked: [Bool]?
            while i < lines.count {
                let l = lines[i]
                if l.hasPrefix("- [ ] ") {
                    items.append(String(l.dropFirst(6)))
                    if checked == nil { checked = [] }
                    checked?.append(false)
                } else if l.hasPrefix("- [x] ") || l.hasPrefix("- [X] ") {
                    items.append(String(l.dropFirst(6)))
                    if checked == nil { checked = [] }
                    checked?.append(true)
                } else if l.hasPrefix("- ") {
                    items.append(String(l.dropFirst(2)))
                } else if l.hasPrefix("* ") {
                    items.append(String(l.dropFirst(2)))
                } else if l.trimmingCharacters(in: .whitespaces).isEmpty {
                    i += 1
                    break
                } else {
                    break
                }
                i += 1
            }
            blocks.append(.bullet(items, checked: checked))
            continue
        }

        if line.first?.isNumber == true && line.contains(". ") {
            var items: [String] = []
            while i < lines.count {
                let l = lines[i]
                if let dotIndex = l.firstIndex(of: "."),
                   l[..<dotIndex].trimmingCharacters(in: .whitespaces).allSatisfy(\.isNumber),
                   l[l.index(after: dotIndex)] == " " {
                    items.append(String(l[l.index(after: dotIndex)...]).trimmingCharacters(in: .whitespaces))
                } else if l.trimmingCharacters(in: .whitespaces).isEmpty {
                    i += 1
                    break
                } else {
                    break
                }
                i += 1
            }
            blocks.append(.numbered(items))
            continue
        }

        var paraLines: [String] = []
        while i < lines.count {
            let l = lines[i]
            if l.trimmingCharacters(in: .whitespaces).isEmpty && !paraLines.isEmpty {
                i += 1
                break
            }
            if l.hasPrefix("```") || l.hasPrefix("#") || l.hasPrefix("---") || l.hasPrefix("***") || l.hasPrefix("___") { break }
            if l.hasPrefix("> ") || l == ">" { break }
            if l.hasPrefix("|") { break }
            if l.hasPrefix("- ") || l.hasPrefix("* ") { break }
            if l.first?.isNumber == true, let dotIndex = l.firstIndex(of: "."), l[l.index(after: dotIndex)...].first == " " {
                let prefix = l[..<dotIndex]
                if prefix.allSatisfy(\.isNumber) { break }
            }
            paraLines.append(l)
            i += 1
        }
        if !paraLines.isEmpty {
            blocks.append(.paragraph(paraLines.joined(separator: "\n")))
        } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
            blocks.append(.paragraph(line))
            i += 1
        } else {
            i += 1
        }
    }

    return blocks
}

private func parseTable(_ lines: [String]) -> (headers: [String], rows: [[String]])? {
    guard lines.count >= 2 else { return nil }

    let headers = parseTableRow(lines[0])
    let separatorLine = lines[1]

    guard separatorLine.allSatisfy({ $0 == "|" || $0 == "-" || $0 == ":" || $0 == " " }) else {
        return nil
    }

    var rows: [[String]] = []
    for i in 2..<lines.count {
        let row = parseTableRow(lines[i])
        if !row.isEmpty {
            rows.append(row)
        }
    }

    return (headers, rows)
}

private func parseTableRow(_ line: String) -> [String] {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix("|") else { return [] }
    var cells: [String] = []
    var current = ""
    var inCell = false
    for ch in trimmed.dropFirst() {
        if ch == "|" {
            cells.append(current.trimmingCharacters(in: .whitespaces))
            current = ""
            inCell = false
        } else {
            current.append(ch)
            inCell = true
        }
    }
    if inCell {
        cells.append(current.trimmingCharacters(in: .whitespaces))
    }
    return cells
}
