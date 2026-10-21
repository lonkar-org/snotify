// HistoryWindow.swift - the main window: a sidebar with the calendar, the
// senders and the outcomes, the list of entries grouped by day, and the
// selected one in full. Search is in the toolbar beside the actions. Opened
// by a double-click on Snotify.app, the menu bar item, `snotify show [QUERY]`,
// or Cmd-Y, and it reloads when the history directory changes.

import AppKit

/// The table with Return and Delete, and a right click that selects first.
final class HistoryTable: NSTableView {
    var onReturn: (() -> Void)?
    var onDelete: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: onReturn?()
        case 51, 117: onDelete?()
        default: super.keyDown(with: event)
        }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        if row >= 0, delegate?.tableView?(self, shouldSelectRow: row) ?? true {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        return super.menu(for: event)
    }
}

final class HistoryWindow: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSToolbarDelegate, NSMenuItemValidation {
    let window: NSWindow
    private let split = NSSplitViewController()
    private let sidebar = Sidebar()
    private let table = HistoryTable()
    private let detail = DetailView()
    private var search: NSSearchField?
    private var toolbarItems: [NSToolbarItem.Identifier: NSToolbarItem] = [:]
    private var all: [HistoryEntry] = []
    private var shown: [HistoryEntry] = []
    private enum Row { case day(String, Int), entry(HistoryEntry) }
    private var rows: [Row] = []
    private var filter = HistoryFilter()
    private var current: HistoryEntry?
    private var watcher: DispatchSourceFileSystemObject?
    private var reloadPending = false
    var onClose: (() -> Void)?

    private static let run = NSToolbarItem.Identifier("run")
    private static let reveal = NSToolbarItem.Identifier("reveal")
    private static let copy = NSToolbarItem.Identifier("copy")
    private static let trash = NSToolbarItem.Identifier("trash")
    private static let search = NSToolbarItem.Identifier("search")
    private static let splitAutosave = "SnotifyHistorySplit"

