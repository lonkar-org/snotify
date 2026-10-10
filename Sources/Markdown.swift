// Markdown.swift - Markdown to attributed text, for the Info window and the
// history window. AttributedString(markdown:) parses the structure but styles
// nothing, so each run is dressed here by the block and inline intents it carries.

import AppKit

// AttributedString(markdown:) parses the structure but styles nothing, so each
// run is dressed by the block and inline intents it carries. Blocks are
// separated here, as the parser drops the newlines between them.
func styled(markdown: String) -> NSAttributedString {
    let base = NSFont.systemFont(ofSize: 13)
    let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    let parsed: AttributedString
    do {
        parsed = try AttributedString(markdown: markdown, options: .init(
            allowsExtendedAttributes: true, interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible))
    } catch {
        return NSAttributedString(string: markdown, attributes: [.font: mono, .foregroundColor: NSColor.labelColor])
    }
    let out = NSMutableAttributedString()
    var lastBlock: Int? = nil
    var lastItem: Int? = nil
    var lastCell: Int? = nil
    var lastRow: Int? = nil
    for run in parsed.runs {
        let text = String(parsed[run.range].characters)
        var font = base
        var color = NSColor.labelColor
        var background: NSColor? = nil
        let para = NSMutableParagraphStyle()
        para.paragraphSpacing = 6
        var prefix = ""
        var separator = ""
        var isCode = false
        if let intent = run.presentationIntent {
            // components run innermost first; the innermost is the block
            // whose text this is, and a change of it is a block boundary.
            let block = intent.components.first?.identity
            var item: Int? = nil, cell: Int? = nil, row: Int? = nil
            var listOrdinal: Int? = nil
            var inList = false
            for comp in intent.components {
                switch comp.kind {
                case .header(let level):
                    font = NSFont.boldSystemFont(ofSize: level == 1 ? 19 : level == 2 ? 16 : 14)
                    para.paragraphSpacingBefore = 8
                case .codeBlock:
                    font = mono; isCode = true
                    background = NSColor.quaternaryLabelColor.withAlphaComponent(0.12)
                    para.headIndent = 8; para.firstLineHeadIndent = 8
                case .listItem(let ordinal):
                    item = comp.identity; listOrdinal = ordinal
                    para.headIndent = 20; para.firstLineHeadIndent = 4
                case .unorderedList: inList = true
                case .orderedList: inList = true
                case .blockQuote:
                    color = .secondaryLabelColor
                    para.headIndent = 14; para.firstLineHeadIndent = 14
                case .tableCell: cell = comp.identity
                case .tableRow: row = comp.identity
                case .tableHeaderRow: row = comp.identity; font = NSFont.boldSystemFont(ofSize: 13)
                case .thematicBreak: break
                default: break
                }
            }
            if row != nil {
                if row != lastRow { separator = out.length > 0 ? "\n" : "" }
                else if cell != lastCell { separator = "  |  " }
            } else if block != lastBlock, out.length > 0 {
                separator = "\n"
            }
            if let item = item, item != lastItem, let ordinal = listOrdinal {
                prefix = inList && listOrdinal != nil && isOrdered(intent) ? "\(ordinal). " : "•  "
            }
            lastBlock = block; lastItem = item; lastCell = cell; lastRow = row
        }
        if let inline = run.inlinePresentationIntent {
            if inline.contains(.code) { font = mono; background = NSColor.quaternaryLabelColor.withAlphaComponent(0.12) }
            if inline.contains(.stronglyEmphasized) {
                font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            }
            if inline.contains(.emphasized) {
                font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            }
        }
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: para]
        if let b = background { attrs[.backgroundColor] = b }
        if let link = run.link { attrs[.link] = link; attrs[.foregroundColor] = NSColor.linkColor }
        if !separator.isEmpty { out.append(NSAttributedString(string: separator, attributes: [.font: base, .paragraphStyle: para])) }
        if !prefix.isEmpty { out.append(NSAttributedString(string: prefix, attributes: attrs)) }
        out.append(NSAttributedString(string: isCode ? text.trimmingCharacters(in: .newlines) : text, attributes: attrs))
    }
    return out
}

func isOrdered(_ intent: PresentationIntent) -> Bool {
    intent.components.contains { if case .orderedList = $0.kind { return true } else { return false } }
}
