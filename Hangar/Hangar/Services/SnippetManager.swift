import Foundation
import SwiftUI
import AppKit
import os

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Hangar",
    category: "SnippetManager"
)

/// Relays NSTextField edits to a closure so the parameter prompt can live-update
/// its command preview as the user types.
private final class TextChangeWatcher: NSObject, NSTextFieldDelegate {
    private let onChange: () -> Void
    init(onChange: @escaping () -> Void) { self.onChange = onChange }
    func controlTextDidChange(_ obj: Notification) { onChange() }
}

/// Drives the real terminal apps via AppleScript. Static / nonisolated so the
/// (blocking) osascript call runs off the main actor.
enum Terminals {
    /// Escape for an AppleScript double-quoted string literal.
    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Open a window in the target terminal and run the command. Returns the
    /// window id (as text) so it can be closed later, or nil on failure.
    static func launch(_ t: TerminalLaunch) -> String? {
        let cmd = esc(t.command)
        let script: String
        switch t.terminal {
        case .iTerm2:
            // Create the window first and make it frontmost, THEN activate — so
            // macOS stays on the current Space instead of jumping to a Space that
            // already has an iTerm window.
            script = """
            tell application "iTerm2"
                set w to (create window with default profile)
                tell current session of w to write text "\(cmd)"
                select w
                activate
                return (id of w) as string
            end tell
            """
        case .terminal:
            script = """
            tell application "Terminal"
                do script "\(cmd)"
                activate
                return (id of front window) as string
            end tell
            """
        }
        return run(script)
    }

    /// Close the window previously launched for this snippet.
    static func close(handle: String, terminal: TerminalApp) {
        let app = terminal == .iTerm2 ? "iTerm2" : "Terminal"
        _ = run("""
        tell application "\(app)"
            try
                close (first window whose id is \(handle))
            end try
        end tell
        """)
    }

    /// Re-run the command in the existing window and bring it to front.
    static func rerun(handle: String, command: String, terminal: TerminalApp) {
        let cmd = esc(command)
        let script: String
        switch terminal {
        case .iTerm2:
            script = """
            tell application "iTerm2"
                try
                    tell current session of (first window whose id is \(handle)) to write text "\(cmd)"
                    select (first window whose id is \(handle))
                    activate
                end try
            end tell
            """
        case .terminal:
            script = """
            tell application "Terminal"
                try
                    do script "\(cmd)" in selected tab of (first window whose id is \(handle))
                    activate
                end try
            end tell
            """
        }
        _ = run(script)
    }

    /// Bring the launched window to the front.
    static func focus(handle: String, terminal: TerminalApp) {
        let app = terminal == .iTerm2 ? "iTerm2" : "Terminal"
        let select = terminal == .iTerm2
            ? "select (first window whose id is \(handle))"
            : "set frontmost of (first window whose id is \(handle)) to true"
        _ = run("""
        tell application "\(app)"
            try
                \(select)
                activate
            end try
        end tell
        """)
    }

    static func bundleID(_ terminal: TerminalApp) -> String {
        terminal == .iTerm2 ? "com.googlecode.iterm2" : "com.apple.Terminal"
    }

