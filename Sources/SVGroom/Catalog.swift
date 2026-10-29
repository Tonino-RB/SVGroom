import Foundation
import Observation
import SVGroomCore

enum Flag: String, Codable, CaseIterable {
    case none, picked, rejected
}

enum ColorLabel: String, Codable, CaseIterable {
    case none, red, yellow, green, blue, purple
}

/// On-disk catalog: one JSON file, wherever the user chose to keep it.
struct CatalogFile: Codable {
    var version = 1
    var roots: [RootFolder]
    /// Linked folder groups (absent in older catalogs).
    var links: [[String]]?
    var entries: [Entry]
}

struct RootFolder: Codable, Identifiable, Hashable {
    var id = UUID()
    var path: String
    /// Lets a moved/renamed root folder be found again.
    var bookmark: Data?
}

/// Codable snapshot of an `SVGItem`.
struct Entry: Codable {
    var id: UUID
    var path: String
    var bookmark: Data?
    var fileSize: Int64
    var modified: Date
    var contentHash: String?
    var rating: Int
    var flag: Flag
    var label: ColorLabel
    var added: Date
    var analysis: SVGAnalysis?
}

extension Entry {
    /// An analysis saved by an older version that no longer decodes is dropped and recomputed.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        path = try c.decode(String.self, forKey: .path)
        bookmark = try c.decodeIfPresent(Data.self, forKey: .bookmark)
        fileSize = try c.decode(Int64.self, forKey: .fileSize)
        modified = try c.decode(Date.self, forKey: .modified)
        contentHash = try c.decodeIfPresent(String.self, forKey: .contentHash)
        rating = try c.decode(Int.self, forKey: .rating)
        flag = try c.decode(Flag.self, forKey: .flag)
        label = try c.decode(ColorLabel.self, forKey: .label)
        added = try c.decode(Date.self, forKey: .added)
        analysis = try? c.decodeIfPresent(SVGAnalysis.self, forKey: .analysis)
    }
}

@Observable
final class SVGItem: Identifiable {
    let id: UUID
    var path: String
    var bookmark: Data?
    var fileSize: Int64
    var modified: Date
    var contentHash: String?
    var rating = 0
    var flag = Flag.none
    var label = ColorLabel.none
    let added: Date
    var analysis: SVGAnalysis?

    // Runtime state, not saved.
    var missing = false
    /// Cloud placeholder (e.g. OneDrive "online only"): reading it triggers a download.
    var dataless = false

    var url: URL { URL(fileURLWithPath: path) }
    var name: String { (path as NSString).lastPathComponent }
    var folder: String { (path as NSString).deletingLastPathComponent }
    var hasUserMetadata: Bool { rating > 0 || flag != .none || label != .none }

    init(path: String, fileSize: Int64, modified: Date) {
        id = UUID()
        self.path = path
        self.fileSize = fileSize
        self.modified = modified
        added = Date()
    }

    init(_ e: Entry) {
        id = e.id; path = e.path; bookmark = e.bookmark; fileSize = e.fileSize; modified = e.modified
        contentHash = e.contentHash; rating = e.rating; flag = e.flag; label = e.label; added = e.added
        analysis = e.analysis
    }

    var entry: Entry {
        Entry(id: id, path: path, bookmark: bookmark, fileSize: fileSize, modified: modified,
              contentHash: contentHash, rating: rating, flag: flag, label: label, added: added, analysis: analysis)
    }

    func makeBookmarkIfNeeded() {
        guard bookmark == nil, !missing else { return }
        bookmark = try? url.bookmarkData()
    }
}

/// Folder in the sidebar tree, derived from the catalogued file paths.
final class FolderNode: Identifiable {
    let path: String
    let name: String
    var count = 0
    var missing = false
    var children: [FolderNode]?
    var id: String { path }

    init(path: String, name: String? = nil) {
        self.path = path
        self.name = name ?? (path as NSString).lastPathComponent
    }
}

enum SidebarSource: Hashable {
    case all, missing
    case folder(String)
}

enum FlagFilter: String, CaseIterable {
    case all = "All", picked = "Picked", unflagged = "Unflagged", rejected = "Rejected", notRejected = "Not Rejected"
}

enum SortKey: String, CaseIterable {
    case name = "Name", modified = "Date Modified", rating = "Rating", plotTime = "Plot Time", size = "File Size"
}

struct Filter: Equatable {
    var text = ""
    var minRating = 0
    var flag = FlagFilter.all
    var label: ColorLabel?
    /// Paper format name ("A3", "Custom"…).
    var format: String?

    var isActive: Bool { self != Filter() }
    var dependsOnAnalysis: Bool { format != nil }
}

enum ViewMode: String {
    case grid, loupe
}
