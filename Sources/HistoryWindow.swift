// HistoryWindow.swift - the main window: a search field over every history
// entry, a list of them, and the selected one rendered in full. Opened by a
// double-click on Snotify.app, the menu bar item, `snotify show [QUERY]`, or
// Cmd-Y, and it reloads when the history directory changes.

import AppKit

final class HistoryWindow: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    let window: NSWindow
    private let search = NSSearchField()
    private let table = NSTableView()
    private let detail = NSTextView()
    private let count = NSTextField(labelWithString: "")
    private let run = NSButton(title: "Run Click Command", target: nil, action: nil)
    private let reveal = NSButton(title: "Reveal in Finder", target: nil, action: nil)
    private let copy = NSButton(title: "Copy", target: nil, action: nil)
    private var all: [HistoryEntry] = []
    private var shown: [HistoryEntry] = []
    private var watcher: DispatchSourceFileSystemObject?
    private var reloadPending = false
    var onClose: (() -> Void)?

    override init() {
        let frame = NSRect(x: 0, y: 0, width: 900, height: 560)
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .resizable, .miniaturizable],
                          backing: .buffered, defer: false)
        super.init()
        window.title = "Snotify History"
        window.delegate = self
        window.minSize = NSSize(width: 600, height: 320)
        window.setFrameAutosaveName("NotifyHistory")

        search.placeholderString = "Search title, body, sender, from:claude, process:bash…"
        search.delegate = self
        search.target = self
        search.action = #selector(filter)
        search.sendsSearchStringImmediately = true
        search.setAccessibilityLabel("Search history")
        search.translatesAutoresizingMaskIntoConstraints = false

        count.font = NSFont.systemFont(ofSize: 11)
        count.textColor = .secondaryLabelColor
        count.alignment = .right
        count.translatesAutoresizingMaskIntoConstraints = false

        for (id, title, width) in [("icon", "", 28), ("time", "When", 112), ("from", "From", 110), ("title", "Title", 200)] {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.title = title
            col.width = CGFloat(width)
            col.minWidth = id == "icon" ? 28 : 60
            if id == "icon" { col.maxWidth = 28 }
            table.addTableColumn(col)
        }
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.dataSource = self
        table.delegate = self
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = false
        table.rowHeight = 22
        table.setAccessibilityLabel("Notifications")
        table.doubleAction = #selector(runClick)
        table.target = self
        let list = NSScrollView()
        list.documentView = table
        list.hasVerticalScroller = true
        list.borderType = .noBorder
        list.translatesAutoresizingMaskIntoConstraints = false

        detail.isEditable = false
        detail.isSelectable = true
        detail.isRichText = true
        detail.drawsBackground = false
        detail.textContainerInset = NSSize(width: 14, height: 12)
        detail.isAutomaticLinkDetectionEnabled = true
        detail.linkTextAttributes = [.foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue]
        detail.autoresizingMask = [.width]
        detail.isVerticallyResizable = true
        detail.isHorizontallyResizable = false
        detail.textContainer?.widthTracksTextView = true
        detail.setAccessibilityLabel("Selected notification")
        let text = NSScrollView()
        text.documentView = detail
        text.hasVerticalScroller = true
        text.borderType = .noBorder
        text.translatesAutoresizingMaskIntoConstraints = false

        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.addArrangedSubview(list)
        split.addArrangedSubview(text)
        split.setHoldingPriority(.defaultLow + 1, forSubviewAt: 0)
        split.translatesAutoresizingMaskIntoConstraints = false

        for (b, sel, label) in [(run, #selector(runClick), "Run the command the click would have run"),
                                (reveal, #selector(revealFile), "Reveal the Markdown file in Finder"),
                                (copy, #selector(copyAll), "Copy the whole entry as Markdown")] {
            b.target = self
            b.action = sel
            b.bezelStyle = .rounded
            b.isEnabled = false
            b.setAccessibilityLabel(label)
            b.translatesAutoresizingMaskIntoConstraints = false
        }
        let close = NSButton(title: "Close", target: window, action: #selector(NSWindow.performClose(_:)))
        close.bezelStyle = .rounded
        close.keyEquivalent = "\u{1b}"
        close.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView(frame: frame)
        for v in [search, count, split, run, reveal, copy, close] { content.addSubview(v) }
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            search.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            search.trailingAnchor.constraint(equalTo: count.leadingAnchor, constant: -10),
            count.centerYAnchor.constraint(equalTo: search.centerYAnchor),
            count.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            count.widthAnchor.constraint(greaterThanOrEqualToConstant: 90),
            split.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 10),
            split.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            split.bottomAnchor.constraint(equalTo: run.topAnchor, constant: -8),
            run.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            run.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
            reveal.leadingAnchor.constraint(equalTo: run.trailingAnchor, constant: 8),
            reveal.bottomAnchor.constraint(equalTo: run.bottomAnchor),
            copy.leadingAnchor.constraint(equalTo: reveal.trailingAnchor, constant: 8),
            copy.bottomAnchor.constraint(equalTo: run.bottomAnchor),
            close.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            close.bottomAnchor.constraint(equalTo: run.bottomAnchor),
        ])
        window.contentView = content
        window.center()
        window.initialFirstResponder = search
        DispatchQueue.main.async { split.setPosition(470, ofDividerAt: 0) }
        reload()
        watch()
    }

    func show(query: String?) {
        if let q = query { search.stringValue = q; filter() }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(search)
    }

    func focusSearch() { window.makeFirstResponder(search) }

    // The window drawn by itself, for checking the rendering from a script.
    // No screen capture is involved, so no Screen Recording permission.
    func snapshot(to path: String) {
        guard let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fail("cannot render", code: 1) }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { fail("cannot encode", code: 1) }
        do { try png.write(to: URL(fileURLWithPath: path)) }
        catch { fail("cannot write \(path): \(error.localizedDescription)", code: 1) }
    }

    func select(path: String) {
        if let i = shown.firstIndex(where: { $0.path == path }) {
            table.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false)
            table.scrollRowToVisible(i)
        } else if !search.stringValue.isEmpty {
            search.stringValue = ""
            filter()
            select(path: path)
        }
    }

    // MARK: data

    func reload() {
        let selected = table.selectedRow >= 0 && table.selectedRow < shown.count ? shown[table.selectedRow].path : nil
        all = HistoryEntry.all()
        filter()
        if let p = selected { select(path: p) }
    }

    @objc func filter() {
        let q = search.stringValue
        shown = q.isEmpty ? all : all.filter { $0.matches(q) }
        table.reloadData()
        count.stringValue = shown.count == all.count ? "\(all.count)" : "\(shown.count) of \(all.count)"
        if shown.isEmpty { render(nil) } else if table.selectedRow < 0 { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
    }

    func controlTextDidChange(_ obj: Notification) { filter() }

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

    // MARK: table

    func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let col = tableColumn, row < shown.count else { return nil }
        let e = shown[row]
        let id = col.identifier.rawValue
        if id == "icon" {
            let cell = tableView.makeView(withIdentifier: col.identifier, owner: self) as? NSTableCellView ?? {
                let c = NSTableCellView()
                c.identifier = col.identifier
                let iv = NSImageView()
                iv.translatesAutoresizingMaskIntoConstraints = false
                c.addSubview(iv)
                c.imageView = iv
                NSLayoutConstraint.activate([
                    iv.centerXAnchor.constraint(equalTo: c.centerXAnchor),
                    iv.centerYAnchor.constraint(equalTo: c.centerYAnchor),
                    iv.widthAnchor.constraint(equalToConstant: 18),
                    iv.heightAnchor.constraint(equalToConstant: 18),
                ])
                return c
            }()
            if let spec = e["icon"], let icon = IconSpec(spec) {
                let color = e["color"].flatMap(parseColor) ?? .labelColor
                cell.imageView?.image = iconImage(icon, color: color, pixels: 36)
                cell.imageView?.setAccessibilityLabel(spec)
            } else {
                cell.imageView?.image = nil
            }
            return cell
        }
        let cell = tableView.makeView(withIdentifier: col.identifier, owner: self) as? NSTableCellView ?? {
            let c = NSTableCellView()
            c.identifier = col.identifier
            let tf = NSTextField(labelWithString: "")
            tf.lineBreakMode = .byTruncatingTail
            tf.translatesAutoresizingMaskIntoConstraints = false
            c.addSubview(tf)
            c.textField = tf
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 2),
                tf.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -2),
                tf.centerYAnchor.constraint(equalTo: c.centerYAnchor),
            ])
            return c
        }()
        switch id {
        case "time":
            cell.textField?.stringValue = e.time.map { HistoryEntry.shown.string(from: $0) } ?? ""
            cell.textField?.textColor = .secondaryLabelColor
        case "from":
            cell.textField?.stringValue = e.sender
        default:
            let body = e["body"] ?? ""
            cell.textField?.stringValue = body.isEmpty ? e.title : e.title + "  —  " + body.replacingOccurrences(of: "\n", with: " ")
            cell.textField?.toolTip = body
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = table.selectedRow
        render(row >= 0 && row < shown.count ? shown[row] : nil)
    }

    private var current: HistoryEntry?

    private func render(_ e: HistoryEntry?) {
        current = e
        guard let e = e else {
            detail.textStorage?.setAttributedString(NSAttributedString(string: all.isEmpty ? "Nothing has been posted yet." : "No match.",
                attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.secondaryLabelColor]))
            run.isEnabled = false; reveal.isEnabled = false; copy.isEnabled = false
            return
        }
        detail.textStorage?.setAttributedString(styled(markdown: e.markdown))
        detail.scroll(.zero)
        run.isEnabled = !(e["on_click"] ?? "").isEmpty
        reveal.isEnabled = true
        copy.isEnabled = true
    }

    // MARK: actions

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

    func windowWillClose(_ notification: Notification) {
        watcher?.cancel()
        watcher = nil
        onClose?()
    }
}
