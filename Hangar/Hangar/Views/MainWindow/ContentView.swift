import SwiftUI
import ServiceManagement
import os

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Hangar",
    category: "ContentView"
)

@MainActor
struct ContentView: View {
    @Environment(SnippetManager.self) private var manager
    @State private var selectedID: UUID?
    @State private var showPreferences = false

    private var selectedItem: SidebarItem? {
        guard let id = selectedID else { return nil }
        return manager.items.first { $0.id == id }
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                SnippetListView(selection: $selectedID)

                Divider()

                if let item = selectedItem {
                    HStack(spacing: 12) {
                        Button {
                            manager.moveItemUp(id: item.id)
                        } label: { Image(systemName: "arrow.up") }
                            .disabled(!manager.canMoveUp(id: item.id))
                            .help("Move Up")

                        Button {
                            manager.moveItemDown(id: item.id)
                        } label: { Image(systemName: "arrow.down") }
                            .disabled(!manager.canMoveDown(id: item.id))
                            .help("Move Down")

                        Divider().frame(height: 16)

                        if case .snippet(let snippet) = item {
                            Button {
                                let clone = manager.cloneSnippet(snippet)
                                selectedID = clone.id
                            } label: { Image(systemName: "doc.on.doc") }
                                .help("Clone")
                        }

                        Spacer()

                        Button(role: .destructive) {
                            deleteSelected(item)
                        } label: { Image(systemName: "trash") }
                            .help("Delete")
                    }
                    .buttonStyle(.borderless)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    Divider()
                }

                HStack {
                    Button {
                        showPreferences.toggle()
                    } label: {
                        Label("Preferences", systemImage: "gearshape").font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .popover(isPresented: $showPreferences, arrowEdge: .bottom) {
                        AppPreferencesView()
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            if let item = selectedItem {
                switch item {
                case .snippet(let snippet):
                    SnippetDetailView(snippet: snippet)
                case .divider(let divider):
                    DividerDetailView(divider: divider).id(divider.id)
                }
            } else {
                ContentUnavailableView {
                    Label("Nothing Selected", systemImage: "terminal")
                } description: {
                    Text("Select a snippet or divider, or create a new one.")
                } actions: {
                    Button("Add Snippet") {
                        let snippet = manager.addSnippet()
                        selectedID = snippet.id
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func deleteSelected(_ item: SidebarItem) {
        selectedID = nil
        switch item {
        case .snippet(let s): manager.deleteSnippet(s)
        case .divider(let d): manager.deleteDivider(d.id)
        }
    }
}

/// Detail pane for a group divider — a single name field.
@MainActor
struct DividerDetailView: View {
    let divider: GroupDivider
    @Environment(SnippetManager.self) private var manager
    @FocusState private var focused: Bool
    @State private var name: String

    init(divider: GroupDivider) {
        self.divider = divider
        self._name = State(initialValue: divider.title)
    }

    var body: some View {
        Form {
            Section {
                TextField("Group name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit { save() }
            } header: {
                Text("Group")
            } footer: {
                Text("Shown as a divider in the sidebar and as a section header with a master toggle in the menu bar.")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .onChange(of: focused) { _, isFocused in if !isFocused { save() } }
        .onChange(of: divider) { _, newValue in name = newValue.title }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Save") { save() }.disabled(name == divider.title)
            }
        }
    }

    private func save() {
        guard name != divider.title else { return }
        manager.renameDivider(divider.id, title: name)
    }
}

/// App-level preferences in a popover.
@MainActor
struct AppPreferencesView: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var closeOnQuit = UserDefaults.standard.bool(forKey: SnippetManager.closeOnQuitKey)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preferences").font(.headline)

            Toggle("Launch at Login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    do {
                        if newValue { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
                    } catch {
                        logger.error("Failed to update login item: \(error.localizedDescription, privacy: .public)")
                        launchAtLogin = !newValue
                    }
                }

            Text("Snippets marked “Auto-start” launch when Hangar starts, so a restart doesn’t leave them behind.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Toggle("Close launched windows when Hangar quits", isOn: $closeOnQuit)
                .onChange(of: closeOnQuit) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: SnippetManager.closeOnQuitKey)
                }

            Text("Off by default — quitting Hangar leaves your terminals and apps running.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .toggleStyle(.checkbox)
        .padding(16)
        .frame(width: 320, alignment: .leading)
    }
}

#Preview {
    ContentView().environment(SnippetManager())
}
