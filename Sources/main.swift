// Snotify.app - macOS notifications from the command line, under this app's own
// name and icon, with a shell command to run when a banner is clicked, an Info
// button that opens a window of Markdown the script supplied, and a history of
// every post that the same window searches.
//
// Built and installed by scripts/snotify-app.sh; called through bin/snotify,
// which is the client every script uses. Launched with --title it posts and
// exits. Launched with a subcommand (history, show, config, icons) it does that
// and exits, or opens the history window. Launched with --resident, by the
// LaunchAgent `snotify config login on` writes, it stays: menu bar item and Dock
// icon as configured, and takes the clicks. Launched with nothing, which is
// what macOS does for a click when no instance is running and what a double
// click in Finder does, it waits a moment for the click and otherwise opens
// the history window.
//
// The PATH of the caller travels inside the notification: a click arrives in a
// process started by launchd, whose PATH has no Homebrew or ~/.local/bin, and
// `tmux` or `open -a` must still resolve.
//
// Every post is a Markdown file under ~/.local/state/snotify/history with its
// metadata as frontmatter and the Info text as body (History.swift). The
// banner's Info button and the history window both read that file.

import AppKit
import UserNotifications

let usage = """
usage: snotify --title TITLE [--body BODY] [--subtitle TEXT] [--sound NAME|default]
              [--group KEY] [--on-click 'shell command']
              [--info-file PATH.md | --info-md 'markdown']
              [--from LABEL] [--icon GLYPH] [--color COLOR] [--meta KEY=VALUE]...
       snotify history [QUERY...] [--since 7d|2026-10-01] [--limit N] [--json | --paths]
       snotify show [QUERY...] [--snapshot OUT.png]
                                           open the history window; --snapshot writes it to a PNG and exits
       snotify config [KEY [VALUE]]         menubar, dock, login: on|off; retention: DAYS|forever
       snotify icons [QUERY] [--png OUT.png [--color COLOR]]
                                           search the glyph names; --png renders the first match
       snotify --show-info PATH.md [--title TITLE] [--snapshot OUT.png]

  --from    who is sending, as the history and the menu bar show it
  --icon    a Nerd Fonts name (fa-rocket, md-robot), sf:NAME for an SF Symbol,
            U+F135 for a codepoint, or one character; shown on the banner
  --color   red orange yellow green mint teal cyan blue indigo purple pink
            brown gray, or #rrggbb; the icon's colour
  --meta    anything else worth keeping with the entry, repeatable
"""

let bundleID = "org.lonkar.snotify"
let infoCategory = bundleID + ".info"
let infoAction = "info"
let stateDir = (ProcessInfo.processInfo.environment["XDG_STATE_HOME"].map { $0 + "/snotify" }
    ?? NSHomeDirectory() + "/.local/state/snotify")

enum Mode {
    case launched, post, showInfo, history, show, config, icons, resident
}

struct Options {
    var mode = Mode.launched
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
    var from: String?
    var icon: String?
    var color: String?
    var meta: [(key: String, value: String)] = []
    var query: [String] = []
    var since: String?
    var limit = 20
    var json = false
    var paths = false
    var configKey: String?
    var configValue: String?
    var png: String?
}

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(("Snotify: " + message + "\n").data(using: .utf8)!)
    exit(code)
}

func parse(_ args: [String]) -> Options {
    // No arguments means a launch by macOS for a click, or by hand.
    var args = args.filter { !$0.hasPrefix("-psn_") }
    var o = Options()
    if args.isEmpty { return o }
    switch args[0] {
    case "history": o.mode = .history; args.removeFirst()
    case "show": o.mode = .show; args.removeFirst()
    case "config": o.mode = .config; args.removeFirst()
    case "icons": o.mode = .icons; args.removeFirst()
    case "--resident": o.mode = .resident; args.removeFirst()
    default: o.mode = .post
    }
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
        case "--show-info": o.showInfo = value(a); o.mode = .showInfo
        case "--snapshot": o.snapshot = value(a)
        case "--from": o.from = value(a)
        case "--icon": o.icon = value(a)
        case "--color": o.color = value(a)
        case "--meta":
            let kv = value(a)
            guard let eq = kv.firstIndex(of: "="), eq != kv.startIndex else { fail("--meta wants KEY=VALUE, not \(kv)", code: 2) }
            o.meta.append((String(kv[..<eq]), String(kv[kv.index(after: eq)...])))
        case "--since": o.since = value(a)
        case "--limit":
            guard let n = Int(value(a)), n >= 0 else { fail("--limit wants a number", code: 2) }
            o.limit = n
        case "--json": o.json = true
        case "--paths": o.paths = true
        case "--png": o.png = value(a)
        case "-h", "--help": print(usage); exit(0)
        default:
            if a.hasPrefix("-") { fail("unknown argument \(a)\n" + usage, code: 2) }
            switch o.mode {
            case .config:
                if o.configKey == nil { o.configKey = a } else if o.configValue == nil { o.configValue = a } else { fail("config takes a key and a value, nothing more", code: 2) }
            case .history, .show, .icons: o.query.append(a)
            default: fail("unexpected argument \(a)\n" + usage, code: 2)
            }
        }
        i += 1
    }
    if o.mode == .post && o.title.isEmpty { fail("--title is required\n" + usage, code: 2) }
    if let c = o.color, parseColor(c) == nil { fail("--color \(c) is not a colour name or #rrggbb", code: 2) }
    if let s = o.icon, IconSpec(s) == nil { fail("--icon \(s) is not a glyph name, sf:NAME, U+XXXX or one character; `snotify icons QUERY` searches the names", code: 2) }
    return o
}

