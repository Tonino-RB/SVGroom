import SwiftUI

struct SidebarView: View {
    @Environment(Library.self) private var library
    @State private var arrowMonitor: Any?

    var body: some View {
        @Bindable var library = library
        List(selection: $library.source) {
            Section("Catalog") {
                Label("All SVGs", systemImage: "square.grid.2x2")
                    .badge(library.items.count)
                    .tag(SidebarSource.all)
                Label("Missing Files", systemImage: "exclamationmark.triangle")
                    .badge(library.missingCount)
                    .foregroundStyle(library.missingCount > 0 ? .primary : .secondary)
                    .tag(SidebarSource.missing)
            }
            Section("Folders") {
                OutlineGroup(library.folderTree, children: \.children) { node in
                    FolderRow(node: node)
                        .tag(SidebarSource.folder(node.path))
                }
            }
        }
        .listStyle(.sidebar)
        // Arrows always browse the SVGs, never the folder list: catch them before the list does.
        .onAppear {
            arrowMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let key = event.keyCode, plain = event.modifierFlags.isDisjoint(with: [.command, .option, .control])
                let handled = MainActor.assumeIsolated { () -> Bool in
                    guard plain, NSApp.keyWindow?.firstResponder is NSTableView else { return false }
                    switch key {
                    case 123: library.moveFocus(by: -1)
                    case 124: library.moveFocus(by: 1)
                    case 126: library.moveFocus(by: -library.rowStep)
                    case 125: library.moveFocus(by: library.rowStep)
                    default: return false
                    }
                    return true
                }
                return handled ? nil : event
            }
        }
        .onDisappear { if let arrowMonitor { NSEvent.removeMonitor(arrowMonitor) } }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button { library.addFolderPanel() } label: { Label("Add Folder", systemImage: "plus") }
                    .buttonStyle(.borderless)
                    .help("Add a folder and its subfolders (⇧⌘I)")
                Spacer()
                if library.isScanning { ProgressView().controlSize(.small).help("Scanning folders…") }
            }
            .padding(10)
        }
        .dropDestination(for: URL.self) { urls, _ in
            let folders = urls.filter { $0.hasDirectoryPath }
            folders.forEach(library.addRoot)
            if !folders.isEmpty { library.rescan() }
            return !folders.isEmpty
        }
    }
}

private struct FolderRow: View {
    @Environment(Library.self) private var library
    let node: FolderNode

    var body: some View {
        let root = library.root(at: node.path)
        let linked = library.linkedFolders(of: node.path)
        Label {
            HStack(spacing: 4) {
                Text(node.name).foregroundStyle(node.missing ? .red : .primary)
                if !linked.isEmpty { Image(systemName: "link").foregroundStyle(.secondary).imageScale(.small) }
            }
        } icon: {
            Image(systemName: node.missing ? "folder.badge.questionmark" : "folder")
        }
        .badge(node.count)
        .help(node.missing ? "Folder not found: \(node.path)"
              : linked.isEmpty ? node.path : node.path + "\n\nLinked with:\n" + linked.joined(separator: "\n"))
        .contextMenu {
            if !node.missing {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: node.path)]) }
                Button("Synchronize") { library.rescan() }
            }
            Divider()
            Button("Link With…") { library.linkFolderPanel(node.path) }
            if !linked.isEmpty { Button("Unlink") { library.unlinkFolder(node.path) } }
            if let root {
                Divider()
                Button("Locate Folder…") { library.locateRootPanel(root) }
                Button("Remove from Catalog…") { library.pendingRootRemoval = root }
            }
        }
    }
}
