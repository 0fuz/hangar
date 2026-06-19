import SwiftUI

@MainActor
struct SnippetListView: View {
    @Environment(SnippetManager.self) private var manager
    @Binding var selection: UUID?

    var body: some View {
        List(selection: $selection) {
            ForEach(manager.items) { item in
                switch item {
                case .snippet(let snippet):
                    SnippetRow(snippet: snippet)
                        .tag(snippet.id)
                        .contextMenu {
                            Button {
                                let clone = manager.cloneSnippet(snippet)
                                selection = clone.id
                            } label: { Label("Clone", systemImage: "doc.on.doc") }

                            Button {
                                let divider = manager.addDivider(after: snippet.id)
                                selection = divider.id
                            } label: { Label("Add Divider Below", systemImage: "rectangle.dashed") }

                            Divider()

                            Button(role: .destructive) {
                                if selection == snippet.id { selection = nil }
                                manager.deleteSnippet(snippet)
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                case .divider(let divider):
                    DividerRow(divider: divider)
                        .tag(divider.id)
                        .contextMenu {
                            Button(role: .destructive) {
                                if selection == divider.id { selection = nil }
                                manager.deleteDivider(divider.id)
                            } label: { Label("Delete Divider", systemImage: "trash") }
                        }
                }
            }
            .onMove { manager.moveItems(from: $0, to: $1) }
            .onDelete(perform: deleteItems)
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    let divider = manager.addDivider(after: selection)
                    selection = divider.id
                } label: { Image(systemName: "rectangle.dashed") }
                .help("Add a group divider")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    let snippet = manager.addSnippet()
                    selection = snippet.id
                } label: { Image(systemName: "plus") }
                .help("Add a snippet")
            }
        }
    }

    private func deleteItems(at offsets: IndexSet) {
        let targets = offsets.map { manager.items[$0] }
        for item in targets {
            if selection == item.id { selection = nil }
            switch item {
            case .snippet(let s): manager.deleteSnippet(s)
            case .divider(let d): manager.deleteDivider(d.id)
            }
        }
    }
}

@MainActor
struct SnippetRow: View {
    let snippet: Snippet
    @Environment(SnippetManager.self) private var manager

    var body: some View {
        HStack(spacing: 8) {
            StatusIndicator(isRunning: manager.isRunning(snippet), size: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(snippet.name).fontWeight(.medium).lineLimit(1)
                Text(snippet.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 2)
    }
}

@MainActor
struct DividerRow: View {
    let divider: GroupDivider

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.horizontal.3")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if divider.title.isEmpty {
                Text("New group").font(.caption2).italic().foregroundStyle(.tertiary)
            } else {
                Text(divider.title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Rectangle().fill(.secondary.opacity(0.25)).frame(height: 1)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

#Preview {
    SnippetListView(selection: .constant(nil))
        .environment(SnippetManager())
        .frame(width: 250)
}
