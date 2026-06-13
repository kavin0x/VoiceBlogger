import Foundation

struct MarkdownProcessor {
    struct ListItem: Equatable {
        var marker: String
        var text: String
        var children: [Block]
    }

    struct Table: Equatable {
        struct Column: Equatable {
            enum Alignment: Equatable {
                case leading
                case center
                case trailing
            }

            var title: String
            var alignment: Alignment
        }

        var columns: [Column]
        var rows: [[String]]
    }

    enum Block: Equatable {
        case heading(level: Int, text: String)
        case paragraph(String)
        case unorderedList([ListItem])
        case orderedList(start: Int, items: [ListItem])
        case codeBlock(language: String?, code: String)
        case blockquote([Block])
        case table(Table)
        case divider
    }

    static func parse(_ markdown: String) -> [Block] {
        var parser = Parser(markdown: markdown)
        return parser.parseBlocks()
    }
}

private struct Parser {
    private let lines: [String]
    private var index = 0

    init(markdown: String) {
        self.lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    mutating func parseBlocks(until shouldStop: ((String) -> Bool)? = nil) -> [MarkdownProcessor.Block] {
        var blocks: [MarkdownProcessor.Block] = []

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let shouldStop, shouldStop(line) {
                break
            }

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if let fence = fenceStart(in: trimmed) {
                blocks.append(parseFencedCodeBlock(openingFence: fence))
            } else if let heading = atxHeading(in: trimmed) {
                blocks.append(heading)
                index += 1
            } else if isThematicBreak(trimmed) {
                blocks.append(.divider)
                index += 1
            } else if isBlockquote(line) {
                blocks.append(parseBlockquote())
            } else if tableCanStart(at: index) {
                blocks.append(parseTable())
            } else if indentedCodeLine(line) {
                blocks.append(parseIndentedCodeBlock())
            } else if let unordered = unorderedListMarker(in: line) {
                blocks.append(parseList(markerKind: .unordered(unordered.marker), baseIndent: unordered.indent))
            } else if let ordered = orderedListMarker(in: line) {
                blocks.append(parseList(markerKind: .ordered(start: ordered.number, delimiter: ordered.delimiter), baseIndent: ordered.indent))
            } else {
                blocks.append(parseParagraph())
            }
        }

        return blocks
    }

    private enum ListMarkerKind {
        case unordered(String)
        case ordered(start: Int, delimiter: Character)
    }

    private mutating func parseParagraph() -> MarkdownProcessor.Block {
        var paragraphLines: [String] = []

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty || isBlockStart(line) {
                break
            }

            if paragraphLines.count == 1, let setext = setextHeadingLevel(for: trimmed) {
                let text = paragraphLines[0].trimmingCharacters(in: .whitespacesAndNewlines)
                index += 1
                return .heading(level: setext, text: text)
            }

            paragraphLines.append(trimmed)
            index += 1
        }

        return .paragraph(paragraphLines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private mutating func parseFencedCodeBlock(openingFence: Fence) -> MarkdownProcessor.Block {
        index += 1
        var codeLines: [String] = []

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if closesFence(trimmed, openingFence: openingFence) {
                index += 1
                return .codeBlock(language: openingFence.language, code: codeLines.joined(separator: "\n"))
            }
            codeLines.append(line)
            index += 1
        }

        return .codeBlock(language: openingFence.language, code: codeLines.joined(separator: "\n"))
    }

