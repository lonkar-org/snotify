// HistoryViews.swift - the pieces the history window is made of: the sender's
// glyph on a tinted disc, a row in the list, a day header, a row in the
// sidebar, an outcome pill, a card, and the detail pane that renders one
// entry as a header, its outcomes, the click command, the Info Markdown and
// the rest of the frontmatter grouped the way the file groups it.

import AppKit

// MARK: - Entry helpers

extension HistoryEntry {
    var day: Date? { time.map { Calendar.current.startOfDay(for: $0) } }
    var hasInfo: Bool { !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var failed: Bool { (self["status"] ?? "").hasPrefix("failed") }
    var iconSpec: IconSpec? { self["icon"].flatMap { IconSpec($0) } }
    /// The colour the script chose, or nil; the glyph is drawn in label colour then.
    var iconColor: NSColor? { self["color"].flatMap(parseColor) }
}

/// What the list shows: every word of the query, a span of whole days, one
/// sender, one outcome. Each facet is counted against the other three.
struct HistoryFilter {
    enum Show: CaseIterable {
        case everything, clicked, infoOpened, replaced, failed
        var label: String {
            switch self {
            case .everything: return "Everything"
            case .clicked: return "Clicked"
            case .infoOpened: return "Info opened"
            case .replaced: return "Replaced"
            case .failed: return "Failed"
            }
        }
        var symbol: String {
            switch self {
            case .everything: return "tray.full"
            case .clicked: return "hand.tap"
            case .infoOpened: return "doc.text.magnifyingglass"
            case .replaced: return "arrow.triangle.2.circlepath"
            case .failed: return "exclamationmark.triangle"
            }
        }
        func matches(_ e: HistoryEntry) -> Bool {
            switch self {
            case .everything: return true
            case .clicked: return e["outcome.clicked"] != nil
            case .infoOpened: return e["outcome.info_opened"] != nil
            case .replaced: return e["outcome.replaced_by"] != nil
            case .failed: return e.failed
            }
        }
    }

    var query = ""
    var days: DateInterval?
    var sender: String?
    var show = Show.everything

    func matchesQuery(_ e: HistoryEntry) -> Bool { query.isEmpty || e.matches(query) }
    func matchesDays(_ e: HistoryEntry) -> Bool {
        guard let d = days else { return true }
        guard let t = e.time else { return false }
        return t >= d.start && t < d.end
    }
    func matchesSender(_ e: HistoryEntry) -> Bool { sender == nil || e.sender == sender }
    func matches(_ e: HistoryEntry) -> Bool { matchesQuery(e) && matchesDays(e) && matchesSender(e) && show.matches(e) }
}

// MARK: - Glyph on a disc

private var badgeCache: [String: NSImage] = [:]

final class IconBadge: NSView {
    var diameter: CGFloat = 36 { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    var icon: IconSpec? { didSet { needsDisplay = true } }
    var color: NSColor? { didSet { needsDisplay = true } }
    /// Drawn when there is no glyph: the sender's initial.
    var initial = "" { didSet { needsDisplay = true } }

    override var intrinsicContentSize: NSSize { NSSize(width: diameter, height: diameter) }

    func set(_ e: HistoryEntry) {
        icon = e.iconSpec
        color = e.iconColor
        initial = String(e.sender.prefix(1)).uppercased()
        setAccessibilityLabel(e["icon"] ?? e.sender)
    }

    override func draw(_ dirty: NSRect) {
        let tint = color ?? .systemGray
        tint.withAlphaComponent(0.16).setFill()
        NSBezierPath(ovalIn: bounds).fill()
        if let icon = icon {
            let px = Int(diameter * 2)
            let key = icon.spec + "|" + (color?.description ?? "label") + "|\(px)"
            let image = badgeCache[key] ?? {
                let i = iconImage(icon, color: color ?? .labelColor, pixels: px)
                if let i = i { badgeCache[key] = i }
                return i
            }()
            let inset = diameter * 0.2
            image?.draw(in: bounds.insetBy(dx: inset, dy: inset))
        } else {
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: diameter * 0.42, weight: .semibold), .foregroundColor: tint]
            let s = initial.size(withAttributes: attrs)
            initial.draw(at: NSPoint(x: bounds.midX - s.width / 2, y: bounds.midY - s.height / 2), withAttributes: attrs)
        }
    }
}

// MARK: - Small pieces

