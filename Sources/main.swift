// Notify.app - one macOS notification from the command line, under this app's
// own name and icon, with a shell command to run when it is clicked and an
// optional Info button that opens a window of Markdown the script supplied.
//
// Built and installed by scripts/notify-app.sh; called through bin/notify,
// which is the documented interface. Launched with arguments it posts and
// exits. Launched with none, which is what macOS does when a notification of
// ours is clicked after the posting process has gone, it waits for the click
// to be delivered, acts on it, and exits.
//
// The PATH of the caller travels inside the notification: a click arrives in a
// process started by launchd, whose PATH has no Homebrew or ~/.local/bin, and
// `tmux` or `open -a` must still resolve.
//
// Info text is kept as a file under ~/.local/state/notify, not in userInfo:
// a log tail can be large and the notification store is not for that. The
// window is an NSTextView, so VoiceOver reads it, text selects, links open.

import AppKit
import UserNotifications

let usage = """
usage: Notify --title TITLE [--body BODY] [--subtitle TEXT] [--sound NAME|default]
              [--group KEY] [--on-click 'shell command']
              [--info-file PATH.md | --info-md 'markdown']
       Notify --show-info PATH.md [--title TITLE] [--snapshot OUT.png]
              open the window directly; --snapshot writes it to a PNG and exits
"""

let bundleID = "org.lonkar.notify"
let infoCategory = bundleID + ".info"
let infoAction = "info"
let stateDir = (ProcessInfo.processInfo.environment["XDG_STATE_HOME"].map { $0 + "/notify" }
    ?? NSHomeDirectory() + "/.local/state/notify")

struct Options {
    var title = ""
    var body = ""
    var subtitle: String?
    var sound: String?
    var group: String?
    var onClick: String?
    var infoFile: String?
    var infoMarkdown: String?
    var showInfo: String?
    var snapshot: String?
}

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(("Notify: " + message + "\n").data(using: .utf8)!)
    exit(code)
}

func parse(_ args: [String]) -> Options? {
    // No arguments means a launch by macOS for a click, or by hand.
    let args = args.filter { !$0.hasPrefix("-psn_") }
    if args.isEmpty { return nil }
    var o = Options()
    var i = 0
    func value(_ flag: String) -> String {
        i += 1
        guard i < args.count else { fail("\(flag) needs a value\n" + usage, code: 2) }
        return args[i]
    }
    while i < args.count {
        let a = args[i]
        switch a {
        case "--title": o.title = value(a)
        case "--body": o.body = value(a)
        case "--subtitle": o.subtitle = value(a)
        case "--sound": o.sound = value(a)
        case "--group": o.group = value(a)
        case "--on-click": o.onClick = value(a)
        case "--info-file": o.infoFile = value(a)
        case "--info-md": o.infoMarkdown = value(a)
        case "--show-info": o.showInfo = value(a)
        case "--snapshot": o.snapshot = value(a)
        case "-h", "--help": print(usage); exit(0)
        default: fail("unknown argument \(a)\n" + usage, code: 2)
        }
        i += 1
    }
    if o.title.isEmpty && o.showInfo == nil { fail("--title is required\n" + usage, code: 2) }
    return o
}

// MARK: - Markdown to attributed text

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

// MARK: - The Info window

final class InfoWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow!
    private let raw: String

    init(title: String, markdown: String) {
        raw = markdown
        super.init()
        let frame = NSRect(x: 0, y: 0, width: 600, height: 440)
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .resizable, .miniaturizable],
                          backing: .buffered, defer: false)
        window.title = title
        window.delegate = self
        window.minSize = NSSize(width: 360, height: 200)
        window.setFrameAutosaveName("NotifyInfo")

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let text = NSTextView()
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = true
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: 14, height: 12)
        text.isAutomaticLinkDetectionEnabled = true
        text.linkTextAttributes = [.foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue]
        text.autoresizingMask = [.width]
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.textContainer?.widthTracksTextView = true
        text.textStorage?.setAttributedString(styled(markdown: markdown))
        text.setAccessibilityLabel(title)
        scroll.documentView = text

        let copy = NSButton(title: "Copy", target: self, action: #selector(copyAll))
        copy.bezelStyle = .rounded
        copy.setAccessibilityLabel("Copy the whole text")
        copy.translatesAutoresizingMaskIntoConstraints = false
        let close = NSButton(title: "Close", target: window, action: #selector(NSWindow.performClose(_:)))
        close.bezelStyle = .rounded
        close.keyEquivalent = "\u{1b}"
        close.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView(frame: frame)
        content.addSubview(scroll)
        content.addSubview(copy)
        content.addSubview(close)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: copy.topAnchor, constant: -8),
            copy.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            copy.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
            close.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            close.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
        ])
        window.contentView = content
        window.center()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

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

    @objc func copyAll() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(raw, forType: .string)
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { exit(0) }
    }
}

// Cmd-W, Cmd-C, Cmd-A and Cmd-Q only work with a menu bar to route them,
// even for an app that never shows in the Dock.
func installMenu() {
    let main = NSMenu()
    let appItem = NSMenuItem(); main.addItem(appItem)
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: "Quit Notify", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appItem.submenu = appMenu
    let fileItem = NSMenuItem(); main.addItem(fileItem)
    let fileMenu = NSMenu(title: "File")
    fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    fileItem.submenu = fileMenu
    let editItem = NSMenuItem(); main.addItem(editItem)
    let editMenu = NSMenu(title: "Edit")
    editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editItem.submenu = editMenu
    NSApp.mainMenu = main
}

