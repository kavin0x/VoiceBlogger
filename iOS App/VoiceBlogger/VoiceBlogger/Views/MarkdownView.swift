import SwiftUI

struct MarkdownView: View {
    private let blocks: [MarkdownProcessor.Block]

    init(text: String) {
        self.blocks = MarkdownProcessor.parse(text)
    }

    init(blocks: [MarkdownProcessor.Block]) {
        self.blocks = blocks
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownProcessor.Block

    var body: some View {
        switch block {
        case .heading(let level, let text):
            heading(text, level: level)
        case .paragraph(let text):
            Text(inlineMarkdown(text))
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        case .unorderedList(let items):
            list(items: items, ordered: false)
        case .orderedList(_, let items):
            list(items: items, ordered: true)
        case .codeBlock(let language, let code):
            codeBlock(code, language: language)
        case .blockquote(let blocks):
            blockquote(blocks)
        case .table(let table):
            tableView(table)
        case .divider:
            Divider()
                .padding(.vertical, 4)
        }
    }

    private func heading(_ text: String, level: Int) -> some View {
        Text(inlineMarkdown(text))
            .font(headingFont(for: level))
            .fontWeight(level == 1 ? .bold : .semibold)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, level == 1 ? 4 : 2)
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1:
            return .title
        case 2:
            return .title2
        case 3:
            return .title3
        case 4:
            return .headline
        case 5:
            return .subheadline.weight(.semibold)
        default:
            return .caption.weight(.semibold)
        }
    }

    private func list(items: [MarkdownProcessor.ListItem], ordered: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(ordered ? item.marker : "•")
                            .font(.body)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(minWidth: ordered ? 28 : 14, alignment: .trailing)
                        Text(inlineMarkdown(item.text))
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !item.children.isEmpty {
                        MarkdownView(blocks: item.children)
                            .padding(.leading, ordered ? 36 : 24)
                    }
                }
                .id(index)
            }
        }
    }

    private func codeBlock(_ code: String, language: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let language {
                Text(language)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code.isEmpty ? " " : code)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private func blockquote(_ blocks: [MarkdownProcessor.Block]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(Color.accentColor.opacity(0.5))
                .frame(width: 3)
            MarkdownView(blocks: blocks)
                .foregroundStyle(.secondary)
                .padding(.leading, 12)
        }
    }

    private func tableView(_ table: MarkdownProcessor.Table) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    ForEach(Array(table.columns.enumerated()), id: \.offset) { _, column in
                        Text(inlineMarkdown(column.title))
                            .font(.subheadline.weight(.semibold))
                            .frame(minWidth: 96, alignment: alignment(for: column.alignment))
                    }
                }

                Divider()
                    .gridCellColumns(max(table.columns.count, 1))

                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { columnIndex, cell in
                            let alignment = table.columns.indices.contains(columnIndex)
                                ? table.columns[columnIndex].alignment
                                : .leading
                            Text(inlineMarkdown(cell))
                                .font(.body)
                                .frame(minWidth: 96, alignment: self.alignment(for: alignment))
                        }
                    }
                }
            }
            .padding(12)
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private func alignment(for alignment: MarkdownProcessor.Table.Column.Alignment) -> Alignment {
        switch alignment {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }

    private func inlineMarkdown(_ string: String) -> AttributedString {
        (try? AttributedString(
            markdown: string,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(string)
    }
}