/// A symbol and a word on a tinted capsule: an outcome.
final class Pill: NSView {
    init(symbol: String, text: String, tint: NSColor) {
        super.init(frame: .zero)
        self.tint = tint
        let image = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold)) ?? NSImage())
        image.contentTintColor = tint
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        label.textColor = tint
        let stack = NSStackView(views: [image, label])
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 3, left: 8, bottom: 3, right: 9)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(text)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    private var tint = NSColor.secondaryLabelColor
    override func draw(_ dirty: NSRect) {
        tint.withAlphaComponent(0.13).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
    }
}

/// A rounded box with a small heading, the way System Settings groups things.
final class Card: NSView {
    let stack = FillStack()
    init(title: String?, accessory: NSView? = nil) {
        super.init(frame: .zero)
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 14, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        if let t = title {
            let label = NSTextField(labelWithString: t.uppercased())
            label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
            label.textColor = .secondaryLabelColor
            if let a = accessory {
                let row = NSStackView(views: [label, a])
                row.alignment = .centerY
                label.setContentHuggingPriority(.defaultLow, for: .horizontal)
                stack.addArrangedSubview(row)
            } else {
                stack.addArrangedSubview(label)
            }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    func add(_ v: NSView) { stack.addArrangedSubview(v) }
    override func draw(_ dirty: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

func label(_ s: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, color: NSColor = .labelColor, mono: Bool = false, wrap: Bool = true) -> NSTextField {
    let l = wrap ? NSTextField(wrappingLabelWithString: s) : NSTextField(labelWithString: s)
    l.font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    l.textColor = color
    l.isSelectable = wrap
    if wrap {
        l.maximumNumberOfLines = 0
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    } else {
        l.lineBreakMode = .byTruncatingTail
    }
    return l
}

/// Keys on the left, values on the right, the values selectable.
func keyValueGrid(_ pairs: [(String, String)], mono: Set<String> = []) -> NSGridView {
    let rows: [[NSView]] = pairs.map { k, v in
        let key = label(k, size: 12, color: .secondaryLabelColor, wrap: false)
        key.alignment = .right
        key.setContentCompressionResistancePriority(.required, for: .horizontal)
        let value = label(v, size: mono.contains(k) ? 11 : 12, mono: mono.contains(k))
        return [key, value]
    }
    let grid = NSGridView(views: rows)
    grid.rowSpacing = 5
    grid.columnSpacing = 12
    grid.column(at: 0).xPlacement = .trailing
    grid.column(at: 0).width = 88
    grid.rowAlignment = .firstBaseline
    grid.translatesAutoresizingMaskIntoConstraints = false
    return grid
}

private final class FlippedView: NSView { override var isFlipped: Bool { true } }

/// A vertical stack whose arranged views span its width: NSStackView's own
/// alignments only pin one edge, so a card or a wrapping label would hug
/// its content and sit wherever the alignment put it.
final class FillStack: NSStackView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        orientation = .vertical
        alignment = .leading
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func addArrangedSubview(_ view: NSView) {
        super.addArrangedSubview(view)
        view.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -edgeInsets.right).isActive = true
    }
}

// MARK: - A row in the list

final class EntryRowView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("entry")
    private let badge = IconBadge()
    private let title = NSTextField(labelWithString: "")
    private let time = NSTextField(labelWithString: "")
    private let line = NSTextField(labelWithString: "")
    private let marks = NSStackView()
    private var senderColor = NSColor.secondaryLabelColor
    private var sender = "", body = ""
    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    init() {
        super.init(frame: .zero)
        identifier = EntryRowView.identifier
        title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 1
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        time.font = NSFont.systemFont(ofSize: 11)
        time.textColor = .secondaryLabelColor
        time.setContentCompressionResistancePriority(.required, for: .horizontal)
        line.font = NSFont.systemFont(ofSize: 12)
        line.lineBreakMode = .byTruncatingTail
        line.maximumNumberOfLines = 1
        line.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        marks.spacing = 5
        marks.setContentCompressionResistancePriority(.required, for: .horizontal)
        for v in [badge, title, time, line, marks] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        textField = title
        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            badge.centerYAnchor.constraint(equalTo: centerYAnchor),
            title.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 10),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            title.trailingAnchor.constraint(lessThanOrEqualTo: time.leadingAnchor, constant: -8),
            time.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            time.firstBaselineAnchor.constraint(equalTo: title.firstBaselineAnchor),
            line.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            line.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3),
            line.trailingAnchor.constraint(lessThanOrEqualTo: marks.leadingAnchor, constant: -8),
            marks.trailingAnchor.constraint(equalTo: time.trailingAnchor),
            marks.centerYAnchor.constraint(equalTo: line.centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func set(_ e: HistoryEntry) {
        badge.set(e)
        title.stringValue = e.title.isEmpty ? e.name : e.title
        time.stringValue = e.time.map { EntryRowView.clock.string(from: $0) } ?? ""
        sender = e.sender
        body = [e["subtitle"], e["body"]].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ").replacingOccurrences(of: "\n", with: " ")
        senderColor = e.iconColor ?? .secondaryLabelColor
        toolTip = body.isEmpty ? nil : body
        for v in marks.arrangedSubviews { v.removeFromSuperview() }
        var symbols: [(String, NSColor, String)] = []
        if e.hasInfo { symbols.append(("doc.text", .tertiaryLabelColor, "has Info text")) }
        if e["outcome.clicked"] != nil { symbols.append(("hand.tap.fill", .secondaryLabelColor, "clicked")) }
        if e["outcome.info_opened"] != nil { symbols.append(("eye.fill", .secondaryLabelColor, "Info opened")) }
        if e["outcome.replaced_by"] != nil { symbols.append(("arrow.triangle.2.circlepath", .tertiaryLabelColor, "replaced by a later post")) }
        if e["outcome.dismissed"] != nil { symbols.append(("xmark.circle", .tertiaryLabelColor, "dismissed")) }
        if e.failed { symbols.append(("exclamationmark.triangle.fill", .systemRed, "failed")) }
        for (name, tint, desc) in symbols {
            let iv = NSImageView(image: NSImage(systemSymbolName: name, accessibilityDescription: desc)?
                .withSymbolConfiguration(.init(pointSize: 10, weight: .medium)) ?? NSImage())
            iv.contentTintColor = tint
            iv.toolTip = desc
            marks.addArrangedSubview(iv)
        }
        recolor()
        setAccessibilityLabel([e.sender, title.stringValue, body, time.stringValue].filter { !$0.isEmpty }.joined(separator: ", "))
    }

    override var backgroundStyle: NSView.BackgroundStyle { didSet { recolor() } }

    private func recolor() {
        let emphasized = backgroundStyle == .emphasized
        title.textColor = emphasized ? .alternateSelectedControlTextColor : .labelColor
        time.textColor = emphasized ? NSColor.alternateSelectedControlTextColor.withAlphaComponent(0.8) : .secondaryLabelColor
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        let who = NSMutableAttributedString(string: sender, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium), .paragraphStyle: para,
            .foregroundColor: emphasized ? NSColor.alternateSelectedControlTextColor : senderColor])
        if !body.isEmpty {
            who.append(NSAttributedString(string: "  " + body, attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: emphasized ? NSColor.alternateSelectedControlTextColor.withAlphaComponent(0.85) : NSColor.secondaryLabelColor]))
        }
        line.attributedStringValue = who
        for case let iv as NSImageView in marks.arrangedSubviews where emphasized {
            iv.contentTintColor = NSColor.alternateSelectedControlTextColor.withAlphaComponent(0.85)
        }
    }
}