    /// Whether the launched window is still open. False (without scripting) when
    /// the terminal app isn't running — which also avoids relaunching it.
    static func windowExists(handle: String, terminal: TerminalApp) -> Bool {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID(terminal)).isEmpty else {
            return false
        }
        let app = terminal == .iTerm2 ? "iTerm2" : "Terminal"
        let r = run("""
        tell application "\(app)"
            try
                return ((count of (windows whose id is \(handle))) > 0) as string
            on error
                return "false"
            end try
        end tell
        """)
        return r == "true"
    }

    @discardableResult
    static func run(_ source: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", source]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
        } catch {
            logger.error("osascript failed to start: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let result = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}

@Observable
@MainActor
final class SnippetManager {
    var items: [SidebarItem] = []
    var snippets: [Snippet] { items.snippets }

    // Optimistic running state (v0): set on launch, cleared on close. Reconciling
    // against the terminal's actual open windows is a later refinement.
    private var runningIDs: Set<UUID> = []
    // Window handle per launched snippet, used to close it.
    private var handles: [UUID: String] = [:]

    private let configStore = ConfigStore()

    init() {
        Task { [weak self] in
            let loaded = await self?.configStore.load() ?? []
            self?.items = loaded
            self?.autoStartSnippets()
        }
        startLivenessMonitor()
    }

    /// Periodically reconcile running state. reconcileRunning early-returns when
    /// nothing is running, so this is cheap while idle.
    private func startLivenessMonitor() {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                self?.reconcileRunning()
            }
        }
    }

    // MARK: - Activation

    func isRunning(_ snippet: Snippet) -> Bool { runningIDs.contains(snippet.id) }

    /// Tray / button entry point. v0: launch when stopped, close when running.
    /// (Per-mode re-click behavior — rerun / focus — is the next iteration.)
    func toggle(_ snippet: Snippet) {
        if isRunning(snippet) {
            close(snippet)
        } else {
            launch(snippet)
        }
    }

    func launch(_ snippet: Snippet) {
        let id = snippet.id
        switch snippet.action {
        case .terminal(var t):
            // Parameterized? Ask for values first; cancelling aborts the launch
            // (so we don't flip the toggle on for a command that never ran).
            if !t.params.isEmpty {
                guard let values = promptForParams(snippetName: snippet.name, snippetID: id, launch: t) else { return }
                t.command = t.resolvedCommand(with: values)
            }
            runningIDs.insert(id) // optimistic, immediate UI feedback
            let launchT = t
            Task {
                // Run the blocking osascript off-main, then store the handle on main.
                let handle = await Task.detached { Terminals.launch(launchT) }.value
                if let handle { self.handles[id] = handle }
            }
        case .app(let a):
            runningIDs.insert(id) // optimistic, immediate UI feedback
            let bundleID = a.bundleIdentifier
            let openPath = a.openPath
            Task.detached {
                guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
                let config = NSWorkspace.OpenConfiguration()
                if openPath.isEmpty {
                    NSWorkspace.shared.openApplication(at: appURL, configuration: config, completionHandler: nil)
                } else {
                    // Open a project / file with the app, e.g. PhpStorm + a project folder.
                    NSWorkspace.shared.open([URL(fileURLWithPath: openPath)],
                                            withApplicationAt: appURL,
                                            configuration: config,
                                            completionHandler: nil)
                }
            }
        }
    }

    func close(_ snippet: Snippet) {
        runningIDs.remove(snippet.id)
        switch snippet.action {
        case .terminal(let t):
            guard let handle = handles.removeValue(forKey: snippet.id) else { return }
            let term = t.terminal
            Task.detached { Terminals.close(handle: handle, terminal: term) }
        case .app(let a):
            let bundleID = a.bundleIdentifier
            Task.detached {
                for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
                    app.terminate()
                }
            }
        }
    }

    /// Re-run: launch if stopped, else re-send the command into the same window.
    func rerun(_ snippet: Snippet) {
        guard isRunning(snippet),
              let handle = handles[snippet.id],
              case .terminal(let t) = snippet.action else {
            launch(snippet)
            return
        }
        var cmd = t.command
        if !t.params.isEmpty {
            guard let values = promptForParams(snippetName: snippet.name, snippetID: snippet.id, launch: t) else { return }
            cmd = t.resolvedCommand(with: values)
        }
        let finalCmd = cmd, term = t.terminal
        Task.detached { Terminals.rerun(handle: handle, command: finalCmd, terminal: term) }
    }

    /// Focus: bring the running window / app to the front. No-op when stopped.
    func focus(_ snippet: Snippet) {
        guard isRunning(snippet) else { return }
        switch snippet.action {
        case .terminal(let t):
            guard let handle = handles[snippet.id] else { return }
            let term = t.terminal
            Task.detached { Terminals.focus(handle: handle, terminal: term) }
        case .app(let a):
            let bundleID = a.bundleIdentifier
            Task.detached {
                NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.activate()
            }
        }
    }

    // MARK: - Parameter prompt

    private func paramKey(_ snippetID: UUID, _ name: String) -> String {
        "param.\(snippetID.uuidString).\(name)"
    }

    /// Ask the user to fill a snippet's `{{name}}` parameters before it runs.
    /// The dialog names the snippet and shows a live preview of the exact command
    /// that will run. Returns the entered values, or nil if the user cancelled.
    /// Fields pre-fill with the last-entered value (else the default) and are
    /// remembered for next time.
    private func promptForParams(snippetName: String, snippetID: UUID, launch: TerminalLaunch) -> [String: String]? {
        let params = launch.params
        guard !params.isEmpty else { return [:] }

        let alert = NSAlert()
        let title = snippetName.isEmpty ? "Run snippet" : "Run “\(snippetName)”"
        alert.messageText = "\(title) in \(launch.terminal.displayName)"
        alert.informativeText = "Fill in the values — the preview below is the exact command that will run."
        alert.addButton(withTitle: "Run")
        alert.addButton(withTitle: "Cancel")

        let labelW: CGFloat = 90, gap: CGFloat = 8, fieldW: CGFloat = 240, rowH: CGFloat = 28
        let width = labelW + gap + fieldW
        let previewH: CGFloat = 48
        let height = previewH + CGFloat(params.count) * rowH
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        var fields: [NSTextField] = []
        for (i, p) in params.enumerated() {
            let y = height - CGFloat(i + 1) * rowH   // fields stacked above the preview
            let label = NSTextField(labelWithString: p.promptLabel + ":")
            label.frame = NSRect(x: 0, y: y + 4, width: labelW, height: 18)
            label.alignment = .right
            let field = NSTextField(frame: NSRect(x: labelW + gap, y: y, width: fieldW, height: 22))
            field.stringValue = UserDefaults.standard.string(forKey: paramKey(snippetID, p.name)) ?? p.defaultValue
            field.placeholderString = p.defaultValue.isEmpty ? p.name : p.defaultValue
            container.addSubview(label)
            container.addSubview(field)
            fields.append(field)
        }

        // Live preview of the resolved command, refreshed as the user types.
        let preview = NSTextField(wrappingLabelWithString: "")
        preview.frame = NSRect(x: 0, y: 0, width: width, height: previewH - 4)
        preview.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        preview.textColor = .secondaryLabelColor
        preview.maximumNumberOfLines = 3
        container.addSubview(preview)

        let refresh = {
            var vals: [String: String] = [:]
            for (i, p) in params.enumerated() { vals[p.name] = fields[i].stringValue }
            preview.stringValue = "$ " + launch.resolvedCommand(with: vals)
        }
        let watcher = TextChangeWatcher(onChange: refresh)
        fields.forEach { $0.delegate = watcher }
        refresh()

        alert.accessoryView = container
        NSApp.activate(ignoringOtherApps: true)
        if let first = fields.first { alert.window.initialFirstResponder = first }

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        var values: [String: String] = [:]
        for (i, p) in params.enumerated() {
            let v = fields[i].stringValue
            values[p.name] = v
            UserDefaults.standard.set(v, forKey: paramKey(snippetID, p.name))
        }
        return values
    }

    /// Reconcile optimistic state against the terminal's actual open windows (and
    /// running apps), so a manually-closed window flips the toggle off. Cheap
    /// enough to run whenever the menu bar / detail view appears.
    func reconcileRunning() {
        let tracked = Array(runningIDs)
        guard !tracked.isEmpty else { return }
        let snapshot = snippets
        let handleSnapshot = handles
        Task {
            var alive: Set<UUID> = []
            for id in tracked {
                guard let snippet = snapshot.first(where: { $0.id == id }) else { continue }
                switch snippet.action {
                case .terminal(let t):
                    guard let handle = handleSnapshot[id] else {
                        alive.insert(id) // still launching (handle not stored yet) — keep
                        continue
                    }
                    let exists = await Task.detached { Terminals.windowExists(handle: handle, terminal: t.terminal) }.value
                    if exists { alive.insert(id) }
                case .app(let a):
                    let bundleID = a.bundleIdentifier
                    let running = await Task.detached {
                        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
                    }.value
                    if running { alive.insert(id) }
                }
            }
            for id in tracked where !alive.contains(id) { handles.removeValue(forKey: id) }
            runningIDs = alive
        }
    }

    private func autoStartSnippets() {
        for snippet in snippets where snippet.autoStart {
            launch(snippet)
        }
    }

    static let closeOnQuitKey = "closeOnQuit"

    /// Synchronously close every running snippet's window / app — used on quit
    /// when the user opted in. Blocking osascript is fine here (we're exiting).
    func closeAllRunningSync() {
        guard UserDefaults.standard.bool(forKey: Self.closeOnQuitKey) else { return }
        for snippet in snippets where isRunning(snippet) {
            switch snippet.action {
            case .terminal(let t):
                if let handle = handles[snippet.id] {
                    Terminals.close(handle: handle, terminal: t.terminal)
                }
            case .app(let a):
                for app in NSRunningApplication.runningApplications(withBundleIdentifier: a.bundleIdentifier) {
                    app.terminate()
                }
            }
        }
    }

    // MARK: - Groups

    func isGroupActive(_ group: [Snippet]) -> Bool {
        guard !group.isEmpty else { return false }
        return group.allSatisfy { isRunning($0) }
    }

    func toggleGroup(_ group: [Snippet]) {
        if isGroupActive(group) {
            for s in group { close(s) }
        } else {
            for s in group where !isRunning(s) { launch(s) }
        }
    }

    // MARK: - Snippet CRUD

    @discardableResult
    func addSnippet() -> Snippet {
        let snippet = Snippet(name: "New Snippet")
        items.append(.snippet(snippet))
        save()
        return snippet
    }

    func updateSnippet(_ snippet: Snippet) {
        guard let index = items.firstIndex(where: { $0.snippet?.id == snippet.id }) else { return }
        items[index] = .snippet(snippet)
        save()
    }

    func deleteSnippet(_ snippet: Snippet) {
        close(snippet)
        items.removeAll { $0.snippet?.id == snippet.id }
        save()
    }

    @discardableResult
    func cloneSnippet(_ snippet: Snippet) -> Snippet {
        var clone = snippet
        clone.id = UUID()
        clone.name = "\(snippet.name) (Copy)"
        if let index = items.firstIndex(where: { $0.snippet?.id == snippet.id }) {
            items.insert(.snippet(clone), at: index + 1)
        } else {
            items.append(.snippet(clone))
        }
        save()
        return clone
    }

    // MARK: - Dividers

    @discardableResult
    func addDivider(after id: UUID?) -> GroupDivider {
        let divider = GroupDivider()
        if let id, let index = items.firstIndex(where: { $0.id == id }) {
            items.insert(.divider(divider), at: index + 1)
        } else {
            items.insert(.divider(divider), at: 0)
        }
        save()
        return divider
    }

    func renameDivider(_ id: UUID, title: String) {
        guard let index = items.firstIndex(where: { $0.id == id }),
              case .divider(var divider) = items[index] else { return }
        divider.title = title
        items[index] = .divider(divider)
        save()
    }

    func deleteDivider(_ id: UUID) {
        items.removeAll { $0.divider?.id == id }
        save()
    }

    // MARK: - Reordering

    func canMoveUp(id: UUID) -> Bool {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return false }
        return i > 0
    }

    func canMoveDown(id: UUID) -> Bool {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return false }
        return i < items.count - 1
    }

    func moveItemUp(id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }), i > 0 else { return }
        items.swapAt(i, i - 1)
        save()
    }

    func moveItemDown(id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }), i < items.count - 1 else { return }
        items.swapAt(i, i + 1)
        save()
    }

    func moveItems(from offsets: IndexSet, to destination: Int) {
        items.move(fromOffsets: offsets, toOffset: destination)
        save()
    }

    // MARK: - Persistence

    private func save() {
        let snapshot = items
        Task { await configStore.save(snapshot) }
    }
}