// MARK: - App

final class Delegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let options: Options?
    var infoWindow: InfoWindow?
    var responded = false
    init(options: Options?) { self.options = options }

    func applicationDidFinishLaunching(_ note: Notification) {
        if let o = options, let path = o.showInfo {
            openInfo(title: o.title.isEmpty ? (path as NSString).lastPathComponent : o.title, path: path)
            if let out = o.snapshot {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.infoWindow?.snapshot(to: out)
                    exit(0)
                }
            }
        } else if let o = options {
            post(o)
        } else {
            // A click launch delivers didReceive within a moment; a stray
            // double-click in Finder delivers nothing, so don't linger.
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                if self?.responded != true { exit(0) }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func infoPath(for o: Options, id: String) -> String? {
        if let f = o.infoFile {
            if f == "-" {
                let data = FileHandle.standardInput.readDataToEndOfFile()
                return write(String(decoding: data, as: UTF8.self), id: id)
            }
            return (f as NSString).expandingTildeInPath
        }
        if let md = o.infoMarkdown { return write(md, id: id) }
        return nil
    }

    func write(_ markdown: String, id: String) -> String {
        try? FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)
        prune()
        let path = stateDir + "/" + id.replacingOccurrences(of: "/", with: "_") + ".md"
        do { try markdown.write(toFile: path, atomically: true, encoding: .utf8) }
        catch { fail("cannot write \(path): \(error.localizedDescription)", code: 1) }
        return path
    }

    // Info files for notifications long dismissed: drop them after a week.
    func prune() {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: stateDir) else { return }
        let cutoff = Date().addingTimeInterval(-7 * 86400)
        for n in names where n.hasSuffix(".md") {
            let p = stateDir + "/" + n
            if let m = (try? fm.attributesOfItem(atPath: p))?[.modificationDate] as? Date, m < cutoff {
                try? fm.removeItem(atPath: p)
            }
        }
    }

    func post(_ o: Options) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error { fail("authorization: \(error.localizedDescription)", code: 3) }
            if !granted {
                fail("notifications are off for Notify.app; turn them on in System Settings > Notifications > Notify", code: 3)
            }
            // A stable identifier makes a repeat replace the earlier banner
            // instead of stacking a second one.
            let id = o.group ?? UUID().uuidString
            let content = UNMutableNotificationContent()
            content.title = o.title
            content.body = o.body
            if let s = o.subtitle { content.subtitle = s }
            if let s = o.sound {
                if s == "default" {
                    content.sound = .default
                } else {
                    // System sounds live in /System/Library/Sounds as NAME.aiff;
                    // a bare name is the usual way to say one.
                    let file = s.contains(".") ? s : s + ".aiff"
                    content.sound = UNNotificationSound(named: UNNotificationSoundName(file))
                }
            }
            if let g = o.group { content.threadIdentifier = g }
            var info: [String: String] = [:]
            if let c = o.onClick { info["command"] = c }
            if let p = self.infoPath(for: o, id: id) {
                info["info"] = p
                info["title"] = o.title
                content.categoryIdentifier = infoCategory
            }
            if let p = ProcessInfo.processInfo.environment["PATH"] { info["path"] = p }
            if let d = ProcessInfo.processInfo.environment["PWD"] { info["cwd"] = d }
            content.userInfo = info
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { error in
                if let error = error { fail("post: \(error.localizedDescription)", code: 1) }
                // The request is with the notification daemon once add
                // completes; a beat more lets the sound start cleanly.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { exit(0) }
            }
        }
    }

    func openInfo(title: String, path: String) {
        let markdown = (try? String(contentsOfFile: path, encoding: .utf8))
            ?? "The info file is gone.\n\n`\(path)`"
        infoWindow = InfoWindow(title: title, markdown: markdown)
        infoWindow?.show()
    }

    func runOnClick(_ info: [AnyHashable: Any]) {
        guard let command = info["command"] as? String, !command.isEmpty else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", command]
        var env = ProcessInfo.processInfo.environment
        if let path = info["path"] as? String { env["PATH"] = path }
        p.environment = env
        if let cwd = info["cwd"] as? String, FileManager.default.fileExists(atPath: cwd) {
            p.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            NSLog("Notify: on-click failed: %@", error.localizedDescription)
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        responded = true
        let info = response.notification.request.content.userInfo
        done()
        switch response.actionIdentifier {
        case infoAction:
            let title = info["title"] as? String ?? response.notification.request.content.title
            DispatchQueue.main.async {
                self.openInfo(title: title, path: info["info"] as? String ?? "")
            }
        case UNNotificationDefaultActionIdentifier:
            runOnClick(info)
            exit(0)
        default:
            exit(0)
        }
    }

    // Show the banner even if, improbably, this app counts as frontmost.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound])
    }
}

let options = parse(Array(CommandLine.arguments.dropFirst()))
let app = NSApplication.shared
let delegate = Delegate(options: options)
app.delegate = delegate
// The notification center's delegate must be in place before the launch
// finishes, or a click that started this process is delivered to nobody.
// Categories likewise: the Info button only exists while this app says so.
let center = UNUserNotificationCenter.current()
center.delegate = delegate
let info = UNNotificationAction(identifier: infoAction, title: "Info", options: [.foreground])
center.setNotificationCategories([
    UNNotificationCategory(identifier: infoCategory, actions: [info], intentIdentifiers: [], options: []),
])
app.setActivationPolicy(.accessory)
installMenu()
app.run()
