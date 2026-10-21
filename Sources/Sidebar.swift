// Sidebar.swift - the history window's left pane: the calendar with the quick
// ranges under it, then every sender with its glyph and count, then the
// outcomes. Each is a filter and the counts are what the other filters leave,
// so the sidebar is also the summary.

import AppKit

final class Sidebar: NSView {
    let calendar = CalendarView()
    private let ranges = NSSegmentedControl(labels: ["All", "Today", "7 days", "30 days"], trackingMode: .selectOne, target: nil, action: nil)
    private let caption = NSTextField(labelWithString: "")
    private let senders = NSStackView()
    private let shows = NSStackView()
    private let stack = FillStack()
    var onDays: ((DateInterval?) -> Void)?
    var onSender: ((String?) -> Void)?
    var onShow: ((HistoryFilter.Show) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 16, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let doc = Flipped()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(stack)
        scroll.documentView = doc

        calendar.translatesAutoresizingMaskIntoConstraints = false
        calendar.onChange = { [weak self] s in
            guard let self = self else { return }
            self.ranges.selectedSegment = self.segment(for: s)
            self.caption.stringValue = self.calendar.describe(s)
            self.onDays?(s)
        }
        ranges.segmentStyle = .capsule
        ranges.controlSize = .small
        ranges.font = NSFont.systemFont(ofSize: 11)
        ranges.target = self
        ranges.action = #selector(pickRange)
        ranges.selectedSegment = 0
        ranges.setAccessibilityLabel("Quick ranges")
        caption.font = NSFont.systemFont(ofSize: 11)
        caption.textColor = .secondaryLabelColor
        caption.lineBreakMode = .byTruncatingTail
        caption.stringValue = calendar.describe(nil)
        for s in [senders, shows] {
            s.orientation = .vertical
            s.alignment = .leading
            s.spacing = 1
        }
        let center = NSView()
        center.addSubview(calendar)
        NSLayoutConstraint.activate([
            calendar.centerXAnchor.constraint(equalTo: center.centerXAnchor),
            calendar.topAnchor.constraint(equalTo: center.topAnchor),
            calendar.bottomAnchor.constraint(equalTo: center.bottomAnchor),
        ])
        stack.addArrangedSubview(center)
        stack.addArrangedSubview(ranges)
        stack.addArrangedSubview(caption)
        stack.setCustomSpacing(18, after: caption)
        stack.addArrangedSubview(heading("Senders"))
        stack.addArrangedSubview(senders)
        stack.setCustomSpacing(18, after: senders)
        stack.addArrangedSubview(heading("Show"))
        stack.addArrangedSubview(shows)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.topAnchor.constraint(equalTo: doc.topAnchor), stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor), stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private final class Flipped: NSView { override var isFlipped: Bool { true } }

    private func heading(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s.uppercased())
        l.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        l.textColor = .secondaryLabelColor
        return l
    }

    // MARK: days

    private func quick(_ segment: Int) -> DateInterval? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        switch segment {
        case 1: return calendar.days(today, today)
        case 2: return calendar.days(cal.date(byAdding: .day, value: -6, to: today)!, today)
        case 3: return calendar.days(cal.date(byAdding: .day, value: -29, to: today)!, today)
        default: return nil
        }
    }

    private func segment(for s: DateInterval?) -> Int {
        for i in 0..<4 where quick(i) == s { return i }
        return -1
    }

    @objc private func pickRange() { select(days: quick(ranges.selectedSegment)) }

    /// Set from outside (the menu, `select(path:)`): the calendar, the
    /// segments and the caption follow, and the owner is told.
    func select(days: DateInterval?) {
        calendar.set(selection: days)
        ranges.selectedSegment = segment(for: days)
        caption.stringValue = calendar.describe(days)
        onDays?(days)
    }

    func stepMonth(_ n: Int) { calendar.perform(n < 0 ? #selector(CalendarView.previousMonth) : #selector(CalendarView.nextMonth)) }

    // MARK: senders and outcomes

    struct SenderFacet { var name: String; var sample: HistoryEntry; var count: Int }

    func setSenders(_ facets: [SenderFacet], total: Int, selected: String?) {
        for v in senders.arrangedSubviews { v.removeFromSuperview() }
        let all = SidebarRow(title: "All senders", symbol: "tray.2", count: total)
        all.isSelected = selected == nil
        all.onClick = { [weak self] in self?.onSender?(nil) }
        senders.addArrangedSubview(all)
        for f in facets {
            let row = SidebarRow(title: f.name, entry: f.sample, count: f.count)
            row.isSelected = selected == f.name
            row.onClick = { [weak self] in self?.onSender?(f.name) }
            senders.addArrangedSubview(row)
            row.trailingAnchor.constraint(equalTo: senders.trailingAnchor).isActive = true
        }
        all.trailingAnchor.constraint(equalTo: senders.trailingAnchor).isActive = true
    }

    func setShows(_ counts: [HistoryFilter.Show: Int], selected: HistoryFilter.Show) {
        for v in shows.arrangedSubviews { v.removeFromSuperview() }
        for s in HistoryFilter.Show.allCases {
            let n = counts[s] ?? 0
            if n == 0 && s != .everything && s != selected { continue }
            let row = SidebarRow(title: s.label, symbol: s.symbol, count: n)
            row.isSelected = s == selected
            row.onClick = { [weak self] in self?.onShow?(s) }
            shows.addArrangedSubview(row)
            row.trailingAnchor.constraint(equalTo: shows.trailingAnchor).isActive = true
        }
    }
}
