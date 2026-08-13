import SwiftUI

// MARK: - Blocks

enum MarkdownBlock: Equatable {
    case text(String)
    case table(MarkdownTable)
}

struct MarkdownTable: Equatable {
    let headers: [String]
    let rows: [[String]]

    var columnCount: Int {
        max(headers.count, rows.map(\.count).max() ?? 0)
    }
}

// MARK: - Parser

enum MarkdownBlockParser {
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        var blocks: [MarkdownBlock] = []
        var textBuffer: [String] = []
        var index = 0

        func flushText() {
            let joined = textBuffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty {
                blocks.append(.text(joined))
            }
            textBuffer.removeAll(keepingCapacity: true)
        }

        while index < lines.count {
            if let table = parseTable(from: lines, startingAt: index) {
                flushText()
                blocks.append(.table(table.table))
                index = table.endIndex
                continue
            }

            textBuffer.append(lines[index])
            index += 1
        }

        flushText()
        return blocks
    }

    private static func parseTable(from lines: [String], startingAt start: Int) -> (table: MarkdownTable, endIndex: Int)? {
        guard start + 1 < lines.count else { return nil }

        let headerLine = lines[start]
        let separatorLine = lines[start + 1]
        guard isTableRow(headerLine), isSeparatorRow(separatorLine) else { return nil }

        let headers = splitCells(headerLine)
        guard !headers.isEmpty else { return nil }

        var rows: [[String]] = []
        var index = start + 2
        while index < lines.count, isTableRow(lines[index]), !isSeparatorRow(lines[index]) {
            var cells = splitCells(lines[index])
            // Normalize column count to header width for stable grids.
            if cells.count < headers.count {
                cells.append(contentsOf: Array(repeating: "", count: headers.count - cells.count))
            } else if cells.count > headers.count {
                cells = Array(cells.prefix(headers.count))
            }
            rows.append(cells)
            index += 1
        }

        return (MarkdownTable(headers: headers, rows: rows), index)
    }

    private static func isTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return false }
        // Need at least two cells (one pipe). Pure pipe/whitespace lines are ignored.
        return trimmed.split(separator: "|", omittingEmptySubsequences: false).count >= 2
            && !trimmed.allSatisfy({ $0 == "|" || $0.isWhitespace })
    }

    private static func isSeparatorRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") || trimmed.contains("-") else { return false }

        let body = trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
            .replacingOccurrences(of: " ", with: "")

        guard !body.isEmpty else { return false }
        return body.allSatisfy { $0 == "-" || $0 == ":" || $0 == "|" }
            && body.contains("-")
    }

    private static func splitCells(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        return trimmed
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

// MARK: - Content view

struct MarkdownContentView: View {
    let text: String
    var font: Font = .subheadline

    private var blocks: [MarkdownBlock] {
        MarkdownBlockParser.parse(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let markdown):
                    Text(attributed(markdown))
                        .font(font)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)

                case .table(let table):
                    MarkdownTableView(table: table)
                }
            }
        }
    }

    private func attributed(_ markdown: String) -> AttributedString {
        let cleaned = MarkdownHTML.unescape(markdown)
        return (try? AttributedString(
            markdown: cleaned,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        )) ?? AttributedString(cleaned)
    }
}

// MARK: - Table view

struct MarkdownTableView: View {
    let table: MarkdownTable

    private var usesHorizontalScroll: Bool {
        table.columnCount >= 4
    }

    var body: some View {
        Group {
            if usesHorizontalScroll {
                ScrollView(.horizontal, showsIndicators: false) {
                    tableGrid
                }
            } else {
                tableGrid
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        }
    }

    private var tableGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(Array(table.headers.enumerated()), id: \.offset) { index, header in
                    cell(
                        header,
                        isHeader: true,
                        columnIndex: index,
                        isLastColumn: index == table.headers.count - 1
                    )
                }
            }

            ForEach(Array(table.rows.enumerated()), id: \.offset) { rowIndex, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { columnIndex, value in
                        cell(
                            value,
                            isHeader: false,
                            isZebra: rowIndex.isMultiple(of: 2) == false,
                            columnIndex: columnIndex,
                            isLastColumn: columnIndex == row.count - 1,
                            isLastRow: rowIndex == table.rows.count - 1
                        )
                    }
                }
            }
        }
        .background(Theme.elevatedSurface.opacity(0.55))
    }

    @ViewBuilder
    private func cell(
        _ value: String,
        isHeader: Bool,
        isZebra: Bool = false,
        columnIndex: Int,
        isLastColumn: Bool,
        isLastRow: Bool = false
    ) -> some View {
        let isLeadingColumn = columnIndex == 0
        Text(attributedCell(value))
            .font(isHeader ? .caption.weight(.semibold) : .caption)
            .foregroundStyle(.primary.opacity(isHeader ? 1 : 0.92))
            .multilineTextAlignment(.leading)
            .lineLimit(usesHorizontalScroll ? 3 : nil)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, isHeader ? 9 : 8)
            .frame(
                minWidth: usesHorizontalScroll ? 88 : nil,
                maxWidth: usesHorizontalScroll || !isLeadingColumn ? .infinity : nil,
                maxHeight: .infinity,
                alignment: .topLeading
            )
            .background {
                if isHeader {
                    Theme.elevatedSurface
                } else if isZebra {
                    Theme.brandGradientSoft.opacity(0.55)
                } else {
                    Color.clear
                }
            }
            .overlay(alignment: .trailing) {
                if !isLastColumn {
                    Rectangle()
                        .fill(Theme.hairline)
                        .frame(width: 1)
                }
            }
            .overlay(alignment: .bottom) {
                if isHeader || !isLastRow {
                    Rectangle()
                        .fill(Theme.hairline)
                        .frame(height: 1)
                }
            }
    }

    private func attributedCell(_ value: String) -> AttributedString {
        let cleaned = MarkdownHTML.unescape(value)
        return (try? AttributedString(
            markdown: cleaned,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(cleaned)
    }
}

// MARK: - HTML leftovers in model output

private enum MarkdownHTML {
    static func unescape(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)</p>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)<p[^>]*>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}

#Preview("Coach tables") {
    let sample = """
    ### Week 1 – Foundation

    | Day | Exercise (duration) | Sample Meal Plan |
    |-----|---------------------|------------------|
    | Mon | 30 min steady-state jog | Breakfast: 1 banana<br>Lunch: chicken + quinoa<br>Dinner: yogurt + berries |
    | Wed | Strength 40 min | Breakfast: eggs · Lunch: chicken salad · Dinner: rice bowl |

    ### Week 2 – Intensity Boost

    | Day | Exercise (duration) | Sample Meal Plan |
    |-----|---------------------|------------------|
    | Mon | Jog + 5 min intervals | Same as week 1; add 1 snack |
    | Fri | Strength 45 min | Chicken over fish; keep quinoa |

    - Add 5 min to one cardio session
    """

    ScrollView {
        MarkdownContentView(text: sample)
            .padding(14)
            .surfaceCard(cornerRadius: 18)
            .padding()
    }
    .background(AmbientBackground())
}