// Cmd-W, Cmd-C, Cmd-A, Cmd-F, Cmd-Y and Cmd-Q only work with a menu bar to
// route them, even for an app that never shows in the Dock.
func installMenu(_ delegate: Delegate) {
    let main = NSMenu()
    let appItem = NSMenuItem(); main.addItem(appItem)
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: "Quit Snotify", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appItem.submenu = appMenu
    let fileItem = NSMenuItem(); main.addItem(fileItem)
    let fileMenu = NSMenu(title: "File")
    let history = fileMenu.addItem(withTitle: "History", action: #selector(Delegate.showHistory(_:)), keyEquivalent: "y")
    history.target = delegate
    fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    fileItem.submenu = fileMenu
    let editItem = NSMenuItem(); main.addItem(editItem)
    let editMenu = NSMenu(title: "Edit")
    editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    let find = editMenu.addItem(withTitle: "Find", action: #selector(Delegate.findInHistory(_:)), keyEquivalent: "f")
    find.target = delegate
    editItem.submenu = editMenu
    NSApp.mainMenu = main
}

// MARK: - App

final class Delegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let options: Options
    var infoWindow: InfoWindow?
    var historyWindow: HistoryWindow?
    var statusItem: StatusItem?
    var responded = false
    /// Launched to stay: by the LaunchAgent, or because an icon is on.
    var residentLaunch = false
    var keepAlive: Bool { residentLaunch || Config.menubar || Config.dock }

    init(options: Options) { self.options = options }

    func applicationDidFinishLaunching(_ note: Notification) {
        let o = options
        switch o.mode {
        case .showInfo:
            let path = o.showInfo ?? ""
            openInfo(title: o.title.isEmpty ? (path as NSString).lastPathComponent : o.title, path: path, record: false)
            if let out = o.snapshot {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.infoWindow?.snapshot(to: out)
                    exit(0)
                }
            }
        case .post:
            post(o)
        case .history:
            printHistory(o)
            exit(0)
        case .icons:
            printIcons(o)
            exit(0)
        case .config:
            runConfig(o)
            exit(0)
        case .show:
            let q = o.query.joined(separator: " ")
            if let other = IPC.otherInstance() {
                IPC.post(IPC.show, ["query": q])
                other.activate(options: [])
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exit(0) }
                return
            }
            becomeResident(launched: false)
            openHistory(query: q)
            if let out = o.snapshot {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.historyWindow?.snapshot(to: out)
                    exit(0)
                }
            }
        case .resident:
            becomeResident(launched: true)
        case .launched:
            // A click launch delivers didReceive within a moment; a double
            // click in Finder or Spotlight delivers nothing, and wants the window.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self, !self.responded else { return }
                self.becomeResident(launched: false)
                self.openHistory(query: nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !keepAlive }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openHistory(query: nil)
        return false
    }

    /// Done with a one-shot job: quit unless something keeps us here.
    func finishIfTransient() {
        if !keepAlive && historyWindow == nil && infoWindow == nil { exit(0) }
    }

    // MARK: resident

    func becomeResident(launched: Bool) {
        if launched { residentLaunch = true }
        applySettings()
        IPC.observe(IPC.settings) { [weak self] _ in self?.applySettings() }
        IPC.observe(IPC.show) { [weak self] n in
            self?.openHistory(query: n.userInfo?["query"] as? String)
        }
        HistoryEntry.prune(days: Config.retentionDays)
    }

    func applySettings() {
        NSApp.setActivationPolicy(Config.dock ? .regular : .accessory)
        if Config.menubar, statusItem == nil {
            statusItem = StatusItem(app: self)
        } else if !Config.menubar, let s = statusItem {
            s.remove()
            statusItem = nil
        }
        if !keepAlive && historyWindow == nil && infoWindow == nil && options.mode == .resident {
            // Every reason to stay was switched off from elsewhere.
            exit(0)
        }
    }

    func openHistory(query: String?) {
        if historyWindow == nil {
            let w = HistoryWindow()
            w.onClose = { [weak self] in
                self?.historyWindow = nil
                self?.finishIfTransient()
            }
            historyWindow = w
        }
        historyWindow?.show(query: query)
    }

    @objc func showHistory(_ sender: Any?) { openHistory(query: nil) }

    @objc func findInHistory(_ sender: Any?) {
        openHistory(query: nil)
        historyWindow?.focusSearch()
    }

    @objc func openEntry(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        openHistory(query: nil)
        historyWindow?.select(path: path)
    }

    @objc func toggleSetting(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        let on = sender.state == .on
        if let err = Config.set(key, on ? "off" : "on") { NSLog("Snotify: %@", err) }
        applySettings()
    }

    // MARK: subcommands

    func entries(_ o: Options) -> [HistoryEntry] {
        var list = HistoryEntry.all()
        if let s = o.since {
            guard let date = HistoryEntry.since(s) else { fail("--since wants 7d, 36h, 90m or a date like 2026-10-01", code: 2) }
            list = list.filter { ($0.time ?? .distantPast) >= date }
        }
        let q = o.query.joined(separator: " ")
        if !q.isEmpty { list = list.filter { $0.matches(q) } }
        if o.limit > 0 { list = Array(list.prefix(o.limit)) }
        return list
    }

    func printHistory(_ o: Options) {
        let list = entries(o)
        if o.json {
            let data = try! JSONSerialization.data(withJSONObject: list.map { $0.json }, options: [.prettyPrinted, .sortedKeys])
            print(String(decoding: data, as: UTF8.self))
            return
        }
        if o.paths {
            for e in list { print(e.path) }
            return
        }
        if list.isEmpty {
            print(o.query.isEmpty ? "nothing in \(historyDir)" : "no match")
            return
        }
        for e in list {
            let when = e.time.map { HistoryEntry.shown.string(from: $0) } ?? String(repeating: " ", count: 16)
            let who = e.sender.padding(toLength: 18, withPad: " ", startingAt: 0)
            var line = when + "  " + who + "  " + e.title
            if let b = e["body"], !b.isEmpty { line += "  —  " + b.replacingOccurrences(of: "\n", with: " ") }
            if let c = e["outcome.clicked"], !c.isEmpty { line += "  [clicked]" }
            print(line)
        }
    }

    func printIcons(_ o: Options) {
        let q = o.query.joined(separator: " ")
        if Glyphs.fontName == nil { fail("the bundle has no Nerd Font; scripts/fetch-nerd-font.sh fetches it", code: 1) }
        if let out = o.png {
            // The query is a spec first (fa-rocket, sf:bell, U+F135, a character)
            // and a search second, so the first match of a word renders too.
            guard let icon = IconSpec(q) ?? Glyphs.search(q, limit: 1).first.flatMap({ IconSpec($0.name) }) else {
                fail("no glyph for \(q)", code: 1)
            }
            let color = o.color.flatMap(parseColor) ?? .labelColor
            guard let image = iconImage(icon, color: color, pixels: 256), writePNG(image, to: out) else { fail("cannot render \(q)", code: 1) }
            print("wrote \(out) (\(icon.spec))")
            return
        }
        let hits = Glyphs.search(q, limit: q.isEmpty ? 40 : 200)
        if hits.isEmpty { print("no glyph name contains \(q)"); return }
        for h in hits { print("\(h.char)  \(h.name)  U+\(h.code.uppercased())") }
        if q.isEmpty { print("… \(Glyphs.index.count) names; `snotify icons QUERY` narrows them") }
    }

    func runConfig(_ o: Options) {
        guard let key = o.configKey else { print(Config.describe()); return }
        guard let value = o.configValue else {
            guard let v = Config.get(key) else { fail("unknown setting \(key); the settings are \(Config.keys.joined(separator: ", "))", code: 2) }
            print(v)
            return
        }
        if let err = Config.set(key, value) { fail(err, code: 1) }
        print("\(key): \(Config.get(key) ?? value)")
    }

    // MARK: posting

    func infoBody(for o: Options) -> String {
        if let f = o.infoFile {
            if f == "-" {
                return String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
            }
            let path = (f as NSString).expandingTildeInPath
            return (try? String(contentsOfFile: path, encoding: .utf8)) ?? "The info file could not be read.\n\n`\(path)`"
        }
        return o.infoMarkdown ?? ""
    }

    func post(_ o: Options) {
        HistoryEntry.prune(days: Config.retentionDays)
        // A stable identifier makes a repeat replace the earlier banner
        // instead of stacking a second one.
        let id = o.group ?? UUID().uuidString
        var entry = HistoryEntry(path: HistoryEntry.newPath(), fields: [], body: infoBody(for: o))
        entry.set("id", id)
        entry.set("time", HistoryEntry.iso.string(from: Date()))
        entry.set("title", o.title)
        if let s = o.subtitle { entry.set("subtitle", s) }
        entry.set("body", o.body)
        if let s = o.sound { entry.set("sound", s) }
        if let g = o.group { entry.set("group", g) }
        if let c = o.onClick { entry.set("on_click", c) }
        if let f = o.from { entry.set("from", f) }
        if let i = o.icon { entry.set("icon", i) }
        if let c = o.color { entry.set("color", c) }
        for (k, v) in o.meta { entry.set("meta." + k, v) }
        for (k, v) in Sender.fields() { entry.set(k, v) }
        entry.set("status", "posting")
        entry.write()
        // The earlier banner with this group is gone from the screen now.
        if let g = o.group {
            for var old in HistoryEntry.all() where old.path != entry.path && old["group"] == g && old["outcome.replaced_by"] == nil {
                old.set("outcome.replaced_by", entry.name)
                old.write()
                break
            }
        }

        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                entry.set("status", "failed: " + error.localizedDescription); entry.write()
                fail("authorization: \(error.localizedDescription)", code: 3)
            }
            if !granted {
                entry.set("status", "failed: notifications are off for Snotify.app"); entry.write()
                fail("notifications are off for Snotify.app; turn them on in System Settings > Notifications > Snotify", code: 3)
            }
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
            info["history"] = entry.path
            info["title"] = o.title
            if !entry.body.isEmpty {
                info["info"] = entry.path
                content.categoryIdentifier = infoCategory
            }
            if let p = ProcessInfo.processInfo.environment["PATH"] { info["path"] = p }
            if let d = ProcessInfo.processInfo.environment["PWD"] { info["cwd"] = d }
            content.userInfo = info
            if let spec = o.icon, let icon = IconSpec(spec) {
                let color = o.color.flatMap(parseColor) ?? .labelColor
                let dir = NSTemporaryDirectory() + "snotify-" + UUID().uuidString
                try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                let png = dir + "/icon.png"
                if let image = iconImage(icon, color: color, pixels: 256), writePNG(image, to: png),
                   let attachment = try? UNNotificationAttachment(identifier: "icon", url: URL(fileURLWithPath: png), options: nil) {
                    content.attachments = [attachment]
                }
            }
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { error in
                if let error = error {
                    entry.set("status", "failed: " + error.localizedDescription); entry.write()
                    fail("post: \(error.localizedDescription)", code: 1)
                }
                entry.set("status", "posted"); entry.write()
                // The request is with the notification daemon once add
                // completes; a beat more lets the sound start cleanly.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { exit(0) }
            }
        }
    }

    // MARK: clicks

    func openInfo(title: String, path: String, record: Bool) {
        var markdown: String
        if var e = HistoryEntry.load(path) {
            markdown = e.body
            if record, e["outcome.info_opened"] == nil {
                e.set("outcome.info_opened", HistoryEntry.iso.string(from: Date()))
                e.write()
            }
        } else {
            markdown = (try? String(contentsOfFile: path, encoding: .utf8)) ?? "The info file is gone.\n\n`\(path)`"
        }
        if markdown.isEmpty { markdown = "_No info text came with this notification._" }
        let w = InfoWindow(title: title, markdown: markdown)
        w.onClose = { [weak self] in
            self?.infoWindow = nil
            self?.finishIfTransient()
        }
        infoWindow = w
        w.show()
    }

    func record(_ info: [AnyHashable: Any], _ key: String) {
        guard let path = info["history"] as? String, var e = HistoryEntry.load(path) else { return }
        e.set(key, HistoryEntry.iso.string(from: Date()))
        e.write()
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
            NSLog("Snotify: on-click failed: %@", error.localizedDescription)
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
                self.openInfo(title: title, path: info["info"] as? String ?? "", record: true)
            }
        case UNNotificationDefaultActionIdentifier:
            record(info, "outcome.clicked")
            runOnClick(info)
            finishIfTransient()
        case UNNotificationDismissActionIdentifier:
            record(info, "outcome.dismissed")
            finishIfTransient()
        default:
            finishIfTransient()
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
    UNNotificationCategory(identifier: infoCategory, actions: [info], intentIdentifiers: [], options: [.customDismissAction]),
])
app.setActivationPolicy(.accessory)
installMenu(delegate)
app.run()
