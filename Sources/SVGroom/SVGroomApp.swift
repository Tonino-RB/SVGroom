import SwiftUI

@main
struct SVGroomApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var library = Library()

    var body: some Scene {
        Window("SVGroom", id: "main") {
            ContentView()
                .environment(library)
                .frame(minWidth: 960, minHeight: 600)
                .onAppear { appDelegate.library = library }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    library.rescanIfStale()
                }
        }
        .defaultSize(width: 1440, height: 900)
        .commands { AppCommands(library: library) }

        Settings {
            SettingsView().environment(library)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var library: Library?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { library?.saveNow(wait: true) }
    }
}

struct AppCommands: Commands {
    let library: Library

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Catalog…") { library.newCatalogPanel() }
            Button("Open Catalog…") { library.openCatalogPanel() }
                .keyboardShortcut("o", modifiers: [.command, .option])
            Button("Show Catalog in Finder") { library.revealCatalog() }
            Divider()
            Button("Add Folder…") { library.addFolderPanel() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            Button("Synchronize Folders") { library.rescan() }
                .keyboardShortcut("r")
            Button("Find Missing Files in Folder…") { library.findMissingPanel() }
        }

        CommandMenu("SVG") {
            Menu("Set Rating") {
                ForEach(0...5, id: \.self) { r in
                    Button(r == 0 ? "No Rating   (0)" : String(repeating: "★", count: r) + "   (\(r))") { library.setRating(r) }
                }
            }
            Menu("Set Flag") {
                Button("Picked   (P)") { library.setFlag(.picked) }
                Button("Rejected   (X)") { library.setFlag(.rejected) }
                Button("Unflagged   (U)") { library.setFlag(.none) }
            }
            Menu("Set Color Label") {
                ForEach(ColorLabel.allCases.dropFirst(), id: \.self) { l in
                    Button(l.title) { library.toggleLabel(l) }
                }
            }
            Divider()
            Button("Reveal in Finder") { library.reveal(library.targetItems) }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Open in Default App") { library.openInDefaultApp(library.targetItems) }
                .keyboardShortcut("e")
            Divider()
            Button("Move to Trash…") { library.requestTrash(library.targetIDs) }
                .keyboardShortcut(.delete, modifiers: .command)
            Button("Move Rejected to Trash…") {
                library.requestTrash(library.displayed.filter { $0.flag == .rejected }.map(\.id))
            }
            Button("Remove Missing from Catalog") { library.removeMissingFromCatalog(library.targetIDs) }
            Divider()
            Toggle("Auto Advance After Rating", isOn: Bindable(library).autoAdvance)
        }
    }
}
