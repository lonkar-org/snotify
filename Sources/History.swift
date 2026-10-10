// History.swift - one Markdown file per notification under
// $XDG_STATE_HOME/snotify/history: YAML frontmatter with everything known about
// the post (when, what, who sent it, from where, what happened to it after),
// then the Info Markdown as the body. The file is the Info file too, so nothing
// is kept twice, and `rg` over the directory is already a search.
//
// The frontmatter is one level deep: `sender:` and `terminal:` and `outcome:`
// group their fields under two-space indents, and every value is a double-quoted
// string with \ " and newlines escaped, so a parser the size of the one below
// reads it back without a YAML library and any YAML reader agrees with it.
//
// Files are named by local time to the millisecond plus six random hex digits,
// 2026-10-10T19-08-33.512-3fa9c1.md, so a directory listing is chronological
// (two posts in one second included) and retention is a string comparison on
// the name.

import AppKit
import Darwin

let historyDir = stateDir + "/history"

struct HistoryEntry {
    var path: String
    var fields: [(key: String, value: String)]
    var body: String

    subscript(_ key: String) -> String? { fields.first { $0.key == key }?.value }
    var id: String { self["id"] ?? "" }
    var title: String { self["title"] ?? "" }
    var name: String { (path as NSString).lastPathComponent }
    var time: Date? { self["time"].flatMap { HistoryEntry.iso.date(from: $0) } }
    /// Who to show as the sender: the explicit label, else the process name.
    var sender: String { self["from"] ?? self["sender.process"] ?? "" }

    mutating func set(_ key: String, _ value: String) {
        if let i = fields.firstIndex(where: { $0.key == key }) { fields[i].value = value } else { fields.append((key, value)) }
    }