    override init() {
        let frame = NSRect(x: 0, y: 0, width: 1120, height: 680)
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        super.init()
        window.title = "Snotify"
        window.delegate = self
        window.minSize = NSSize(width: 860, height: 480)
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .automatic

        // sidebar
        let side = NSViewController()
        side.view = sidebar
        let sideItem = NSSplitViewItem(sidebarWithViewController: side)
        sideItem.minimumThickness = 248
        sideItem.maximumThickness = 320
        sideItem.canCollapse = true
        sidebar.onDays = { [weak self] d in self?.filter.days = d; self?.apply() }
        sidebar.onSender = { [weak self] s in self?.filter.sender = s; self?.apply() }
        sidebar.onShow = { [weak self] s in self?.filter.show = s; self?.apply() }

        // list
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("entry"))
        col.resizingMask = .autoresizingMask
        table.addTableColumn(col)
        table.headerView = nil
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.style = .inset
        table.floatsGroupRows = true
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.dataSource = self
        table.delegate = self
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = true
        table.setAccessibilityLabel("Notifications")
        table.doubleAction = #selector(runClick)
        table.target = self
        table.onReturn = { [weak self] in self?.runClick() }
        table.onDelete = { [weak self] in self?.trashEntry() }
        let menu = NSMenu()
        for (title, sel, key) in [("Run Click Command", #selector(runClick), "\r"), ("Open Info Window", #selector(openInfo), "i"),
                                  ("Reveal in Finder", #selector(revealFile), "r"), ("Copy as Markdown", #selector(copyAll), ""),
                                  ("Copy Click Command", #selector(copyCommand), ""), ("Move to Trash", #selector(trashEntry), "")] {
            if title.hasPrefix("Reveal") || title.hasPrefix("Move") { menu.addItem(.separator()) }
            let mi = menu.addItem(withTitle: title, action: sel, keyEquivalent: key)
            mi.target = self
            mi.keyEquivalentModifierMask = []
        }
        table.menu = menu
        let list = NSScrollView()
        list.documentView = table
        list.hasVerticalScroller = true
        list.borderType = .noBorder
        let listVC = NSViewController()
        listVC.view = list
        let listItem = NSSplitViewItem(contentListWithViewController: listVC)
        listItem.minimumThickness = 320
        listItem.maximumThickness = 520

        // detail
        let detailVC = NSViewController()
        detailVC.view = detail
        let detailItem = NSSplitViewItem(viewController: detailVC)
        detailItem.minimumThickness = 380
        detail.onRun = { [weak self] in self?.runClick() }
        detail.onOpenInfo = { [weak self] in self?.openInfo() }

        split.splitView.dividerStyle = .thin
        split.addSplitViewItem(sideItem)
        split.addSplitViewItem(listItem)
        split.addSplitViewItem(detailItem)
        split.splitView.autosaveName = HistoryWindow.splitAutosave
        window.contentViewController = split
        window.setContentSize(frame.size)

        let toolbar = NSToolbar(identifier: "SnotifyHistory")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar

        if !window.setFrameUsingName("NotifyHistory") { window.center() }
        window.setFrameAutosaveName("NotifyHistory")
        if UserDefaults.standard.object(forKey: "NSSplitView Subview Frames " + HistoryWindow.splitAutosave) == nil {
            DispatchQueue.main.async { [split] in
                split.splitView.setPosition(264, ofDividerAt: 0)
                split.splitView.setPosition(264 + 400, ofDividerAt: 1)
            }
        }
        reload()
        watch()
    }

    func show(query: String?) {
        if let q = query, let s = search { s.stringValue = q; filter.query = q; apply() }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if (query ?? "").isEmpty { window.makeFirstResponder(table) } else { focusSearch() }
    }

    func focusSearch() { if let s = search { window.makeFirstResponder(s) } }

    /// The window drawn by itself, toolbar included, for checking the
    /// rendering from a script. No screen capture, so no permission. Drawn
    /// in three parts: the vibrancy view under the sidebar renders nothing
    /// offscreen, so the sidebar goes on top of the content, then the
    /// titlebar with the toolbar on top of both.
    func snapshot(to path: String) {
        guard let content = window.contentView else { fail("cannot render", code: 1) }
        // Through PNG and back: a vibrant view's cached bitmap draws inverted
        // when composited directly, and encodes correctly.
        func part(_ view: NSView) -> NSImage? {
            guard !view.isHidden, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
            view.cacheDisplay(in: view.bounds, to: rep)
            return rep.representation(using: .png, properties: [:]).flatMap { NSImage(data: $0) }
        }
        func place(_ view: NSView) -> NSRect {
            var r = content.convert(view.bounds, from: view)
            if content.isFlipped { r.origin.y = content.bounds.height - r.maxY }
            return r
        }
        let image = NSImage(size: content.bounds.size)
        image.lockFocus()
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            part(content)?.draw(in: content.bounds)
            // the sidebar floats inside a margin that renders black offscreen too
            let column = place(sidebar)
            NSColor.windowBackgroundColor.setFill()
            NSRect(x: 0, y: 0, width: column.maxX + column.minX, height: content.bounds.height).fill()
            part(sidebar)?.draw(in: column)
            if let titlebar = window.standardWindowButton(.closeButton)?.superview?.superview {
                part(titlebar)?.draw(in: place(titlebar))
            }
        }
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { fail("cannot encode", code: 1) }
        do { try png.write(to: URL(fileURLWithPath: path)) }
        catch { fail("cannot write \(path): \(error.localizedDescription)", code: 1) }
    }

    /// Select one entry, clearing whatever filter hides it.
    func select(path: String) {
        if let i = rows.firstIndex(where: { if case .entry(let e) = $0 { return e.path == path } else { return false } }) {
            table.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false)
            table.scrollRowToVisible(i)
        } else if filter.query.isEmpty, filter.days == nil, filter.sender == nil, filter.show == .everything {
            return
        } else {
            search?.stringValue = ""
            filter = HistoryFilter()
            sidebar.select(days: nil)
            select(path: path)
        }
    }

    // MARK: data

    func reload() {
        all = HistoryEntry.all()
        apply()
    }

