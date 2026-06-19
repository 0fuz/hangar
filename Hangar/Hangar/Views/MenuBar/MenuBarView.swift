import SwiftUI

@MainActor
struct MenuBarView: View {
    @Environment(SnippetManager.self) private var manager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if manager.snippets.isEmpty {
                Text("No snippets yet")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                ForEach(manager.items.grouped()) { group in
                    if let title = group.title {
                        GroupHeaderRow(title: title, snippets: group.snippets)
                    }
                    ForEach(group.snippets) { snippet in
                        SnippetMenuItem(snippet: snippet)
                    }
                }
            }

            Divider().padding(.vertical, 4)

            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                menuRow(icon: "gear", title: "Settings...", shortcut: "⌘,")
            }
            .buttonStyle(.plain)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                menuRow(icon: "power", title: "Quit", shortcut: "⌘Q")
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .frame(minWidth: 280, maxWidth: 400)
        .fixedSize(horizontal: true, vertical: false)
        .task { manager.reconcileRunning() }
    }

    private func menuRow(icon: String, title: String, shortcut: String) -> some View {
        HStack {
            Image(systemName: icon)
            Text(title)
            Spacer()
            Text(shortcut).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

@MainActor
struct SnippetMenuItem: View {
    let snippet: Snippet
    @Environment(SnippetManager.self) private var manager

    private var isOn: Bool { manager.isRunning(snippet) }

    var body: some View {
        HStack {
            Circle()
                .fill(isOn ? Color.green : Color.secondary)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(snippet.name).lineLimit(1).truncationMode(.tail)
                Text(snippet.summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Button { manager.rerun(snippet) } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Run again — re-runs the command in the same window")

            Button { manager.focus(snippet) } label: {
                Image(systemName: "scope")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Bring its window to the front")
            .disabled(!isOn)

            Toggle("", isOn: Binding(
                get: { isOn },
                set: { _ in manager.toggle(snippet) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}

@MainActor
struct GroupHeaderRow: View {
    let title: String
    let snippets: [Snippet]
    @Environment(SnippetManager.self) private var manager

    var body: some View {
        HStack(spacing: 6) {
            if !title.isEmpty {
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            Rectangle().fill(.secondary.opacity(0.25)).frame(height: 1)
            Toggle("", isOn: Binding(
                get: { manager.isGroupActive(snippets) },
                set: { _ in manager.toggleGroup(snippets) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            .help("Toggle every snippet in this group")
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }
}

#Preview {
    MenuBarView().environment(SnippetManager())
}
