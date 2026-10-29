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
    private var plot = PlotSettingsStorage()

    var body: some View {
        Form {
            Section {
                TextField("Pen-down speed (mm/s)", value: plot.$drawSpeed, format: .number)
                TextField("Pen-up speed (mm/s)", value: plot.$travelSpeed, format: .number)
                TextField("Pen lift + lower (s)", value: plot.$liftTime, format: .number)
            } header: {
                Text("Plot Time Estimate")
            } footer: {
                Text("A rough estimate: constant speeds, no acceleration. Each layer is timed as its own job (one pen), starting and ending at the home corner.")
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
