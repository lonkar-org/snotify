// Resident.swift - what keeps Notify running between banners, when asked to:
// the settings (menu bar icon, Dock icon, launch at login, retention), the
// LaunchAgent that starts it at login, the menu bar item, and the two
// distributed notifications a transient `notify show` or `notify config` uses
// to reach the instance already running.
//
// Posting stays post-and-exit whether or not an instance is resident; macOS
// delivers a click to the running instance when there is one, and launches a
// fresh one otherwise, which is the same code either way.

import AppKit

enum Config {
    /// NOTIFY_DEFAULTS_SUITE moves the settings to another domain, so a test
    /// run leaves the real ones alone.
    static let defaults: UserDefaults = {
        if let suite = ProcessInfo.processInfo.environment["NOTIFY_DEFAULTS_SUITE"], let d = UserDefaults(suiteName: suite) { return d }
        return .standard
    }()
    static var menubar: Bool {
        get { defaults.bool(forKey: "menubar") }
        set { defaults.set(newValue, forKey: "menubar") }
    }
    static var dock: Bool {
        get { defaults.bool(forKey: "dock") }
        set { defaults.set(newValue, forKey: "dock") }
    }
    static var retentionDays: Int {
        get { defaults.object(forKey: "retention") == nil ? 90 : defaults.integer(forKey: "retention") }
        set { defaults.set(newValue, forKey: "retention") }
    }
    static var login: Bool { LoginAgent.installed }

    static let keys = ["menubar", "dock", "login", "retention"]

    static func get(_ key: String) -> String? {
        switch key {
        case "menubar": return menubar ? "on" : "off"
        case "dock": return dock ? "on" : "off"
        case "login": return login ? "on" : "off"
        case "retention": return retentionDays == 0 ? "forever" : "\(retentionDays)"
        default: return nil
        }
    }

    static func describe() -> String {
        keys.map { "\($0): \(get($0) ?? "")" }.joined(separator: "\n")
    }

    /// Returns an error message, or nil when set.
    static func set(_ key: String, _ value: String) -> String? {
        func onOff() -> Bool? {
            switch value.lowercased() {
            case "on", "true", "yes", "1": return true
            case "off", "false", "no", "0": return false
            default: return nil
            }
        }
        switch key {
        case "menubar", "dock":
            guard let b = onOff() else { return "\(key) wants on or off, not \(value)" }
            if key == "menubar" { menubar = b } else { dock = b }
        case "login":
            guard let b = onOff() else { return "login wants on or off, not \(value)" }
            if let err = b ? LoginAgent.install() : LoginAgent.remove() { return err }
        case "retention":
            if value == "forever" || value == "0" { retentionDays = 0 }
            else if let n = Int(value.hasSuffix("d") ? String(value.dropLast()) : value), n > 0 { retentionDays = n }
            else { return "retention wants a number of days, or forever, not \(value)" }
        default:
            return "unknown setting \(key); the settings are \(keys.joined(separator: ", "))"
        }
        defaults.synchronize()
        IPC.post(IPC.settings)
        return nil
    }
}

/// ~/Library/LaunchAgents/org.lonkar.notify.plist runs this very binary with
/// --resident at login. A plist rather than SMAppService so the install is a
/// file anyone can read and `launchctl print gui/$UID/org.lonkar.notify` says
/// what state it is in.
enum LoginAgent {
    static let label = bundleID
    static var plistPath: String { NSHomeDirectory() + "/Library/LaunchAgents/" + label + ".plist" }
    static var installed: Bool { FileManager.default.fileExists(atPath: plistPath) }
    static var domain: String { "gui/\(getuid())" }

    static func install() -> String? {
        guard let exec = Bundle.main.executablePath else { return "cannot find this app's executable" }
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [exec, "--resident"],
            "RunAtLoad": true,
            "ProcessType": "Interactive",
        ]
        do {
            try FileManager.default.createDirectory(atPath: (plistPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: URL(fileURLWithPath: plistPath))
        } catch {
            return "cannot write \(plistPath): \(error.localizedDescription)"
        }
        _ = launchctl(["bootout", domain + "/" + label])
        let status = launchctl(["bootstrap", domain, plistPath])
        // 5 is "already loaded" (EIO from launchctl), which is where we wanted to be.
        if status != 0 && status != 5 && status != 37 { return "launchctl bootstrap exited \(status); the agent is written and loads at the next login" }
        return nil
    }

    static func remove() -> String? {
        _ = launchctl(["bootout", domain + "/" + label])
        if installed {
            do { try FileManager.default.removeItem(atPath: plistPath) }
            catch { return "cannot remove \(plistPath): \(error.localizedDescription)" }
        }
        return nil
    }

    static func launchctl(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}

enum IPC {
    static let show = Notification.Name(bundleID + ".show")
    static let settings = Notification.Name(bundleID + ".settings")

    /// Another instance of this bundle, if one is running: the resident one.
    static func otherInstance() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first { $0.processIdentifier != getpid() }
    }

    static func post(_ name: Notification.Name, _ info: [String: String] = [:]) {
        DistributedNotificationCenter.default().postNotificationName(name, object: nil, userInfo: info, deliverImmediately: true)
    }

    static func observe(_ name: Notification.Name, _ handler: @escaping (Notification) -> Void) {
        DistributedNotificationCenter.default().addObserver(forName: name, object: nil, queue: .main, using: handler)
    }
}

// MARK: - The menu bar item

final class StatusItem: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let menu = NSMenu()
    private unowned let app: Delegate
    private let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    init(app: Delegate) {
        self.app = app
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "bell", accessibilityDescription: "Notify")
            button.image?.isTemplate = true
            button.setAccessibilityLabel("Notify")
        }
        menu.delegate = self
        item.menu = menu
    }

    func remove() { NSStatusBar.system.removeStatusItem(item) }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let history = NSMenuItem(title: "History…", action: #selector(Delegate.showHistory(_:)), keyEquivalent: "y")
        history.target = app
        menu.addItem(history)
        menu.addItem(.separator())
        let recent = Array(HistoryEntry.all().prefix(8))
        if recent.isEmpty {
            let none = NSMenuItem(title: "No notifications yet", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        }
        for e in recent {
            let when = e.time.map { relative.localizedString(for: $0, relativeTo: Date()) } ?? ""
            let title = [e.title, when].filter { !$0.isEmpty }.joined(separator: "   ")
            let mi = NSMenuItem(title: title, action: #selector(Delegate.openEntry(_:)), keyEquivalent: "")
            mi.target = app
            mi.representedObject = e.path
            if let spec = e["icon"], let icon = IconSpec(spec) {
                let color = e["color"].flatMap(parseColor) ?? .labelColor
                mi.image = iconImage(icon, color: color, pixels: 32)
                mi.image?.size = NSSize(width: 16, height: 16)
            }
            if let b = e["body"], !b.isEmpty { mi.toolTip = b }
            menu.addItem(mi)
        }
        menu.addItem(.separator())
        for (title, key, on) in [("Show in Dock", "dock", Config.dock), ("Show in Menu Bar", "menubar", Config.menubar), ("Launch at Login", "login", Config.login)] {
            let mi = NSMenuItem(title: title, action: #selector(Delegate.toggleSetting(_:)), keyEquivalent: "")
            mi.target = app
            mi.representedObject = key
            mi.state = on ? .on : .off
            menu.addItem(mi)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Notify", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }
}
