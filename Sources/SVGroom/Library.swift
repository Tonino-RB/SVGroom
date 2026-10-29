import AppKit
import Observation
import SVGroomCore
import UniformTypeIdentifiers

extension PlotSettings {
    /// UserDefaults key, label in Settings, and setting.
    static let fields: [(key: String, label: String, path: WritableKeyPath<PlotSettings, Double>)] = [
        ("plot.penDownSpeed", "Pen-down speed", \.penDownSpeed),
        ("plot.penUpSpeed", "Pen-up speed", \.penUpSpeed),
        ("plot.acceleration", "Acceleration", \.acceleration),
        ("plot.penUpHeight", "Pen up position", \.penUpHeight),
        ("plot.penDownHeight", "Pen down position", \.penDownHeight),
        ("plot.penRaiseRate", "Pen raising speed", \.penRaiseRate),
        ("plot.penLowerRate", "Pen lowering speed", \.penLowerRate),
    ]

    static func registerDefaults() {
        let d = PlotSettings()
        UserDefaults.standard.register(defaults: Dictionary(uniqueKeysWithValues: fields.map { ($0.key, d[keyPath: $0.path]) }))
    }

    static var current: PlotSettings {
        var s = PlotSettings()
        for f in fields { s[keyPath: f.path] = UserDefaults.standard.double(forKey: f.key) }
        return s
    }
}

/// The open catalog plus everything the browser shows: folders, filters, selection, analysis queue.
@MainActor @Observable
final class Library {
    static let catalogType = UTType(filenameExtension: "svgroom", conformingTo: .json) ?? .json
    private static let lastCatalogKey = "lastCatalogPath"

    // MARK: Catalog
    private(set) var catalogURL: URL?
    var catalogProblem: String?
    private(set) var roots: [RootFolder] = []
    private(set) var missingRoots: Set<UUID> = []
    /// Folders that share ratings, flags and labels by relative path.
    private(set) var links: [[String]] = []
    private(set) var items: [UUID: SVGItem] = [:]
    private(set) var folderTree: [FolderNode] = []
    private(set) var missingCount = 0
    private(set) var isScanning = false
    private(set) var analysisPending = 0

