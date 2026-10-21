// CalendarView.swift - the month grid in the history window's sidebar. A dot
// under every day something was posted, darker the more there was; a click
// selects the day, shift-click or a drag selects a range, and a second click
// on the one selected day clears it. The selection is whole days, the start
// of the first to the start of the day after the last, so filtering an entry
// is two comparisons on its time.

import AppKit

final class CalendarView: NSView {
    /// Posts per day, keyed by the start of the day in the current calendar.
    var counts: [Date: Int] = [:] { didSet { needsDisplay = true } }
    private(set) var selection: DateInterval?
    /// Called after the user changes the selection, not after `set`.
    var onChange: ((DateInterval?) -> Void)?
    /// The first day of the month on show.
    private(set) var month: Date

    private let cal = Calendar.current
    private let title = NSTextField(labelWithString: "")
    private let prev = NSButton()
    private let next = NSButton()
    private var anchor: Date?
    private var dragged = false
    private let cellW: CGFloat = 32, cellH: CGFloat = 28, headerH: CGFloat = 30, weekdayH: CGFloat = 20
    private var gridTop: CGFloat { headerH + weekdayH }
    private static let monthName: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return f
    }()

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: cellW * 7, height: gridTop + cellH * 6) }

    override init(frame: NSRect) {
        month = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
        super.init(frame: frame)
        title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false
        for (b, name, label, sel) in [(prev, "chevron.left", "Previous month", #selector(previousMonth)),
                                      (next, "chevron.right", "Next month", #selector(nextMonth))] {
            b.image = NSImage(systemSymbolName: name, accessibilityDescription: label)?
                .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
            b.isBordered = false
            b.imagePosition = .imageOnly
            b.target = self
            b.action = sel
            b.contentTintColor = .secondaryLabelColor
            b.setAccessibilityLabel(label)
            b.translatesAutoresizingMaskIntoConstraints = false
            addSubview(b)
        }
        addSubview(title)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            title.centerYAnchor.constraint(equalTo: topAnchor, constant: headerH / 2),
            next.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            next.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            prev.trailingAnchor.constraint(equalTo: next.leadingAnchor, constant: -6),
            prev.centerYAnchor.constraint(equalTo: title.centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Calendar")
        updateTitle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: selection

    /// Set from outside (a quick range); `reveal` turns the grid to the
    /// month of the last selected day.
    func set(selection: DateInterval?, reveal: Bool = true) {
        self.selection = selection
        if reveal, let s = selection, let last = cal.date(byAdding: .day, value: -1, to: s.end) {
            month = cal.date(from: cal.dateComponents([.year, .month], from: last))!
            updateTitle()
        }
        setAccessibilityValue(describe(selection))
        needsDisplay = true
    }

    func days(_ lo: Date, _ hi: Date) -> DateInterval {
        DateInterval(start: min(lo, hi), end: cal.date(byAdding: .day, value: 1, to: max(lo, hi))!)
    }

    private var lastDay: Date? { selection.flatMap { cal.date(byAdding: .day, value: -1, to: $0.end) } }
    private var isSingleDay: Bool { selection.map { cal.date(byAdding: .day, value: 1, to: $0.start) == $0.end } ?? false }

    /// "All time", "Friday 10 October", "10 – 17 October".
    func describe(_ s: DateInterval?) -> String {
        guard let s = s, let last = cal.date(byAdding: .day, value: -1, to: s.end) else { return "All time" }
        let sameYear = cal.component(.year, from: s.start) == cal.component(.year, from: Date())
        if cal.isDate(s.start, inSameDayAs: last) {
            let f = DateFormatter()
            f.setLocalizedDateFormatFromTemplate(sameYear ? "EEEE d MMMM" : "EEEE d MMMM yyyy")
            return f.string(from: s.start)
        }
        let f = DateIntervalFormatter()
        f.dateTemplate = sameYear ? "d MMM" : "d MMM yyyy"
        return f.string(from: s.start, to: last)
    }

    // MARK: month

    @objc func previousMonth() { step(-1) }
    @objc func nextMonth() { step(1) }
    private func step(_ n: Int) {
        month = cal.date(byAdding: .month, value: n, to: month)!
        updateTitle()
        needsDisplay = true
    }
    private func updateTitle() { title.stringValue = CalendarView.monthName.string(from: month) }

    private var firstCell: Date {
        let weekday = cal.component(.weekday, from: month)
        let back = (weekday - cal.firstWeekday + 7) % 7
        return cal.date(byAdding: .day, value: -back, to: month)!
    }

    private func day(at p: NSPoint) -> Date? {
        guard p.y >= gridTop, p.x >= 0, p.x < cellW * 7 else { return nil }
        let col = Int(p.x / cellW), row = Int((p.y - gridTop) / cellH)
        guard row >= 0, row < 6 else { return nil }
        return cal.date(byAdding: .day, value: row * 7 + col, to: firstCell)
    }

    private func cell(_ i: Int) -> NSRect {
        NSRect(x: CGFloat(i % 7) * cellW, y: gridTop + CGFloat(i / 7) * cellH, width: cellW, height: cellH)
    }

    // MARK: drawing

    override func draw(_ dirty: NSRect) {
        let accent = NSColor.controlAccentColor
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let weekdayAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: NSColor.tertiaryLabelColor]
        for col in 0..<7 {
            let s = symbols[(cal.firstWeekday - 1 + col) % 7]
            let size = s.size(withAttributes: weekdayAttrs)
            s.draw(at: NSPoint(x: CGFloat(col) * cellW + (cellW - size.width) / 2, y: headerH + (weekdayH - size.height) / 2), withAttributes: weekdayAttrs)
        }
        let today = cal.startOfDay(for: Date())
        let last = lastDay
        let single = isSingleDay
        let first = firstCell
        for i in 0..<42 {
            guard let d = cal.date(byAdding: .day, value: i, to: first) else { continue }
            let r = cell(i)
            let inMonth = cal.isDate(d, equalTo: month, toGranularity: .month)
            let selected = selection.map { d >= $0.start && d < $0.end } ?? false
            let isStart = selected && selection?.start == d
            let isEnd = selected && last == d
            let circle = NSRect(x: r.midX - 13, y: r.midY - 13, width: 26, height: 26)
            if selected {
                if !single {
                    let band = NSRect(x: isStart ? r.midX : r.minX, y: circle.minY,
                                      width: isStart || isEnd ? cellW / 2 : cellW, height: circle.height)
                    accent.withAlphaComponent(0.18).setFill()
                    band.fill()
                }
                if isStart || isEnd {
                    accent.setFill()
                    NSBezierPath(ovalIn: circle).fill()
                }
            }
            let endpoint = isStart || isEnd
            let isToday = d == today
            let color: NSColor = endpoint ? .white : isToday ? accent : inMonth ? .labelColor : .tertiaryLabelColor
            let font = NSFont.systemFont(ofSize: 12, weight: isToday || endpoint ? .semibold : .regular)
            let text = String(cal.component(.day, from: d))
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let size = text.size(withAttributes: attrs)
            text.draw(at: NSPoint(x: r.midX - size.width / 2, y: r.midY - size.height / 2 - 2), withAttributes: attrs)
            if let n = counts[d], n > 0 {
                let alpha: CGFloat = n == 1 ? 0.45 : n < 4 ? 0.7 : 1
                let dot: NSColor = endpoint ? .white.withAlphaComponent(0.9) : (inMonth ? accent : NSColor.tertiaryLabelColor).withAlphaComponent(alpha)
                dot.setFill()
                NSBezierPath(ovalIn: NSRect(x: r.midX - 2, y: r.midY + 7, width: 4, height: 4)).fill()
            }
        }
    }

    // MARK: mouse

    override func mouseDown(with event: NSEvent) {
        guard let d = day(at: convert(event.locationInWindow, from: nil)) else { return }
        dragged = false
        if event.modifierFlags.contains(.shift), let s = selection, let last = lastDay {
            anchor = nil
            set(selection: days(min(s.start, d), max(last, d)), reveal: false)
            onChange?(selection)
        } else {
            anchor = d
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let a = anchor, let d = day(at: convert(event.locationInWindow, from: nil)) else { return }
        let range = days(a, d)
        if range != selection {
            dragged = true
            set(selection: range, reveal: false)
            onChange?(selection)
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { anchor = nil }
        guard let a = anchor, !dragged else { return }
        if isSingleDay, selection?.start == a {
            set(selection: nil, reveal: false)
        } else {
            set(selection: days(a, a), reveal: false)
        }
        onChange?(selection)
    }
}