    // MARK: time

    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = .current
        return f
    }()
    static let fileStamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH-mm-ss.SSS"
        return f
    }()
    static let shown: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    // MARK: files

    static func newPath(at date: Date = Date()) -> String {
        let hex = String(format: "%06x", UInt32.random(in: 0...0xFFFFFF))
        return historyDir + "/" + fileStamp.string(from: date) + "-" + hex + ".md"
    }

    static func load(_ path: String) -> HistoryEntry? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return parse(text, path: path)
    }

    /// Every entry, newest first.
    static func all() -> [HistoryEntry] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: historyDir) else { return [] }
        return names.filter { $0.hasSuffix(".md") }.sorted(by: >).compactMap { load(historyDir + "/" + $0) }
    }

    func write() {
        try? FileManager.default.createDirectory(atPath: historyDir, withIntermediateDirectories: true)
        do { try render().write(toFile: path, atomically: true, encoding: .utf8) }
        catch { NSLog("Snotify: cannot write %@: %@", path, error.localizedDescription) }
    }

    /// Drop entries older than `days`; 0 keeps everything. Compares the name's
    /// timestamp, since appending an outcome changes the modification date.
    static func prune(days: Int) {
        guard days > 0 else { return }
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: historyDir) else { return }
        let cutoff = fileStamp.string(from: Date().addingTimeInterval(-Double(days) * 86400))
        for n in names where n.hasSuffix(".md") && n < cutoff {
            try? fm.removeItem(atPath: historyDir + "/" + n)
        }
    }

    // MARK: frontmatter

    static func quote(_ s: String) -> String {
        var out = "\""
        for ch in s.unicodeScalars {
            switch ch {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": continue
            default: out.unicodeScalars.append(ch)
            }
        }
        return out + "\""
    }

    static func unquote(_ s: String) -> String {
        guard s.hasPrefix("\""), s.hasSuffix("\""), s.count >= 2 else { return s }
        var out = ""
        var escaped = false
        for ch in s.dropFirst().dropLast() {
            if escaped {
                switch ch {
                case "n": out.append("\n")
                case "t": out.append("\t")
                default: out.append(ch)
                }
                escaped = false
            } else if ch == "\\" {
                escaped = true
            } else {
                out.append(ch)
            }
        }
        return out
    }

    func render() -> String {
        var out = "---\n"
        var emitted = Set<String>()
        for (key, value) in fields {
            if let dot = key.firstIndex(of: ".") {
                let prefix = String(key[..<dot])
                if emitted.contains(prefix) { continue }
                emitted.insert(prefix)
                out += prefix + ":\n"
                for (k, v) in fields where k.hasPrefix(prefix + ".") {
                    out += "  " + String(k.dropFirst(prefix.count + 1)) + ": " + HistoryEntry.quote(v) + "\n"
                }
            } else {
                out += key + ": " + HistoryEntry.quote(value) + "\n"
            }
        }
        out += "---\n"
        if !body.isEmpty {
            out += "\n" + body
            if !body.hasSuffix("\n") { out += "\n" }
        }
        return out
    }

    static func parse(_ text: String, path: String) -> HistoryEntry? {
        let lines = text.components(separatedBy: "\n")
        guard lines.first == "---" else { return nil }
        var fields: [(key: String, value: String)] = []
        var prefix = ""
        var i = 1
        func split(_ line: Substring) -> (String, String) {
            if let r = line.range(of: ": ") {
                return (String(line[..<r.lowerBound]), String(line[r.upperBound...]))
            }
            if line.hasSuffix(":") { return (String(line.dropLast()), "") }
            return (String(line), "")
        }
        while i < lines.count, lines[i] != "---" {
            let line = lines[i]
            i += 1
            if line.hasPrefix("  ") {
                let (k, v) = split(line.dropFirst(2))
                fields.append((prefix + "." + k, unquote(v)))
            } else {
                let (k, v) = split(Substring(line))
                if v.isEmpty { prefix = k } else { fields.append((k, unquote(v))) }
            }
        }
        guard i < lines.count else { return nil }
        var rest = lines[(i + 1)...]
        if rest.first == "" { rest = rest.dropFirst() }
        return HistoryEntry(path: path, fields: fields, body: rest.joined(separator: "\n"))
    }

    // MARK: search

    var searchText: String {
        (fields.map { $0.key + ": " + $0.value } + [body]).joined(separator: "\n").lowercased()
    }

    /// Every word must match somewhere; `key:text` matches one field, where the
    /// key is the full dotted key or its last part (`process:bash`).
    func matches(_ query: String) -> Bool {
        let words = query.lowercased().split(separator: " ").map(String.init)
        if words.isEmpty { return true }
        let text = searchText
        return words.allSatisfy { w in
            if let c = w.firstIndex(of: ":"), c != w.startIndex, w.index(after: c) != w.endIndex {
                let k = String(w[..<c]), v = String(w[w.index(after: c)...])
                let keyed = fields.filter { $0.key == k || $0.key.hasSuffix("." + k) }
                // A key that exists is searched alone; `https:...` and the like
                // fall through to the whole text.
                if !keyed.isEmpty { return keyed.contains { $0.value.lowercased().contains(v) } }
            }
            return text.contains(w)
        }
    }

    /// `7d`, `36h`, `90m`, or a date `2026-10-01`.
    static func since(_ spec: String) -> Date? {
        if let n = Double(spec.dropLast()) {
            switch spec.last {
            case "d": return Date().addingTimeInterval(-n * 86400)
            case "h": return Date().addingTimeInterval(-n * 3600)
            case "m": return Date().addingTimeInterval(-n * 60)
            default: break
            }
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: spec)
    }

    /// The entry as a dictionary for --json: the fields flat, then the body.
    var json: [String: Any] {
        var d: [String: Any] = ["path": path, "body": body]
        for (k, v) in fields { d[k] = v }
        return d
    }

    /// The whole entry as Markdown for the history window: title, the body text
    /// of the banner, a table of everything else, then the Info Markdown.
    var markdown: String {
        var md = "# " + (title.isEmpty ? name : title) + "\n\n"
        if let s = self["subtitle"], !s.isEmpty { md += "**" + s + "**\n\n" }
        if let b = self["body"], !b.isEmpty { md += b + "\n\n" }
        md += "| | |\n|---|---|\n"
        let skip: Set<String> = ["title", "subtitle", "body"]
        for (k, v) in fields where !skip.contains(k) && !v.isEmpty {
            md += "| " + k + " | " + v.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ") + " |\n"
        }
        if !body.isEmpty { md += "\n---\n\n" + body }
        return md
    }
}

// MARK: - Who sent it