    // MARK: Browsing
    var source: SidebarSource? = .all { didSet { if oldValue != source { sourceChanged(from: oldValue) } } }
    var includeSubfolders = true { didSet { refreshDisplay() } }
    var filter = Filter() { didSet { if oldValue != filter { refreshDisplay() } } }
    var sort = SortKey.name { didSet { refreshDisplay() } }
    var sortAscending = true { didSet { refreshDisplay() } }
    private(set) var displayed: [SVGItem] = []
    var selection: Set<UUID> = []
    var focusedID: UUID? {
        didSet {
            guard oldValue != focusedID else { return }
            layerOverrides = [:]
            prioritizeFocused()
        }
    }
    var viewMode = ViewMode.grid
    var loupeZoom: CGFloat = 1
    /// Layer visibility changes for the focused file (preview + stats only, the file is not modified).
    var layerOverrides: [Int: Bool] = [:]
    var previewMode = PreviewMode.normal
    /// Sheet, size and pens of the simulation preview, kept between files and launches.
    var simulation = UserDefaults.standard.data(forKey: "simulation")
        .flatMap { try? JSONDecoder().decode(SimulationSettings.self, from: $0) } ?? SimulationSettings() {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(simulation), forKey: "simulation") }
    }
    var autoAdvance = UserDefaults.standard.bool(forKey: "autoAdvance") {
        didSet { UserDefaults.standard.set(autoAdvance, forKey: "autoAdvance") }
    }

    // MARK: Dialogs
    var pendingTrash: [UUID]?
    var pendingRootRemoval: RootFolder?
    var alertMessage: String?

    @ObservationIgnored var gridColumns = 1
    @ObservationIgnored private var pathIndex: [String: UUID] = [:]
    @ObservationIgnored private var displayIndex: [UUID: Int] = [:]
    /// The file last focused in each sidebar source, restored when coming back to it.
    @ObservationIgnored private var lastFocus: [SidebarSource: UUID] = [:]
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let saveQueue = DispatchQueue(label: "SVGroom.catalog-save")
    @ObservationIgnored private var rescanRequested = false
    @ObservationIgnored private var lastScan = Date.distantPast
    @ObservationIgnored private var analysisQueue: [UUID] = []
    @ObservationIgnored private var analysisRunning = 0
    private var analysisFailed: Set<UUID> = []
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    /// Settings the plot times are computed with; files are re-analysed when they change.
    @ObservationIgnored private var plotSettings: PlotSettings
    @ObservationIgnored private var settingsTask: Task<Void, Never>?

    init() {
        PlotSettings.registerDefaults()
        plotSettings = .current
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.plotSettingsMayHaveChanged() }
        }
        if let p = UserDefaults.standard.string(forKey: Self.lastCatalogKey) {
            if FileManager.default.fileExists(atPath: p) {
                open(URL(fileURLWithPath: p))
            } else {
                catalogProblem = "The last catalog was not found at \(p). It may have been moved or renamed — open it from its new location."
            }
        }
    }

    var focused: SVGItem? { focusedID.flatMap { items[$0] } }

    /// Items the metadata commands act on: the selection, in display order.
    var targetItems: [SVGItem] {
        let ids = selection.isEmpty ? Set(focusedID.map { [$0] } ?? []) : selection
        return displayed.filter { ids.contains($0.id) }
    }

    var targetIDs: [UUID] { targetItems.map(\.id) }

    var availableFormats: [String] {
        let names = Set(items.values.compactMap { $0.analysis?.format?.name })
        return (PaperFormat.all.map(\.name) + [PaperFormat.customName]).filter(names.contains)
    }

    // MARK: - Catalog file

    func newCatalogPanel() {
        let panel = NSSavePanel()
        panel.title = "New Catalog"
        panel.message = "Choose where the catalog lives. It stores ratings, flags, labels and file locations."
        panel.allowedContentTypes = [Self.catalogType]
        panel.nameFieldStringValue = "SVGroom Catalog.svgroom"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try JSONEncoder().encode(CatalogFile(roots: [], entries: [])).write(to: url, options: .atomic)
            open(url)
        } catch {
            alertMessage = "Could not create the catalog: \(error.localizedDescription)"
        }
    }

    func openCatalogPanel() {
        let panel = NSOpenPanel()
        panel.title = "Open Catalog"
        panel.allowedContentTypes = [Self.catalogType]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url)
    }

    func open(_ url: URL) {
        do {
            let file = try JSONDecoder().decode(CatalogFile.self, from: Data(contentsOf: url))
            if catalogURL != nil { saveNow() }
            catalogURL = url
            catalogProblem = nil
            UserDefaults.standard.set(url.path, forKey: Self.lastCatalogKey)
            roots = file.roots
            links = file.links ?? []
            missingRoots = []
            items = Dictionary(file.entries.map { ($0.id, SVGItem($0)) }, uniquingKeysWith: { a, _ in a })
            pathIndex = Dictionary(items.values.map { ($0.path, $0.id) }, uniquingKeysWith: { a, _ in a })
            analysisFailed = []
            selection = []
            focusedID = nil
            source = .all
            lastFocus = [:]
            rebuildTree()
            refreshDisplay()
            rescan()
        } catch {
            catalogProblem = "Could not open \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func revealCatalog() {
        if let catalogURL { NSWorkspace.shared.activateFileViewerSelecting([catalogURL]) }
    }

    private func markDirty() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow(wait: Bool = false) {
        saveTask?.cancel()
        saveTask = nil
        guard let url = catalogURL else { return }
        let file = CatalogFile(roots: roots, links: links, entries: items.values.map(\.entry))
        let work = {
            do {
                try JSONEncoder().encode(file).write(to: url, options: .atomic)
            } catch {
                DispatchQueue.main.async { self.alertMessage = "Could not save the catalog: \(error.localizedDescription)" }
            }
        }
        if wait { saveQueue.sync(execute: work) } else { saveQueue.async(execute: work) }
    }

    /// Call after adding, removing or moving items.
    private func catalogChanged() {
        rebuildTree()
        refreshDisplay()
        markDirty()
    }

    // MARK: - Root folders

    func addFolderPanel() {
        let panel = NSOpenPanel()
        panel.title = "Add Folders"
        panel.message = "SVG files in these folders and all their subfolders are added to the catalog."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(addRoot)
        if let first = panel.urls.first { source = .folder(first.standardizedFileURL.path) }
        rescan()
    }

    func addRoot(_ url: URL) {
        let path = url.standardizedFileURL.path
        if roots.contains(where: { path == $0.path || path.hasPrefix($0.path + "/") }) { return }
        // A new parent folder absorbs roots inside it.
        roots.removeAll { $0.path.hasPrefix(path + "/") }
        roots.append(RootFolder(path: path, bookmark: try? url.bookmarkData()))
        roots.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        catalogChanged()
    }

    func root(at path: String) -> RootFolder? { roots.first { $0.path == path } }

    func confirmRootRemoval() {
        guard let root = pendingRootRemoval else { return }
        pendingRootRemoval = nil
        let prefix = root.path + "/"
        for item in items.values where item.path.hasPrefix(prefix) { removeItem(item) }
        roots.removeAll { $0.id == root.id }
        links = links.map { $0.filter { $0 != root.path && !$0.hasPrefix(prefix) } }.filter { $0.count > 1 }
        if case .folder(let p)? = source, p == root.path || p.hasPrefix(prefix) { source = .all }
        catalogChanged()
    }

    func locateRootPanel(_ root: RootFolder) {
        let panel = NSOpenPanel()
        panel.title = "Locate “\((root.path as NSString).lastPathComponent)”"
        panel.message = "Was: \(root.path)"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        relocateRoot(root, to: url.standardizedFileURL.path)
        rescan()
    }

    private func relocateRoot(_ root: RootFolder, to newPath: String) {
        guard let i = roots.firstIndex(where: { $0.id == root.id }) else { return }
        let old = root.path
        for item in Array(items.values) where item.path.hasPrefix(old + "/") {
            setPath(item, newPath + item.path.dropFirst(old.count))
        }
        roots[i].path = newPath
        roots[i].bookmark = try? URL(fileURLWithPath: newPath).bookmarkData()
        links = links.map { $0.map { $0 == old || $0.hasPrefix(old + "/") ? newPath + $0.dropFirst(old.count) : $0 } }
        missingRoots.remove(root.id)
        if source == .folder(old) { source = .folder(newPath) }
        catalogChanged()
    }

    // MARK: - Linked folders

    func linkFolderPanel(_ path: String) {
        let panel = NSOpenPanel()
        panel.title = "Link “\((path as NSString).lastPathComponent)” With…"
        panel.message = "Ratings, flags and labels set on a file are also set on the file at the same place in the linked folders."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: (path as NSString).deletingLastPathComponent)
        guard panel.runModal() == .OK else { return }
        links = FolderLinks.link(path, with: panel.urls.map(\.standardizedFileURL.path), in: links)
        markDirty()
    }

    func unlinkFolder(_ path: String) {
        links = FolderLinks.unlink(path, in: links)
        markDirty()
    }

    func linkedFolders(of path: String) -> [String] {
        links.first { $0.contains(path) }?.filter { $0 != path } ?? []
    }

    // MARK: - Scanning

    func rescanIfStale() {
        if Date().timeIntervalSince(lastScan) > 15 { rescan() }
    }

    func rescan() {
        guard catalogURL != nil else { return }
        guard !isScanning else { rescanRequested = true; return }
        isScanning = true
        lastScan = Date()
        let paths = roots.map(\.path)
        Task {
            let results = await Task.detached(priority: .userInitiated) { paths.map(FolderScanner.scan) }.value
            apply(results)
            isScanning = false
            if rescanRequested {
                rescanRequested = false
                rescan()
            }
        }
    }

    private func apply(_ results: [ScanResult]) {
        var seen = Set<String>()
        var newFiles: [ScannedFile] = []
        var lostRoots: [RootFolder] = []

        for r in results {
            guard let root = root(at: r.root) else { continue } // removed while scanning
            guard r.exists else { lostRoots.append(root); continue }
            for f in r.files {
                seen.insert(f.path)
                if let id = pathIndex[f.path], let item = items[id] {
                    update(item, from: f)
                } else {
                    newFiles.append(f)
                }
            }
        }

        // A moved root folder is followed through its bookmark.
        var relocated = false
        for root in lostRoots {
            if let p = Self.resolve(root.bookmark), p != root.path, Self.isDirectory(p), self.root(at: p) == nil {
                relocateRoot(root, to: p)
                relocated = true
            }
        }
        missingRoots = Set(lostRoots.map(\.id))
        if relocated { rescanRequested = true }

        // Files that are no longer where the catalog expects them.
        var lost = items.values.filter { !seen.contains($0.path) }
        var newByPath = Dictionary(newFiles.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })

        // 1. Bookmarks follow renames and moves on the same volume.
        lost.removeAll { item in
            guard item.bookmark != nil, let p = Self.resolve(item.bookmark), let f = newByPath[p] else { return false }
            relink(item, to: f)
            newByPath[p] = nil
            return true
        }

        // 2. Same file name and size, when unambiguous.
        func key(_ name: String, _ size: Int64) -> String { "\(name)|\(size)" }
        var lostByKey = Dictionary(grouping: lost) { key($0.name, $0.fileSize) }
        let newByKey = Dictionary(grouping: newByPath.values) { key(($0.path as NSString).lastPathComponent, $0.size) }
        for (k, files) in newByKey where files.count == 1 {
            guard let candidates = lostByKey[k], candidates.count == 1 else { continue }
            relink(candidates[0], to: files[0])
            newByPath[files[0].path] = nil
            lostByKey[k] = nil
        }

        for f in newByPath.values {
            let item = SVGItem(path: f.path, fileSize: f.size, modified: f.modified)
            item.dataless = f.dataless
            items[item.id] = item
            pathIndex[f.path] = item.id
        }
        for item in lostByKey.values.joined() { item.missing = true }

        catalogChanged()
    }

    private func update(_ item: SVGItem, from f: ScannedFile) {
        if item.fileSize != f.size || item.modified != f.modified {
            item.fileSize = f.size
            item.modified = f.modified
            item.analysis = nil
            item.contentHash = nil
            analysisFailed.remove(item.id)
        }
        item.missing = false
        item.dataless = f.dataless
    }

    private func relink(_ item: SVGItem, to f: ScannedFile) {
        setPath(item, f.path)
        update(item, from: f)
        item.bookmark = nil
        if item.hasUserMetadata { item.makeBookmarkIfNeeded() }
    }

    private func setPath(_ item: SVGItem, _ path: String) {
        if pathIndex[item.path] == item.id { pathIndex[item.path] = nil }
        item.path = path
        pathIndex[path] = item.id
    }

    private func removeItem(_ item: SVGItem) {
        items[item.id] = nil
        if pathIndex[item.path] == item.id { pathIndex[item.path] = nil }
        selection.remove(item.id)
    }

    private static func resolve(_ bookmark: Data?) -> String? {
        guard let bookmark else { return nil }
        var stale = false
        let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                           relativeTo: nil, bookmarkDataIsStale: &stale)
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url.standardizedFileURL.path
    }

    private static func isDirectory(_ path: String) -> Bool {
        var d: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &d) && d.boolValue
    }

    // MARK: - Missing files

    func locatePanel(_ item: SVGItem) {
        let panel = NSOpenPanel()
        panel.title = "Locate “\(item.name)”"
        panel.message = "Was: \(item.path)"
        panel.allowedContentTypes = [.svg]
        if Self.isDirectory(item.folder) { panel.directoryURL = URL(fileURLWithPath: item.folder) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.standardizedFileURL.path
        if let other = pathIndex[path], other != item.id {
            alertMessage = "“\(url.lastPathComponent)” is already in the catalog as another entry."
            return
        }
        let v = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        relink(item, to: ScannedFile(path: path, size: Int64(v?.fileSize ?? 0),
                                     modified: v?.contentModificationDate ?? .distantPast,
                                     dataless: FolderScanner.isDataless(path)))
        let folder = url.deletingLastPathComponent()
        addRoot(folder)
        // Other missing files are often in the same place.
        if items.values.contains(where: \.missing) {
            searchForMissing(in: folder, report: false)
        } else {
            catalogChanged()
            rescan()
        }
    }

    func findMissingPanel() {
        guard items.values.contains(where: \.missing) else {
            alertMessage = "No files are missing."
            return
        }
        let panel = NSOpenPanel()
        panel.title = "Find Missing Files"
        panel.message = "Choose a folder to search (subfolders included). Matches are found by name and size, then by content."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        searchForMissing(in: url, report: true)
    }

    private func searchForMissing(in folder: URL, report: Bool) {
        let lost = items.values.filter(\.missing)
        let dir = folder.standardizedFileURL.path
        let hashedSizes = Set(lost.filter { $0.contentHash != nil }.map(\.fileSize))
        Task {
            let (files, hashes) = await Task.detached(priority: .userInitiated) { () -> ([ScannedFile], [String: String]) in
                let files = FolderScanner.scan(dir).files
                var hashes: [String: String] = [:]
                for f in files where hashedSizes.contains(f.size) && !f.dataless {
                    if let d = try? Data(contentsOf: URL(fileURLWithPath: f.path), options: .mappedIfSafe) {
                        hashes[f.path] = SVGAnalyzer.contentHash(d)
                    }
                }
                return (files, hashes)
            }.value

            var free = files.filter { pathIndex[$0.path] == nil }
            var found = 0
            for item in lost where item.missing {
                let byName = free.firstIndex { ($0.path as NSString).lastPathComponent == item.name && $0.size == item.fileSize }
                let byHash = item.contentHash.flatMap { h in free.firstIndex { hashes[$0.path] == h } }
                guard let i = byName ?? byHash else { continue }
                relink(item, to: free.remove(at: i))
                found += 1
            }
            if found > 0 { addRoot(folder) }
            if report {
                alertMessage = found == 0
                    ? "None of the \(lost.count) missing files were found in “\(folder.lastPathComponent)”."
                    : "Found \(found) of \(lost.count) missing files. “\(folder.lastPathComponent)” is now part of the catalog."
            }
            catalogChanged()
            rescan()
        }
    }

    func removeMissingFromCatalog(_ ids: [UUID]) {
        for id in ids { if let item = items[id], item.missing { removeItem(item) } }
        catalogChanged()
    }

    // MARK: - Display

    func refreshDisplay() {
        let oldIndex = focusedID.flatMap { displayIndex[$0] }
        var list = items.values.filter { matchesSource($0) && matchesFilter($0) }
        list.sort { a, b in
            let order: ComparisonResult
            switch sort {
            case .name: order = a.name.localizedStandardCompare(b.name)
            case .modified: order = Self.compare(a.modified, b.modified)
            case .rating: order = Self.compare(a.rating, b.rating)
            case .size: order = Self.compare(a.fileSize, b.fileSize)
            case .plotTime:
                order = Self.compare(a.analysis?.fileTotals.seconds ?? -1, b.analysis?.fileTotals.seconds ?? -1)
            }
            if order == .orderedSame { return a.path.localizedStandardCompare(b.path) == .orderedAscending }
            return sortAscending ? order == .orderedAscending : order == .orderedDescending
        }
        displayed = list
        displayIndex = Dictionary(uniqueKeysWithValues: list.enumerated().map { ($1.id, $0) })
        selection = selection.filter { displayIndex[$0] != nil }
        if focusedID.flatMap({ displayIndex[$0] }) == nil {
            focusedID = list.isEmpty ? nil : list[min(oldIndex ?? 0, list.count - 1)].id
            if let f = focusedID { selection.insert(f) }
        }
        missingCount = items.values.reduce(0) { $0 + ($1.missing ? 1 : 0) }
        scheduleAnalysis()
    }

    /// A new source opens on its first file, or on the one left focused there last time.
    private func sourceChanged(from old: SidebarSource?) {
        if let old { lastFocus[old] = focusedID }
        focusedID = nil
        selection = []
        refreshDisplay()
        if let id = source.flatMap({ lastFocus[$0] }), displayIndex[id] != nil { focus(id) }
    }

    private static func compare<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
        a < b ? .orderedAscending : (a > b ? .orderedDescending : .orderedSame)
    }

    private func matchesSource(_ item: SVGItem) -> Bool {
        switch source ?? .all {
        case .all: return true
        case .missing: return item.missing
        case .folder(let p): return includeSubfolders ? item.path.hasPrefix(p + "/") : item.folder == p
        }
    }

    private func matchesFilter(_ item: SVGItem) -> Bool {
        let f = filter
        if !f.text.isEmpty && !item.name.localizedCaseInsensitiveContains(f.text) { return false }
        if item.rating < f.minRating { return false }
        switch f.flag {
        case .all: break
        case .picked: if item.flag != .picked { return false }
        case .unflagged: if item.flag != .none { return false }
        case .rejected: if item.flag != .rejected { return false }
        case .notRejected: if item.flag == .rejected { return false }
        }
        if let l = f.label, item.label != l { return false }
        if let fmt = f.format, item.analysis?.format?.name != fmt { return false }
        return true
    }

    /// Re-filters soon, coalescing bursts (e.g. analysis results arriving).
    private func refreshSoon() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.refreshDisplay()
        }
    }

    // MARK: - Selection & navigation

    func focus(_ id: UUID) {
        focusedID = id
        selection = [id]
    }

    func click(_ id: UUID, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
            focusedID = id
        } else if modifiers.contains(.shift), let from = focusedID.flatMap({ displayIndex[$0] }), let to = displayIndex[id] {
            selection.formUnion(displayed[min(from, to)...max(from, to)].map(\.id))
            focusedID = id
        } else {
            focus(id)
        }
    }

    /// How far up/down arrows move: a whole row in the grid, one file elsewhere.
    var rowStep: Int { viewMode == .grid && previewMode == .normal ? gridColumns : 1 }

    func moveFocus(by delta: Int) {
        guard !displayed.isEmpty else { return }
        let i = focusedID.flatMap { displayIndex[$0] } ?? -1
        focus(displayed[min(max(i + delta, 0), displayed.count - 1)].id)
    }

    func selectAll() { selection = Set(displayed.map(\.id)) }

    // MARK: - Metadata

    func setRating(_ r: Int, advance: Bool = false) { applyMetadata(advance: advance) { $0.rating = r } }
    func setFlag(_ f: Flag, advance: Bool = false) { applyMetadata(advance: advance) { $0.flag = f } }

    /// Same label again removes it, like Lightroom.
    func toggleLabel(_ l: ColorLabel, advance: Bool = false) {
        let clear = targetItems.allSatisfy { $0.label == l }
        applyMetadata(advance: advance) { $0.label = clear ? .none : l }
    }

    private func applyMetadata(advance: Bool, _ change: (SVGItem) -> Void) {
        let targets = targetItems
        guard !targets.isEmpty else { return }
        // The same files in linked folders get the same change.
        var all = targets
        var ids = Set(targets.map(\.id))
        for path in targets.flatMap({ FolderLinks.counterparts(of: $0.path, in: links) }) {
            if let id = pathIndex[path], ids.insert(id).inserted, let item = items[id] { all.append(item) }
        }
        for item in all {
            change(item)
            item.makeBookmarkIfNeeded()
        }
        markDirty()
        if advance && autoAdvance && targets.count == 1 { moveFocus(by: 1) }
        if filter.isActive || sort == .rating { refreshDisplay() }
    }

    func isLayerVisible(_ index: Int, in analysis: SVGAnalysis) -> Bool {
        layerOverrides[index] ?? !analysis.layers[index].hiddenInFile
    }

    func setLayer(_ index: Int, visible: Bool, in analysis: SVGAnalysis) {
        layerOverrides[index] = visible == !analysis.layers[index].hiddenInFile ? nil : visible
    }

    // MARK: - Files

    func reveal(_ items: [SVGItem]) {
        NSWorkspace.shared.activateFileViewerSelecting(items.filter { !$0.missing }.map(\.url))
    }

    func openInDefaultApp(_ items: [SVGItem]) {
        for item in items where !item.missing { NSWorkspace.shared.open(item.url) }
    }

    func requestTrash(_ ids: [UUID]) {
        if !ids.isEmpty { pendingTrash = ids }
    }

    func confirmTrash() {
        guard let ids = pendingTrash else { return }
        pendingTrash = nil
        var failures: [String] = []
        for id in ids {
            guard let item = items[id] else { continue }
            if !item.missing {
                do { try FileManager.default.trashItem(at: item.url, resultingItemURL: nil) } catch {
                    failures.append(item.name)
                    continue
                }
            }
            removeItem(item)
        }
        catalogChanged()
        if !failures.isEmpty { alertMessage = "Could not move to Trash: \(failures.joined(separator: ", "))" }
    }

    // MARK: - Analysis (background, never blocks browsing)

    private func needsAnalysis(_ item: SVGItem) -> Bool {
        guard !item.missing, !analysisFailed.contains(item.id) else { return false }
        guard let a = item.analysis else { return true }
        return a.version != SVGAnalyzer.version || a.settings != plotSettings
    }

    /// Recomputes plot times once the settings have stopped changing.
    private func plotSettingsMayHaveChanged() {
        let s = PlotSettings.current
        guard s != plotSettings else { return }
        plotSettings = s
        settingsTask?.cancel()
        settingsTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            self?.scheduleAnalysis()
        }
    }

    /// Analyses the displayed files in order; online-only files are skipped unless focused.
    private func scheduleAnalysis() {
        var queue: [UUID] = []
        if let f = focused, needsAnalysis(f) { queue.append(f.id) }
        queue += displayed.lazy.filter { !$0.dataless && self.needsAnalysis($0) }.map(\.id)
        analysisQueue = queue
        pumpAnalysis()
    }

    private func prioritizeFocused() {
        guard let f = focused, needsAnalysis(f) else { return }
        analysisQueue.removeAll { $0 == f.id }
        analysisQueue.insert(f.id, at: 0)
        pumpAnalysis()
    }

    /// Explicit request, e.g. for an online-only file (downloads it).
    func analyzeNow(_ item: SVGItem) {
        analysisFailed.remove(item.id)
        analysisQueue.insert(item.id, at: 0)
        pumpAnalysis()
    }

    private func pumpAnalysis() {
        while analysisRunning < 2, !analysisQueue.isEmpty {
            let id = analysisQueue.removeFirst()
            guard let item = items[id], needsAnalysis(item) else { continue }
            analysisRunning += 1
            let url = item.url, size = item.fileSize, modified = item.modified, settings = plotSettings
            Task {
                let result = await Task.detached(priority: .utility) { try? SVGAnalyzer.analyze(url: url, settings: settings) }.value
                analysisRunning -= 1
                if let item = items[id], item.fileSize == size, item.modified == modified {
                    if let result, let a = result.analysis {
                        item.analysis = a
                        item.contentHash = result.hash
                        markDirty()
                        if filter.dependsOnAnalysis || sort == .plotTime { refreshSoon() }
                    } else {
                        analysisFailed.insert(id)
                    }
                }
                pumpAnalysis()
            }
        }
        analysisPending = analysisQueue.count + analysisRunning
    }

    func didFailAnalysis(_ item: SVGItem) -> Bool { analysisFailed.contains(item.id) }

    // MARK: - Folder tree

    private func rebuildTree() {
        var nodes: [String: FolderNode] = [:]
        let tops = roots.map { root -> FolderNode in
            let n = FolderNode(path: root.path)
            n.missing = missingRoots.contains(root.id)
            nodes[root.path] = n
            return n
        }
        for item in items.values {
            guard let root = roots.first(where: { item.path.hasPrefix($0.path + "/") }) else { continue }
            var dir = item.folder
            while dir.count >= root.path.count {
                let node = nodes[dir] ?? {
                    let n = FolderNode(path: dir)
                    nodes[dir] = n
                    return n
                }()
                node.count += 1
                dir = (dir as NSString).deletingLastPathComponent
            }
        }
        for (path, node) in nodes where root(at: path) == nil {
            if let parent = nodes[(path as NSString).deletingLastPathComponent] {
                parent.children = (parent.children ?? []) + [node]
            }
        }
        for node in nodes.values {
            node.children?.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        folderTree = tops
    }
}