    private static let dayName: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        return f
    }()
    private static let dayNameYear: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEE d MMMM yyyy")
        return f
    }()

    private func dayLabel(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        return (cal.component(.year, from: d) == cal.component(.year, from: Date()) ? HistoryWindow.dayName : HistoryWindow.dayNameYear).string(from: d)
    }

    /// Filter, regroup, recount the facets, keep the selection if it survived.
    private func apply() {
        let selected = current?.path
        shown = all.filter { filter.matches($0) }
        rows = []
        var lastDay: Date? = nil
        var counts: [Date: Int] = [:]
        for e in shown { if let d = e.day { counts[d, default: 0] += 1 } }
        for e in shown {
            let d = e.day ?? .distantPast
            if d != lastDay {
                rows.append(.day(e.day.map(dayLabel) ?? "Undated", counts[d] ?? 0))
                lastDay = d
            }
            rows.append(.entry(e))
        }
        table.reloadData()

        // the calendar counts what the other filters leave, and so on round
        var byDay: [Date: Int] = [:]
        for e in all where filter.matchesQuery(e) && filter.matchesSender(e) && filter.show.matches(e) {
            if let d = e.day { byDay[d, default: 0] += 1 }
        }
        sidebar.calendar.counts = byDay
        var bySender: [String: Sidebar.SenderFacet] = [:]
        var total = 0
        for e in all where filter.matchesQuery(e) && filter.matchesDays(e) && filter.show.matches(e) {
            total += 1
            if var f = bySender[e.sender] {
                f.count += 1
                if f.sample.iconSpec == nil, e.iconSpec != nil { f.sample = e }
                bySender[e.sender] = f
            } else {
                bySender[e.sender] = Sidebar.SenderFacet(name: e.sender, sample: e, count: 1)
            }
        }
        if let s = filter.sender, bySender[s] == nil, let sample = all.first(where: { $0.sender == s }) {
            bySender[s] = Sidebar.SenderFacet(name: s, sample: sample, count: 0)
        }
        sidebar.setSenders(bySender.values.sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }, total: total, selected: filter.sender)
        var byShow: [HistoryFilter.Show: Int] = [:]
        for e in all where filter.matchesQuery(e) && filter.matchesDays(e) && filter.matchesSender(e) {
            for s in HistoryFilter.Show.allCases where s.matches(e) { byShow[s, default: 0] += 1 }
        }
        sidebar.setShows(byShow, selected: filter.show)

        var subtitle = shown.count == all.count ? "\(all.count) notification\(all.count == 1 ? "" : "s")" : "\(shown.count) of \(all.count)"
        if let d = filter.days { subtitle += "  ·  " + sidebar.calendar.describe(d) }
        if let s = filter.sender { subtitle += "  ·  " + s }
        if filter.show != .everything { subtitle += "  ·  " + filter.show.label.lowercased() }
        window.subtitle = subtitle

        if let p = selected, let i = rows.firstIndex(where: { if case .entry(let e) = $0 { return e.path == p } else { return false } }) {
            table.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false)
        } else if let i = rows.firstIndex(where: { if case .entry = $0 { return true } else { return false } }) {
            table.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false)
            table.scrollRowToVisible(0)
        } else {
            render(nil)
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        filter.query = search?.stringValue ?? ""
        apply()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        // Down from the search field goes to the list; Escape clears, then leaves.
        if sel == #selector(NSResponder.moveDown(_:)) { window.makeFirstResponder(table); return true }
        if sel == #selector(NSResponder.cancelOperation(_:)) {
            if !(search?.stringValue ?? "").isEmpty { search?.stringValue = ""; filter.query = ""; apply() } else { window.makeFirstResponder(table) }
            return true
        }
        return false
    }

    /// A vnode watch on the directory, so a banner posted while the window is
    /// open shows up without a reload; coalesced, since a post writes twice.
    private func watch() {
        try? FileManager.default.createDirectory(atPath: historyDir, withIntermediateDirectories: true)
        let fd = open(historyDir, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self = self, !self.reloadPending else { return }
            self.reloadPending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.reloadPending = false
                self.reload()
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    // MARK: toolbar

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, HistoryWindow.run, HistoryWindow.reveal, HistoryWindow.copy, HistoryWindow.trash, .flexibleSpace, HistoryWindow.search]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if id == HistoryWindow.search {
            let item = NSSearchToolbarItem(itemIdentifier: id)
            item.searchField.placeholderString = "Search, or from:claude, process:bash"
            item.searchField.delegate = self
            item.searchField.sendsSearchStringImmediately = true
            item.searchField.setAccessibilityLabel("Search history")
            item.preferredWidthForSearchField = 300
            search = item.searchField
            return item
        }
        let spec: [NSToolbarItem.Identifier: (String, String, Selector, String)] = [
            HistoryWindow.run: ("play.fill", "Run", #selector(runClick), "Run the command the click would have run (Return)"),
            HistoryWindow.reveal: ("folder", "Reveal", #selector(revealFile), "Reveal the Markdown file in Finder"),
            HistoryWindow.copy: ("doc.on.doc", "Copy", #selector(copyAll), "Copy the whole entry as Markdown"),
            HistoryWindow.trash: ("trash", "Trash", #selector(trashEntry), "Move the entry's file to the Trash (Delete)"),
        ]
        guard let (symbol, title, sel, tip) = spec[id] else { return nil }
        let item = NSToolbarItem(itemIdentifier: id)
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        item.label = title
        item.paletteLabel = title
        item.toolTip = tip
        item.target = self
        item.action = sel
        item.isBordered = true
        item.autovalidates = false
        item.isEnabled = false
        toolbarItems[id] = item
        return item
    }

    // MARK: table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        if case .day = rows[row] { return true } else { return false }
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if case .entry = rows[row] { return true } else { return false }
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if case .day = rows[row] { return 26 } else { return 58 }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .day(let name, let n):
            let cell = tableView.makeView(withIdentifier: DayHeaderView.identifier, owner: self) as? DayHeaderView ?? DayHeaderView()
            cell.set(name, count: n)
            return cell
        case .entry(let e):
            let cell = tableView.makeView(withIdentifier: EntryRowView.identifier, owner: self) as? EntryRowView ?? EntryRowView()
            cell.set(e)
            return cell
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = table.selectedRow
        if row >= 0, case .entry(let e) = rows[row] { render(e) } else { render(nil) }
    }

    private func render(_ e: HistoryEntry?) {
        current = e
        let placeholder = all.isEmpty ? "Nothing has been posted yet." : shown.isEmpty ? "No match." : "Select a notification."
        detail.render(e, placeholder: placeholder)
        let hasCommand = !(e?["on_click"] ?? "").isEmpty
        toolbarItems[HistoryWindow.run]?.isEnabled = hasCommand
        toolbarItems[HistoryWindow.reveal]?.isEnabled = e != nil
        toolbarItems[HistoryWindow.copy]?.isEnabled = e != nil
        toolbarItems[HistoryWindow.trash]?.isEnabled = e != nil
    }

    // MARK: actions

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(runClick), #selector(copyCommand): return !(current?["on_click"] ?? "").isEmpty
        case #selector(openInfo): return current?.hasInfo ?? false
        case #selector(revealFile), #selector(copyAll), #selector(trashEntry): return current != nil
        default: return true
        }
    }

    @objc func runClick() {
        guard let e = current, let command = e["on_click"], !command.isEmpty else { return }
        // The banner's click had the caller's PATH; this one has ours, which is
        // launchd's, so the usual places go on it.
        var env = ProcessInfo.processInfo.environment
        let extra = ["/opt/homebrew/bin", "/usr/local/bin", NSHomeDirectory() + "/.local/bin"]
        env["PATH"] = (extra + [(env["PATH"] ?? "/usr/bin:/bin")]).joined(separator: ":")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", command]
        p.environment = env
        if let cwd = e["sender.cwd"], FileManager.default.fileExists(atPath: cwd) { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        do { try p.run() } catch { NSLog("Snotify: on-click failed: %@", error.localizedDescription) }
    }

    @objc func openInfo() {
        guard let e = current, e.hasInfo, let app = NSApp.delegate as? Delegate else { return }
        app.openInfo(title: e.title.isEmpty ? e.name : e.title, path: e.path, record: false)
    }

    @objc func revealFile() {
        guard let e = current else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: e.path)])
    }

    @objc func copyAll() {
        guard let e = current else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(e.render(), forType: .string)
    }

    @objc func copyCommand() {
        guard let c = current?["on_click"], !c.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(c, forType: .string)
    }

    /// To the Trash, so a slip is undone from Finder; the watcher reloads.
    @objc func trashEntry() {
        guard let e = current else { return }
        let row = table.selectedRow
        NSWorkspace.shared.recycle([URL(fileURLWithPath: e.path)]) { [weak self] _, error in
            if let error = error { NSLog("Snotify: cannot trash %@: %@", e.path, error.localizedDescription); return }
            guard let self = self else { return }
            self.current = nil
            self.reload()
            let next = min(row, self.rows.count - 1)
            if next >= 0, case .entry = self.rows[next] {
                self.table.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
            }
        }
    }

    @objc func showToday() { sidebar.select(days: sidebar.calendar.days(Calendar.current.startOfDay(for: Date()), Calendar.current.startOfDay(for: Date()))) }
    @objc func showAllDays() { sidebar.select(days: nil) }
    @objc func previousMonth() { sidebar.stepMonth(-1) }
    @objc func nextMonth() { sidebar.stepMonth(1) }

    func windowWillClose(_ notification: Notification) {
        watcher?.cancel()
        watcher = nil
        onClose?()
    }
}
