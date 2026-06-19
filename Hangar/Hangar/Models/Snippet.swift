import Foundation

/// Which terminal a terminal-action snippet drives.
enum TerminalApp: String, Codable, Hashable, CaseIterable {
    case iTerm2
    case terminal   // Apple Terminal.app

    var displayName: String {
        switch self {
        case .iTerm2: return "iTerm2"
        case .terminal: return "Terminal"
        }
    }
}

/// A terminal workflow: open `terminal` and run `command`. The command is the
/// full line the user types, e.g. "cd ~/code/project && npm run b".
struct TerminalLaunch: Codable, Hashable {
    var terminal: TerminalApp
    var command: String

    init(terminal: TerminalApp = .iTerm2, command: String = "") {
        self.terminal = terminal
        self.command = command
    }
}

/// Launch an application. `displayName` is kept for the UI so we don't re-resolve
/// the bundle identifier every render. `openPath` optionally opens a file or
/// folder *with* the app (e.g. a project folder for an IDE) — empty just launches it.
struct AppLaunch: Codable, Hashable {
    var bundleIdentifier: String
    var displayName: String
    var openPath: String

    init(bundleIdentifier: String = "", displayName: String = "", openPath: String = "") {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.openPath = openPath
    }
}

/// What a snippet does when activated. The typed action keeps the door open for
/// `.app` / `.url` launches without reshaping `Snippet`.
enum SnippetAction: Codable, Hashable {
    case terminal(TerminalLaunch)
    case app(AppLaunch)
}

struct Snippet: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var action: SnippetAction
    var autoStart: Bool   // activate on launch (so a restart doesn't lose it)

    init(
        id: UUID = UUID(),
        name: String = "",
        action: SnippetAction = .terminal(TerminalLaunch()),
        autoStart: Bool = false
    ) {
        self.id = id
        self.name = name
        self.action = action
        self.autoStart = autoStart
    }

    /// The terminal payload, if this is a terminal snippet.
    var terminalLaunch: TerminalLaunch? {
        if case .terminal(let t) = action { return t }
        return nil
    }

    /// The app payload, if this is an application snippet.
    var appLaunch: AppLaunch? {
        if case .app(let a) = action { return a }
        return nil
    }

    /// Short one-line summary for the sidebar / menu bar.
    var summary: String {
        switch action {
        case .terminal(let t):
            return t.command.isEmpty ? "(no command)" : t.command
        case .app(let a):
            let base = a.displayName.isEmpty ? a.bundleIdentifier : a.displayName
            guard !a.openPath.isEmpty else { return base }
            return "\(base) — \((a.openPath as NSString).lastPathComponent)"
        }
    }
}

/// A standalone divider that begins a group in the sidebar / menu bar.
struct GroupDivider: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String

    init(id: UUID = UUID(), title: String = "") {
        self.id = id
        self.title = title
    }
}

/// One row in the ordered list: a snippet or a group divider.
enum SidebarItem: Identifiable, Hashable {
    case snippet(Snippet)
    case divider(GroupDivider)

    var id: UUID {
        switch self {
        case .snippet(let s): return s.id
        case .divider(let d): return d.id
        }
    }
    var snippet: Snippet? {
        if case .snippet(let s) = self { return s }
        return nil
    }
    var divider: GroupDivider? {
        if case .divider(let d) = self { return d }
        return nil
    }
}

extension SidebarItem: Codable {
    private enum Kind: String, Codable { case snippet, divider }
    private enum CodingKeys: String, CodingKey { case kind, snippet, divider }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .snippet: self = .snippet(try c.decode(Snippet.self, forKey: .snippet))
        case .divider: self = .divider(try c.decode(GroupDivider.self, forKey: .divider))
        }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .snippet(let s):
            try c.encode(Kind.snippet, forKey: .kind)
            try c.encode(s, forKey: .snippet)
        case .divider(let d):
            try c.encode(Kind.divider, forKey: .kind)
            try c.encode(d, forKey: .divider)
        }
    }
}

/// A contiguous run of snippets between dividers. `title` is nil for the
/// leading run before the first divider.
struct SnippetGroup: Identifiable {
    let id: String
    let title: String?
    let snippets: [Snippet]
}

extension Array where Element == SidebarItem {
    /// All snippets in order, ignoring dividers.
    var snippets: [Snippet] { compactMap(\.snippet) }

    /// Split into groups: each divider begins a new group with its title.
    func grouped() -> [SnippetGroup] {
        var groups: [SnippetGroup] = []
        var current: [Snippet] = []
        var title: String?

        func flush() {
            guard let first = current.first else { return }
            groups.append(SnippetGroup(id: first.id.uuidString, title: title, snippets: current))
        }

        for item in self {
            switch item {
            case .snippet(let s):
                current.append(s)
            case .divider(let d):
                flush()
                current = []
                title = d.title
            }
        }
        flush()
        return groups
    }
}