/// What the kernel knows about the process that ran `snotify`: this app is
/// exec'd by the bin/snotify wrapper, so our parent is the script or shell that
/// called it. Read at post time; nothing here needs a flag.
enum Sender {
    static func kinfo(_ pid: pid_t) -> kinfo_proc? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info
    }

    static func comm(_ k: kinfo_proc) -> String {
        var p = k.kp_proc.p_comm
        return withUnsafePointer(to: &p) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN) + 1) { String(cString: $0) }
        }
    }

    static func argv(_ pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4 else { return [] }
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0 else { return [] }
        let argc = Int(buf.withUnsafeBytes { $0.load(as: Int32.self) })
        // After argc comes the executable path, padding, then argv and the
        // environment, all NUL separated.
        var parts = buf[4...].split(separator: 0, omittingEmptySubsequences: false).map { String(decoding: $0, as: UTF8.self) }
        if !parts.isEmpty { parts.removeFirst() }
        parts = parts.filter { !$0.isEmpty }
        return Array(parts.prefix(max(argc, 0)))
    }

    static func cwd(_ pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let n = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, Int32(MemoryLayout<proc_vnodepathinfo>.size))
        guard n > 0 else { return nil }
        var p = info.pvi_cdir.vip_path
        return withUnsafePointer(to: &p) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
    }

    /// bash running a script is the script, not bash. The script is the first
    /// argument that is not an option and looks like a path: `zsh -c 'a b c'`
    /// carries a command string there, not a file, and stays zsh.
    static let interpreters: Set<String> = ["bash", "sh", "zsh", "dash", "fish", "env", "python", "python3", "ruby", "perl", "node", "osascript"]

    static func name(_ pid: pid_t, _ k: kinfo_proc) -> String {
        let args = argv(pid)
        let base = (args.first.map { ($0 as NSString).lastPathComponent } ?? comm(k))
        if interpreters.contains(base) {
            var skipNext = false
            for a in args.dropFirst() {
                if skipNext { skipNext = false; continue }
                if a == "-c" || a == "-e" || a == "-o" { skipNext = true; continue }
                if a.hasPrefix("-") { continue }
                if a.contains(" ") || a.contains("\n") { break }
                if interpreters.contains((a as NSString).lastPathComponent) { continue }
                return (a as NSString).lastPathComponent
            }
        }
        return base.isEmpty ? comm(k) : base
    }

    /// The launching GUI app, as LaunchServices stamps it on every descendant:
    /// com.mitchellh.ghostty, com.googlecode.iterm2, com.apple.Terminal. It
    /// survives tmux, where TERM_PROGRAM only says "tmux".
    static var terminalBundle: String? {
        let env = ProcessInfo.processInfo.environment
        if let b = env["__CFBundleIdentifier"], !b.isEmpty, b != bundleID { return b }
        return nil
    }

    static func fields() -> [(key: String, value: String)] {
        var out: [(key: String, value: String)] = []
        let env = ProcessInfo.processInfo.environment
        let parent = getppid()
        if let k = kinfo(parent) {
            out.append(("sender.process", name(parent, k)))
            out.append(("sender.pid", String(parent)))
            let args = argv(parent)
            if !args.isEmpty {
                var command = args.joined(separator: " ")
                if command.count > 400 { command = String(command.prefix(400)) + " …" }
                out.append(("sender.command", command))
            }
            var chain: [String] = []
            var pid = parent
            var info: kinfo_proc? = k
            while let i = info, pid > 0, chain.count < 12 {
                chain.append("\(chain.isEmpty ? name(pid, i) : comm(i))(\(pid))")
                let next = i.kp_eproc.e_ppid
                if next <= 0 || next == pid { break }
                pid = next
                info = kinfo(pid)
            }
            out.append(("sender.ancestry", chain.joined(separator: " < ")))
            if let d = cwd(parent) ?? env["PWD"] { out.append(("sender.cwd", d)) }
            if let t = ttyname(0) {
                out.append(("sender.tty", String(cString: t)))
            } else if k.kp_eproc.e_tdev != UInt32(bitPattern: -1), let d = devname(k.kp_eproc.e_tdev, mode_t(S_IFCHR)) {
                out.append(("sender.tty", "/dev/" + String(cString: d)))
            }
        } else if let d = env["PWD"] {
            out.append(("sender.cwd", d))
        }
        out.append(("sender.user", NSUserName()))
        var host = [CChar](repeating: 0, count: 256)
        if gethostname(&host, 256) == 0 { out.append(("sender.host", String(cString: host))) }
        // launchd names its jobs in XPC_SERVICE_NAME; a terminal's children see
        // "0" or "application.<bundle>...", neither of which is a job.
        if let label = env["XPC_SERVICE_NAME"], label != "0", !label.hasPrefix("application.") {
            out.append(("sender.launchd", label))
        }
        if let t = env["TERM_PROGRAM"] { out.append(("terminal.program", t)) }
        if let b = terminalBundle { out.append(("terminal.app", b)) }
        if let v = env["TERM_PROGRAM_VERSION"] { out.append(("terminal.version", v)) }
        if let p = env["TMUX_PANE"] { out.append(("terminal.tmux_pane", p)) }
        if let s = env["TMUX"] { out.append(("terminal.tmux", s)) }
        if let s = env["SSH_CONNECTION"] { out.append(("terminal.ssh", s)) }
        return out
    }
}
