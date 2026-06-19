import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
struct SnippetDetailView: View {
    let snippet: Snippet
    @Environment(SnippetManager.self) private var manager
    @FocusState private var focusedField: Field?

    @State private var editedSnippet: Snippet

    enum Field: Hashable { case name, command }
    enum ActionKind: Hashable { case terminal, app }

    init(snippet: Snippet) {
        self.snippet = snippet
        self._editedSnippet = State(initialValue: snippet)
    }

    private var hasChanges: Bool { editedSnippet != snippet }
    private var isRunning: Bool { manager.isRunning(snippet) }

    private var actionKind: Binding<ActionKind> {
        Binding(
            get: { if case .app = editedSnippet.action { return .app } else { return .terminal } },
            set: { kind in
                switch kind {
                case .terminal: editedSnippet.action = .terminal(editedSnippet.terminalLaunch ?? TerminalLaunch())
                case .app:      editedSnippet.action = .app(editedSnippet.appLaunch ?? AppLaunch())
                }
            }
        )
    }

    private var terminal: Binding<TerminalLaunch> {
        Binding(get: { editedSnippet.terminalLaunch ?? TerminalLaunch() },
                set: { editedSnippet.action = .terminal($0) })
    }

    private var app: Binding<AppLaunch> {
        Binding(get: { editedSnippet.appLaunch ?? AppLaunch() },
                set: { editedSnippet.action = .app($0) })
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    StatusIndicator(isRunning: isRunning)
                    Text(isRunning ? "Running" : "Stopped")
                        .foregroundStyle(isRunning ? .green : .secondary)

                    Spacer()

                    Button {
                        if hasChanges { save() }
                        manager.rerun(editedSnippet)
                    } label: { Image(systemName: "arrow.clockwise") }
                        .help("Run again — re-runs the command in the same window")

                    Button {
                        manager.focus(editedSnippet)
                    } label: { Image(systemName: "scope") }
                        .help("Bring its window to the front")
                        .disabled(!isRunning)

                    Button(isRunning ? "Stop" : "Launch") {
                        if hasChanges { save() }
                        manager.toggle(editedSnippet)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isRunning ? .red : .green)
                }
            } header: {
                Text("Status")
            }

            Section {
                TextField("Name", text: $editedSnippet.name)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .name)
            } header: {
                Text("General")
            }

            Section {
                Picker("Type", selection: actionKind) {
                    Text("Terminal").tag(ActionKind.terminal)
                    Text("Application").tag(ActionKind.app)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch actionKind.wrappedValue {
                case .terminal:
                    Picker("Terminal", selection: terminal.terminal) {
                        ForEach(TerminalApp.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Command")
                            Spacer()
                            Button("Folder…") { chooseFolder() }
                        }
                        TextField("npm run b", text: terminal.command)
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .focused($focusedField, equals: .command)
                    }

                    Text("Opens \(terminal.wrappedValue.terminal.displayName) and runs this command. Folder… prepends a `cd`, or type the full line yourself.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                case .app:
                    LabeledContent("Application") {
                        HStack {
                            Text(app.wrappedValue.displayName.isEmpty ? "None chosen" : app.wrappedValue.displayName)
                                .foregroundStyle(app.wrappedValue.displayName.isEmpty ? .secondary : .primary)
                            Spacer()
                            Button("Choose App…") { chooseApp() }
                        }
                    }

                    LabeledContent("Open") {
                        HStack {
                            Text(app.wrappedValue.openPath.isEmpty ? "App only" : (app.wrappedValue.openPath as NSString).lastPathComponent)
                                .foregroundStyle(app.wrappedValue.openPath.isEmpty ? .secondary : .primary)
                            Spacer()
                            if !app.wrappedValue.openPath.isEmpty {
                                Button("Clear") { app.wrappedValue.openPath = "" }
                            }
                            Button("Choose…") { chooseOpenPath() }
                        }
                    }

                    Text("Launches the app (toggling off quits it). Optionally open a project or file with it — e.g. PhpStorm + a project folder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Action")
            }

            Section {
                Toggle("Auto-start when Hangar launches", isOn: $editedSnippet.autoStart)
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Save") { save() }.disabled(!hasChanges)
            }
        }
        .task { manager.reconcileRunning() }
        .onChange(of: snippet.id) { _, _ in editedSnippet = snippet }
        .onChange(of: focusedField) { oldValue, newValue in
            if oldValue != nil && newValue != oldValue && hasChanges { save() }
        }
    }

    private func save() {
        manager.updateSnippet(editedSnippet)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url {
            var a = app.wrappedValue   // keep any chosen project/file
            a.bundleIdentifier = Bundle(url: url)?.bundleIdentifier ?? ""
            a.displayName = url.deletingPathExtension().lastPathComponent
            app.wrappedValue = a
        }
    }

    private func chooseOpenPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true   // projects are usually folders
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            app.wrappedValue.openPath = url.path
        }
    }

    /// Pick a folder and prepend (or replace) a leading `cd '…' &&` in the command.
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var cmd = terminal.wrappedValue.command
        if cmd.hasPrefix("cd "), let range = cmd.range(of: " && ") {
            cmd = String(cmd[range.upperBound...])
        }
        let safe = url.path.replacingOccurrences(of: "'", with: "'\\''")
        terminal.wrappedValue.command = "cd '\(safe)' && " + cmd
    }
}

#Preview {
    SnippetDetailView(snippet: Snippet(name: "Build"))
        .environment(SnippetManager())
}