    private mutating func parseIndentedCodeBlock() -> MarkdownProcessor.Block {
        var codeLines: [String] = []

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                codeLines.append("")
                index += 1
            } else if indentedCodeLine(line) {
                codeLines.append(removeIndent(from: line, count: 4))
                index += 1
            } else {
                break
            }
        }

        while codeLines.last?.isEmpty == true {
            codeLines.removeLast()
        }

        return .codeBlock(language: nil, code: codeLines.joined(separator: "\n"))
    }

    private mutating func parseBlockquote() -> MarkdownProcessor.Block {
        var quotedLines: [String] = []

        while index < lines.count {
            let line = lines[index]
            if let content = blockquoteContent(from: line) {
                quotedLines.append(content)
                index += 1
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                quotedLines.append("")
                index += 1
            } else {
                break
            }
        }

        return .blockquote(MarkdownProcessor.parse(quotedLines.joined(separator: "\n")))
    }

    private mutating func parseTable() -> MarkdownProcessor.Block {
        let header = tableCells(in: lines[index])
        let alignments = tableAlignments(in: lines[index + 1])
        index += 2

        var rows: [[String]] = []
        while index < lines.count, lines[index].contains("|"), !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
            let row = normalizedTableCells(tableCells(in: lines[index]), count: header.count)
            rows.append(row)
            index += 1
        }

        let columns = zip(header, alignments).map { title, alignment in
            MarkdownProcessor.Table.Column(title: title, alignment: alignment)
        }
        return .table(.init(columns: columns, rows: rows))
    }

    private mutating func parseList(markerKind: ListMarkerKind, baseIndent: Int) -> MarkdownProcessor.Block {
        var items: [MarkdownProcessor.ListItem] = []
        let startNumber: Int

        switch markerKind {
        case .unordered:
            startNumber = 1
        case .ordered(let start, _):
            startNumber = start
        }

        while index < lines.count {
            let line = lines[index]
            let marker: String
            let content: String
            let itemIndent: Int

            switch markerKind {
            case .unordered:
                guard let parsed = unorderedListMarker(in: line), parsed.indent == baseIndent else {
                    return listBlock(markerKind: markerKind, start: startNumber, items: items)
                }
                marker = parsed.marker
                content = parsed.content
                itemIndent = parsed.contentIndent
            case .ordered:
                guard let parsed = orderedListMarker(in: line), parsed.indent == baseIndent else {
                    return listBlock(markerKind: markerKind, start: startNumber, items: items)
                }
                marker = "\(parsed.number)\(parsed.delimiter)"
                content = parsed.content
                itemIndent = parsed.contentIndent
            }

            index += 1
            var childLines: [String] = []

            while index < lines.count {
                let next = lines[index]
                let trimmed = next.trimmingCharacters(in: .whitespaces)

                if trimmed.isEmpty {
                    childLines.append("")
                    index += 1
                    continue
                }

                let nextIndent = indentationCount(in: next)
                if nextIndent <= baseIndent && startsAnyListItem(next) {
                    break
                }
                if nextIndent <= baseIndent && isBlockStart(next) {
                    break
                }
                if nextIndent <= baseIndent && !startsAnyListItem(next) {
                    break
                }

                childLines.append(removeIndent(from: next, count: min(itemIndent, nextIndent)))
                index += 1
            }

            var children: [MarkdownProcessor.Block] = []
            let continuation = childLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !continuation.isEmpty {
                children = MarkdownProcessor.parse(continuation)
            }
            items.append(.init(marker: marker, text: content, children: children))
        }

        return listBlock(markerKind: markerKind, start: startNumber, items: items)
    }

    private func listBlock(markerKind: ListMarkerKind, start: Int, items: [MarkdownProcessor.ListItem]) -> MarkdownProcessor.Block {
        switch markerKind {
        case .unordered:
            return .unorderedList(items)
        case .ordered:
            return .orderedList(start: start, items: items)
        }
    }

    private func isBlockStart(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return fenceStart(in: trimmed) != nil
            || atxHeading(in: trimmed) != nil
            || isThematicBreak(trimmed)
            || isBlockquote(line)
            || tableCanStart(at: index)
            || startsAnyListItem(line)
            || indentedCodeLine(line)
    }

    private func startsAnyListItem(_ line: String) -> Bool {
        unorderedListMarker(in: line) != nil || orderedListMarker(in: line) != nil
    }

    private func atxHeading(in trimmed: String) -> MarkdownProcessor.Block? {
        let hashes = trimmed.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let afterHashes = trimmed.dropFirst(hashes)
        guard afterHashes.isEmpty || afterHashes.first == " " || afterHashes.first == "\t" else { return nil }

        let rawText = afterHashes.trimmingCharacters(in: .whitespaces)
        let text = rawText.replacingOccurrences(of: #"\s+#+\s*$"#, with: "", options: .regularExpression)
        return .heading(level: hashes, text: text)
    }

    private func setextHeadingLevel(for trimmed: String) -> Int? {
        if trimmed.allSatisfy({ $0 == "=" || $0 == " " || $0 == "\t" }), trimmed.contains("=") {
            return 1
        }
        if trimmed.allSatisfy({ $0 == "-" || $0 == " " || $0 == "\t" }), trimmed.contains("-") {
            return 2
        }
        return nil
    }

    private func isThematicBreak(_ trimmed: String) -> Bool {
        let compact = trimmed.filter { !$0.isWhitespace }
        guard compact.count >= 3, let first = compact.first, ["-", "*", "_"].contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private struct Fence {
        var character: Character
        var length: Int
        var language: String?
    }

    private func fenceStart(in trimmed: String) -> Fence? {
        guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
        let length = trimmed.prefix { $0 == first }.count
        guard length >= 3 else { return nil }
        let info = trimmed.dropFirst(length).trimmingCharacters(in: .whitespaces)
        return Fence(character: first, length: length, language: info.isEmpty ? nil : info)
    }

    private func closesFence(_ trimmed: String, openingFence: Fence) -> Bool {
        let length = trimmed.prefix { $0 == openingFence.character }.count
        guard length >= openingFence.length else { return false }
        return trimmed.dropFirst(length).trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func isBlockquote(_ line: String) -> Bool {
        blockquoteContent(from: line) != nil
    }

    private func blockquoteContent(from line: String) -> String? {
        let trimmedLeading = line.trimmingCharacters(in: .whitespaces)
        guard trimmedLeading.first == ">" else { return nil }
        var content = String(trimmedLeading.dropFirst())
        if content.first == " " { content.removeFirst() }
        return content
    }

    private func tableCanStart(at lineIndex: Int) -> Bool {
        guard lineIndex + 1 < lines.count else { return false }
        let header = lines[lineIndex]
        let delimiter = lines[lineIndex + 1]
        guard header.contains("|"), delimiter.contains("|") else { return false }
        let headerCells = tableCells(in: header)
        let alignments = tableAlignments(in: delimiter)
        return !headerCells.isEmpty && headerCells.count == alignments.count
    }

    private func tableCells(in line: String) -> [String] {
        var raw = line.trimmingCharacters(in: .whitespaces)
        if raw.first == "|" { raw.removeFirst() }
        if raw.last == "|" { raw.removeLast() }
        return raw.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func tableAlignments(in line: String) -> [MarkdownProcessor.Table.Column.Alignment] {
        tableCells(in: line).compactMap { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            let core = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            guard core.count >= 3, core.allSatisfy({ $0 == "-" }) else { return nil }

            if trimmed.hasPrefix(":") && trimmed.hasSuffix(":") {
                return .center
            } else if trimmed.hasSuffix(":") {
                return .trailing
            } else {
                return .leading
            }
        }
    }

    private func normalizedTableCells(_ cells: [String], count: Int) -> [String] {
        if cells.count == count { return cells }
        if cells.count > count { return Array(cells.prefix(count)) }
        return cells + Array(repeating: "", count: count - cells.count)
    }

    private func unorderedListMarker(in line: String) -> (indent: Int, marker: String, contentIndent: Int, content: String)? {
        let indent = indentationCount(in: line)
        guard indent < 4 else { return nil }
        let trimmed = line.dropFirst(indent)
        guard let first = trimmed.first, ["-", "*", "+"].contains(first) else { return nil }
        let afterMarker = trimmed.dropFirst()
        guard afterMarker.first == " " || afterMarker.first == "\t" else { return nil }
        let contentIndent = indent + 1 + afterMarker.prefix { $0 == " " || $0 == "\t" }.count
        return (indent, String(first), contentIndent, String(afterMarker).trimmingCharacters(in: .whitespaces))
    }

    private func orderedListMarker(in line: String) -> (indent: Int, number: Int, delimiter: Character, contentIndent: Int, content: String)? {
        let indent = indentationCount(in: line)
        guard indent < 4 else { return nil }
        let trimmed = line.dropFirst(indent)
        let digits = trimmed.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 9, let number = Int(digits) else { return nil }
        let afterDigits = trimmed.dropFirst(digits.count)
        guard let delimiter = afterDigits.first, delimiter == "." || delimiter == ")" else { return nil }
        let afterDelimiter = afterDigits.dropFirst()
        guard afterDelimiter.first == " " || afterDelimiter.first == "\t" else { return nil }
        let contentIndent = indent + digits.count + 1 + afterDelimiter.prefix { $0 == " " || $0 == "\t" }.count
        return (indent, number, delimiter, contentIndent, String(afterDelimiter).trimmingCharacters(in: .whitespaces))
    }

    private func indentationCount(in line: String) -> Int {
        var count = 0
        for character in line {
            if character == " " {
                count += 1
            } else if character == "\t" {
                count += 4
            } else {
                break
            }
        }
        return count
    }

    private func removeIndent(from line: String, count: Int) -> String {
        var remaining = count
        var output = line[...]

        while remaining > 0, let first = output.first {
            if first == " " {
                output.removeFirst()
                remaining -= 1
            } else if first == "\t" {
                output.removeFirst()
                remaining -= 4
            } else {
                break
            }
        }

        return String(output)
    }

    private func indentedCodeLine(_ line: String) -> Bool {
        indentationCount(in: line) >= 4
    }
}
