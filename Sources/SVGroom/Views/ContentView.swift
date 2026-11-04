import SVGroomCore
import SwiftUI

struct ContentView: View {
    @Environment(Library.self) private var library
    @AppStorage("showInspector") private var showInspector = true

    var body: some View {
        @Bindable var library = library
        Group {
            if library.catalogURL == nil {
                WelcomeView()
            } else {
                NavigationSplitView {
                    SidebarView()
                        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 360)
                } detail: {
                    BrowserView()
                        .inspector(isPresented: $showInspector) {
                            InspectorView()
                                .inspectorColumnWidth(min: 260, ideal: 300, max: 440)
                        }
                }
                .navigationTitle(library.catalogURL?.deletingPathExtension().lastPathComponent ?? "SVGroom")
                .toolbar {
                    ToolbarItem {
                        Button { showInspector.toggle() } label: { Label("Inspector", systemImage: "sidebar.right") }
                            .help("Show or hide the inspector")
                    }
                }
            }
        }
        .confirmationDialog(trashTitle, isPresented: Binding(get: { library.pendingTrash != nil },
                                                             set: { if !$0 { library.pendingTrash = nil } })) {
            Button("Move to Trash", role: .destructive) { library.confirmTrash() }
        } message: {
            Text("Files go to the Trash and can be restored from there. Their ratings and flags are removed from the catalog.")
        }
        .confirmationDialog("Remove “\(library.pendingRootRemoval.map { ($0.path as NSString).lastPathComponent } ?? "")” from the catalog?",
                            isPresented: Binding(get: { library.pendingRootRemoval != nil },
                                                 set: { if !$0 { library.pendingRootRemoval = nil } })) {
            Button("Remove", role: .destructive) { library.confirmRootRemoval() }
        } message: {
            Text("Files stay on disk, but their ratings, flags and labels are forgotten.")
        }
        .confirmationDialog("Move “\(library.pendingFolderTrash.map { ($0.path as NSString).lastPathComponent } ?? "")” to the Trash?",
                            isPresented: Binding(get: { library.pendingFolderTrash != nil },
                                                 set: { if !$0 { library.pendingFolderTrash = nil } })) {
            Button("Move Folder to Trash", role: .destructive) { library.confirmFolderTrash() }
        } message: {
            let n = library.pendingFolderTrash?.svgCount ?? 0
            Text("The whole folder goes to the Trash — all its files, not only the \(n == 1 ? "SVG" : "\(n) SVGs"), and its subfolders. It can be restored from the Trash. Its ratings, flags and tags are removed from the catalog.")
        }
        .sheet(item: $library.pendingTagSync) { TagSyncView(review: $0) }
        .sheet(isPresented: $library.showsMissingReview) { MissingReviewView() }
        .sheet(isPresented: $library.showsTagManager) { TagManagerView() }
        .alert(library.alertMessage ?? "", isPresented: Binding(get: { library.alertMessage != nil },
                                                               set: { if !$0 { library.alertMessage = nil } })) {
            Button("OK") {}
        }
    }

    private var trashTitle: String {
        let n = library.pendingTrash?.count ?? 0
        return n == 1 ? "Move 1 file to the Trash?" : "Move \(n) files to the Trash?"
    }
}

struct WelcomeView: View {
    @Environment(Library.self) private var library

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "scribble.variable")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
            Text("SVGroom").font(.largeTitle.bold())
            Text("Your ratings, flags and labels live in a catalog: a single file you choose the location of, and can back up or move.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 440)
            if let problem = library.catalogProblem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .frame(maxWidth: 480)
            }
            HStack {
                Button("Open Catalog…") { library.openCatalogPanel() }
                Button("New Catalog…") { library.newCatalogPanel() }
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SettingsView: View {
    @Environment(Library.self) private var library

    var body: some View {
        Form {
            Section {
                ForEach(PlotSettings.fields, id: \.key) { f in
                    PercentField(key: f.key, label: f.label, default: PlotSettings()[keyPath: f.path])
                }
            } header: {
                Text("AxiDraw Settings")
            } footer: {
                Text("Same values as in AxiDraw Control. Times follow the AxiDraw motion model (acceleration, slowing down in corners, pen-lift servo time) in high-resolution mode with the standard servo. Paths are plotted in file order; each layer is timed as its own job, starting and ending at the home corner.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Catalog") {
                LabeledContent("Location") {
                    Text(library.catalogURL?.path ?? "None").textSelection(.enabled).lineLimit(3)
                }
                Button("Show in Finder") { library.revealCatalog() }
                    .disabled(library.catalogURL == nil)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}