final class DayHeaderView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("day")
    private let title = NSTextField(labelWithString: "")
    private let count = NSTextField(labelWithString: "")
    init() {
        super.init(frame: .zero)
        identifier = DayHeaderView.identifier
        title.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        title.textColor = .secondaryLabelColor
        count.font = NSFont.systemFont(ofSize: 11)
        count.textColor = .tertiaryLabelColor
        for v in [title, count] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        textField = title
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            title.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            count.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            count.firstBaselineAnchor.constraint(equalTo: title.firstBaselineAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    func set(_ day: String, count n: Int) {
        title.stringValue = day.uppercased()
        count.stringValue = String(n)
    }
}

// MARK: - A row in the sidebar

final class SidebarRow: NSView {
    private let image = NSImageView()
    private let badge = IconBadge()
    private let name = NSTextField(labelWithString: "")
    private let count = NSTextField(labelWithString: "")
    var onClick: (() -> Void)?
    var isSelected = false { didSet { needsDisplay = true; recolor() } }

    init(title: String, symbol: String? = nil, entry: HistoryEntry? = nil, count n: Int) {
        super.init(frame: .zero)
        name.stringValue = title
        name.font = NSFont.systemFont(ofSize: 13)
        name.lineBreakMode = .byTruncatingTail
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        count.stringValue = String(n)
        count.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        count.textColor = .secondaryLabelColor
        count.setContentCompressionResistancePriority(.required, for: .horizontal)
        let leading: NSView
        if let e = entry, e.iconSpec != nil {
            badge.diameter = 20
            badge.set(e)
            leading = badge
        } else if let s = symbol {
            image.image = NSImage(systemSymbolName: s, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
            image.contentTintColor = .controlAccentColor
            leading = image
        } else {
            badge.diameter = 20
            badge.initial = String(title.prefix(1)).uppercased()
            leading = badge
        }
        for v in [leading, name, count] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),
            leading.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            leading.centerYAnchor.constraint(equalTo: centerYAnchor),
            leading.widthAnchor.constraint(equalToConstant: 20),
            name.leadingAnchor.constraint(equalTo: leading.trailingAnchor, constant: 8),
            name.centerYAnchor.constraint(equalTo: centerYAnchor),
            count.leadingAnchor.constraint(greaterThanOrEqualTo: name.trailingAnchor, constant: 6),
            count.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            count.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("\(title), \(n)")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func recolor() {
        setAccessibilitySelected(isSelected)
        name.font = NSFont.systemFont(ofSize: 13, weight: isSelected ? .medium : .regular)
    }

    override func draw(_ dirty: NSRect) {
        guard isSelected else { return }
        NSColor.labelColor.withAlphaComponent(0.1).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }

    override func mouseDown(with event: NSEvent) { onClick?() }
}

// MARK: - The detail pane

final class DetailView: NSView {
    private let scroll = NSScrollView()
    private let doc = FlippedView()
    private let stack = FillStack()
    private let emptySymbol = NSImageView()
    private let emptyText = NSTextField(labelWithString: "")
    private let empty = NSStackView()
    var onRun: (() -> Void)?
    var onOpenInfo: (() -> Void)?
    private static let when: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .short
        return f
    }()

    override init(frame: NSRect) {
        super.init(frame: frame)
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 28, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(stack)
        scroll.documentView = doc
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        emptySymbol.image = NSImage(systemSymbolName: "tray", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 40, weight: .light))
        emptySymbol.contentTintColor = .tertiaryLabelColor
        emptyText.font = NSFont.systemFont(ofSize: 13)
        emptyText.textColor = .secondaryLabelColor
        emptyText.alignment = .center
        empty.orientation = .vertical
        empty.alignment = .centerX
        empty.spacing = 10
        empty.addArrangedSubview(emptySymbol)
        empty.addArrangedSubview(emptyText)
        empty.translatesAutoresizingMaskIntoConstraints = false
        addSubview(empty)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.topAnchor.constraint(equalTo: doc.topAnchor), stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor), stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            empty.centerXAnchor.constraint(equalTo: centerXAnchor), empty.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -20),
        ])
        setAccessibilityLabel("Selected notification")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirty: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
    }

    func render(_ e: HistoryEntry?, placeholder: String) {
        for v in stack.arrangedSubviews { v.removeFromSuperview() }
        guard let e = e else {
            emptyText.stringValue = placeholder
            empty.isHidden = false
            scroll.isHidden = true
            return
        }
        empty.isHidden = true
        scroll.isHidden = false
        stack.addArrangedSubview(header(e))
        if let b = e["body"], !b.isEmpty { stack.addArrangedSubview(label(b, size: 14)) }
        stack.addArrangedSubview(outcomes(e))
        if let c = e["on_click"], !c.isEmpty {
            let run = NSButton(title: "Run", target: self, action: #selector(runClick))
            run.bezelStyle = .rounded
            run.controlSize = .small
            run.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: nil)
            run.imagePosition = .imageLeading
            run.toolTip = "Run the command the click would have run"
            let card = Card(title: "On click", accessory: run)
            card.add(label(c, size: 12, mono: true))
            if let d = e["sender.cwd"], !d.isEmpty { card.add(label("in " + d, size: 11, color: .secondaryLabelColor, mono: true)) }
            stack.addArrangedSubview(card)
        }
        if e.hasInfo {
            let open = NSButton(title: "Open", target: self, action: #selector(openInfo))
            open.bezelStyle = .rounded
            open.controlSize = .small
            open.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
            open.imagePosition = .imageLeading
            open.toolTip = "Open the Info window the banner's Info button opens"
            let card = Card(title: "Info", accessory: open)
            let md = NSTextField(wrappingLabelWithString: "")
            md.attributedStringValue = styled(markdown: e.body)
            md.isSelectable = true
            md.allowsEditingTextAttributes = true
            md.maximumNumberOfLines = 0
            md.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            card.add(md)
            stack.addArrangedSubview(card)
        }
        for (title, pairs, mono) in groups(e) where !pairs.isEmpty {
            let card = Card(title: title)
            card.add(keyValueGrid(pairs, mono: mono))
            stack.addArrangedSubview(card)
        }
        // the top is above the origin by the toolbar's inset
        scroll.contentView.scroll(to: NSPoint(x: 0, y: -scroll.contentView.contentInsets.top))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    private func header(_ e: HistoryEntry) -> NSView {
        let badge = IconBadge()
        badge.diameter = 56
        badge.set(e)
        badge.setContentHuggingPriority(.required, for: .horizontal)
        let title = label(e.title.isEmpty ? e.name : e.title, size: 22, weight: .bold)
        var meta = [e.sender, e.time.map { DetailView.when.string(from: $0) }].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "  ·  ")
        if let s = e["subtitle"], !s.isEmpty { meta = s + "\n" + meta }
        let sub = label(meta, size: 12, color: .secondaryLabelColor)
        let column = NSStackView(views: [title, sub])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 4
        column.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [badge, column])
        row.alignment = .top
        row.spacing = 14
        column.trailingAnchor.constraint(equalTo: row.trailingAnchor).isActive = true
        return row
    }

    private func outcomes(_ e: HistoryEntry) -> NSView {
        let clock = DateFormatter()
        clock.timeStyle = .short
        func at(_ key: String) -> String {
            guard let v = e[key], let d = HistoryEntry.iso.date(from: v) else { return "" }
            return " " + clock.string(from: d)
        }
        var pills: [NSView] = []
        if e.failed {
            pills.append(Pill(symbol: "exclamationmark.triangle.fill", text: e["status"] ?? "failed", tint: .systemRed))
        } else {
            pills.append(Pill(symbol: "paperplane.fill", text: (e["status"] ?? "posted").capitalized + at("time"), tint: .systemBlue))
        }
        if e["outcome.clicked"] != nil { pills.append(Pill(symbol: "hand.tap.fill", text: "Clicked" + at("outcome.clicked"), tint: .systemGreen)) }
        if e["outcome.info_opened"] != nil { pills.append(Pill(symbol: "eye.fill", text: "Info opened" + at("outcome.info_opened"), tint: .systemIndigo)) }
        if e["outcome.dismissed"] != nil { pills.append(Pill(symbol: "xmark.circle.fill", text: "Dismissed" + at("outcome.dismissed"), tint: .systemGray)) }
        if e["outcome.replaced_by"] != nil { pills.append(Pill(symbol: "arrow.triangle.2.circlepath", text: "Replaced by a later post", tint: .systemOrange)) }
        if let s = e["sound"], !s.isEmpty { pills.append(Pill(symbol: "speaker.wave.2.fill", text: s, tint: .systemTeal)) }
        for p in pills { p.setContentHuggingPriority(.required, for: .horizontal) }
        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        let row = NSStackView(views: pills + [spacer])
        row.spacing = 6
        row.alignment = .centerY
        row.setClippingResistancePriority(.defaultLow, for: .horizontal)
        return row
    }

    /// The frontmatter as the file groups it: the top-level keys first, then
    /// each dotted prefix as its own card.
    private func groups(_ e: HistoryEntry) -> [(String, [(String, String)], Set<String>)] {
        let skip: Set<String> = ["title", "subtitle", "body", "on_click", "status", "sound", "time", "icon", "color"]
        var top: [(String, String)] = []
        var byPrefix: [String: [(String, String)]] = [:]
        var order: [String] = []
        for (k, v) in e.fields where !v.isEmpty {
            if let dot = k.firstIndex(of: ".") {
                let p = String(k[..<dot])
                if byPrefix[p] == nil { order.append(p) }
                byPrefix[p, default: []].append((String(k[k.index(after: dot)...]), v))
            } else if !skip.contains(k) {
                top.append((k, v))
            }
        }
        if let i = e["icon"] { top.append(("icon", i + (e["color"].map { ", " + $0 } ?? ""))) }
        top.append(("file", e.name))
        var out: [(String, [(String, String)], Set<String>)] = [("Notification", top, ["id", "group", "file"])]
        // outcome is already the pills; meta before sender, since it is the script's own
        let preferred = ["meta", "sender", "terminal"]
        for p in preferred + order.filter({ !preferred.contains($0) }) where p != "outcome" {
            guard let pairs = byPrefix[p] else { continue }
            out.append((p.capitalized, pairs, ["pid", "command", "ancestry", "cwd", "tty", "launchd", "tmux_pane", "tmux", "ssh", "app"]))
        }
        return out
    }

    @objc private func runClick() { onRun?() }
    @objc private func openInfo() { onOpenInfo?() }
}
