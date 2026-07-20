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
        var parser = Parser(markdown: resolvingReferenceLinks(in: markdown))
        return parser.parseBlocks()
    }

    private static func resolvingReferenceLinks(in markdown: String) -> String {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines = normalized.components(separatedBy: "\n")
        var definitions: [String: String] = [:]
        var activeFence: (character: Character, length: Int)?

        for index in lines.indices {
            let line = lines[index]
            if let fence = activeFence {
                if closesFence(line, fence: fence) { activeFence = nil }
                continue
            }
            if let fence = openingFence(line) {
                activeFence = fence
                continue
            }
            if let definition = referenceDefinition(in: line) {
                definitions[normalizedReferenceLabel(definition.label)] = definition.destination
                lines[index] = ""
            }
        }
        guard !definitions.isEmpty else { return normalized }

        activeFence = nil
        for index in lines.indices {
            let line = lines[index]
            if let fence = activeFence {
                if closesFence(line, fence: fence) { activeFence = nil }
                continue
            }
            if let fence = openingFence(line) {
                activeFence = fence
                continue
            }
            // Indented code blocks must keep literal reference-looking text.
            if indentationCount(in: line) >= 4 {
                continue
            }
            lines[index] = replacingReferences(in: line, definitions: definitions)
        }
        return lines.joined(separator: "\n")
    }

    private static func indentationCount(in line: String) -> Int {
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

    private static func normalizedReferenceLabel(_ label: String) -> String {
        label
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

    private static func referenceDefinition(in line: String) -> (label: String, destination: String)? {
        let pattern = #"^\s{0,3}\[([^\]]+)\]:\s*(\S+)(?:\s+(?:"([^"]*)"|'([^']*)'|\(([^)]*)\)))?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let source = line as NSString
        let range = NSRange(location: 0, length: source.length)
        guard let match = regex.firstMatch(in: line, range: range) else { return nil }
        let label = source.substring(with: match.range(at: 1))
        let url = source.substring(with: match.range(at: 2))
        let title = (3...5)
            .compactMap { capture -> String? in
                let captureRange = match.range(at: capture)
                return captureRange.location == NSNotFound ? nil : source.substring(with: captureRange)
            }
            .first
        let destination = title.map {
            "\(url) \"\($0.replacingOccurrences(of: "\"", with: "\\\""))\""
        } ?? url
        return (label, destination)
    }

    private static func replacingReferences(
        in line: String,
        definitions: [String: String]
    ) -> String {
        var result = replaceMatches(
            in: line,
            pattern: #"\[([^\]\n]+)\]\[([^\]\n]*)\]"#,
            definitions: definitions,
            usesExplicitLabel: true
        )
        result = replaceMatches(
            in: result,
            pattern: #"(?<!!)\[([^\]\n]+)\](?![\[(])"#,
            definitions: definitions,
            usesExplicitLabel: false
        )
        return result
    }

    private static func replaceMatches(
        in line: String,
        pattern: String,
        definitions: [String: String],
        usesExplicitLabel: Bool
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return line }
        let mutable = NSMutableString(string: line)
        let matches = regex.matches(
            in: line,
            range: NSRange(location: 0, length: (line as NSString).length)
        )
        let codeSpans = inlineCodeSpanRanges(in: line)
        for match in matches.reversed() {
            if codeSpans.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
                continue
            }
            let text = mutable.substring(with: match.range(at: 1))
            let explicit = usesExplicitLabel ? mutable.substring(with: match.range(at: 2)) : text
            let label = normalizedReferenceLabel(explicit.isEmpty ? text : explicit)
            guard let destination = definitions[label] else { continue }
            mutable.replaceCharacters(in: match.range, with: "[\(text)](\(destination))")
        }
        return mutable as String
    }

    /// Ranges of CommonMark inline code spans (backtick-delimited) on a single line.
    private static func inlineCodeSpanRanges(in line: String) -> [NSRange] {
        let nsLine = line as NSString
        var ranges: [NSRange] = []
        var index = 0
        let length = nsLine.length
        while index < length {
            var openerLength = 0
            while index + openerLength < length,
                  nsLine.character(at: index + openerLength) == 0x60 { // `
                openerLength += 1
            }
            guard openerLength > 0 else {
                index += 1
                continue
            }
            let searchStart = index + openerLength
            var closerStart = searchStart
            var found: NSRange?
            while closerStart < length {
                var closerLength = 0
                while closerStart + closerLength < length,
                      nsLine.character(at: closerStart + closerLength) == 0x60 {
                    closerLength += 1
                }
                if closerLength == openerLength {
                    found = NSRange(
                        location: index,
                        length: (closerStart + closerLength) - index
                    )
                    break
                }
                closerStart += max(closerLength, 1)
            }
            if let span = found {
                ranges.append(span)
                index = span.location + span.length
            } else {
                index = searchStart
            }
        }
        return ranges
    }

    private static func openingFence(_ line: String) -> (character: Character, length: Int)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let character = trimmed.first, character == "`" || character == "~" else { return nil }
        let length = trimmed.prefix { $0 == character }.count
        return length >= 3 ? (character, length) : nil
    }

    private static func closesFence(
        _ line: String,
        fence: (character: Character, length: Int)
    ) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let length = trimmed.prefix { $0 == fence.character }.count
        return length >= fence.length
            && trimmed.dropFirst(length).trimmingCharacters(in: .whitespaces).isEmpty
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

            paragraphLines.append(String(line.drop(while: { $0 == " " || $0 == "\t" })))
            index += 1
        }

        return .paragraph(paragraphLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
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
            let sourceMarker: String
            let sourceContent: String
            let itemIndent: Int

            switch markerKind {
            case .unordered:
                guard let parsed = unorderedListMarker(in: line), parsed.indent == baseIndent else {
                    return listBlock(markerKind: markerKind, start: startNumber, items: items)
                }
                sourceMarker = parsed.marker
                sourceContent = parsed.content
                itemIndent = parsed.contentIndent
            case .ordered:
                guard let parsed = orderedListMarker(in: line), parsed.indent == baseIndent else {
                    return listBlock(markerKind: markerKind, start: startNumber, items: items)
                }
                sourceMarker = "\(parsed.number)\(parsed.delimiter)"
                sourceContent = parsed.content
                itemIndent = parsed.contentIndent
            }

            let task = taskListItem(in: sourceContent)
            let marker = task.map { $0.isChecked ? "☑︎" : "☐" } ?? sourceMarker
            let content = task?.content ?? sourceContent

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
                if nextIndent <= baseIndent {
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

    private func taskListItem(in content: String) -> (isChecked: Bool, content: String)? {
        guard content.count >= 3, content.first == "[" else { return nil }
        let marker = content.prefix(3).lowercased()
        guard marker == "[ ]" || marker == "[x]" else { return nil }
        let remainder = content.dropFirst(3)
        guard remainder.isEmpty || remainder.first?.isWhitespace == true else { return nil }
        return (
            isChecked: marker == "[x]",
            content: remainder.trimmingCharacters(in: .whitespaces)
        )
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
            guard !core.isEmpty, core.allSatisfy({ $0 == "-" }) else { return nil }

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
