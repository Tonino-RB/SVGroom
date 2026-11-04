import SwiftUI

/// After a synchronization: files and folders no longer where the catalog expects them.
/// Each one can be located (moved or renamed) or removed from the catalog (deleted).
struct MissingReviewView: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let roots = library.missingRootFolders
        let rootPrefixes = roots.map { $0.path + "/" }
        // Files inside a missing folder follow it.
        let files = library.items.values
            .filter { item in item.missing && !rootPrefixes.contains { item.path.hasPrefix($0) } }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

        VStack(alignment: .leading, spacing: 12) {
            Text("Missing Files").font(.title2.bold())
            Text("These are no longer where the catalog expects them. Locate the ones that were moved or renamed; remove the ones that were deleted (their ratings, flags and tags are forgotten).")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if roots.isEmpty && files.isEmpty {
                Label("Nothing is missing.", systemImage: "checkmark.circle").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !roots.isEmpty {
                        Section("Folders") {
                            ForEach(roots) { root in
                                row(name: (root.path as NSString).lastPathComponent, path: root.path, icon: "folder.badge.questionmark") {
                                    Button("Locate…") { library.locateRootPanel(root) }
                                    Button("Remove") { library.removeRoot(root) }
                                }
                            }
                        }
                    }
                    if !files.isEmpty {
                        Section("Files (\(files.count))") {
                            ForEach(files) { item in
                                row(name: item.name, path: item.folder, icon: "questionmark.square.dashed") {
                                    Button("Locate…") { library.locatePanel(item) }
                                    Button("Remove") { library.removeMissingFromCatalog([item.id]) }
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }

            HStack {
                Button("Search Folder…") { library.findMissingPanel() }
                    .help("Find the missing files in a folder, by name and size, then by content")
                    .disabled(files.isEmpty)
                Button("Remove All Files from Catalog", role: .destructive) {
                    library.removeMissingFromCatalog(files.map(\.id))
                }
                .disabled(files.isEmpty)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 620, idealWidth: 760, minHeight: 420, idealHeight: 560)
    }

    private func row<Buttons: View>(name: String, path: String, icon: String, @ViewBuilder buttons: () -> Buttons) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).lineLimit(1).truncationMode(.middle)
                Text(path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            .help(path)
            Spacer()
            buttons().controlSize(.small)
        }
    }
}
