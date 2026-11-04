import Foundation
import Observation
import SVGroomCore

enum Flag: String, Codable, CaseIterable {
    case none, picked, rejected
}

enum ColorLabel: String, Codable, CaseIterable {
    case none, red, yellow, green, blue, purple
}

/// One size per file.
enum SizeTag: String, Codable, CaseIterable {
    case none, xs, s, m, l, xl
    var title: String { rawValue.uppercased() }
}

/// On-disk catalog: one JSON file, wherever the user chose to keep it.
struct CatalogFile: Codable {
    var version = 1
    var roots: [RootFolder]
    /// Linked folder groups (absent in older catalogs).
    var links: [[String]]?
    /// Custom tags, in the order they are listed (absent in older catalogs).
    var keywords: [String]?
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
    var sizeTag: SizeTag?
    var keywords: [String]?
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
        sizeTag = try c.decodeIfPresent(SizeTag.self, forKey: .sizeTag)
        keywords = try c.decodeIfPresent([String].self, forKey: .keywords)
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
    var sizeTag = SizeTag.none
    /// Custom tags.
    var keywords: Set<String> = []
    let added: Date
    var analysis: SVGAnalysis?

    // Runtime state, not saved.
    var missing = false
    /// Cloud placeholder (e.g. OneDrive "online only"): reading it triggers a download.
    var dataless = false

    var url: URL { URL(fileURLWithPath: path) }
    var name: String { (path as NSString).lastPathComponent }
    var folder: String { (path as NSString).deletingLastPathComponent }
    var hasUserMetadata: Bool { rating > 0 || flag != .none || label != .none || sizeTag != .none || !keywords.isEmpty }
    /// Rating, flag, label, size and tags; nil when none is set.
    var tags: Tags? {
        get { hasUserMetadata ? Tags(rating: rating, flag: flag, label: label, sizeTag: sizeTag, keywords: keywords) : nil }
        set {
            rating = newValue?.rating ?? 0; flag = newValue?.flag ?? .none; label = newValue?.label ?? .none
            sizeTag = newValue?.sizeTag ?? .none; keywords = newValue?.keywords ?? []
        }
    }

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
        sizeTag = e.sizeTag ?? .none; keywords = Set(e.keywords ?? [])
    }

    var entry: Entry {
        Entry(id: id, path: path, bookmark: bookmark, fileSize: fileSize, modified: modified,
              contentHash: contentHash, rating: rating, flag: flag, label: label, added: added, analysis: analysis,
              sizeTag: sizeTag == .none ? nil : sizeTag, keywords: keywords.isEmpty ? nil : keywords.sorted())
    }

    func makeBookmarkIfNeeded() {
        guard bookmark == nil, !missing else { return }
        bookmark = try? url.bookmarkData()
    }
}

/// What linked folders share.
struct Tags: Equatable {
    var rating: Int
    var flag: Flag
    var label: ColorLabel
    var sizeTag: SizeTag
    var keywords: Set<String>
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
    var sizeTag: SizeTag?
    /// Custom tag.
    var keyword: String?

    var isActive: Bool { self != Filter() }
    var dependsOnAnalysis: Bool { format != nil }
}

enum ViewMode: String {
    case grid, loupe
}

/// Normal browsing, the simulated plot alone, the original and the simulation side by side,
/// or the same file in every linked folder side by side.
enum PreviewMode: String {
    case normal, simulation, compare, versions
}

/// A linked folder and its file at the focused file's relative path (nil when it has none).
struct LinkedVersion: Identifiable {
    let folder: String
    let item: SVGItem?
    var id: String { folder }
}

/// Tags to sync across a link group, waiting for review.
struct TagSyncReview: Identifiable {
    let id = UUID()
    let folders: [String]
    /// Untagged files and the tags their linked versions agree on.
    let copies: [(item: SVGItem, tags: Tags)]
    /// The versions of each file whose tags differ.
    let conflicts: [[LinkedVersion]]
}

/// Moving a sidebar folder and everything in it to the Trash, waiting for confirmation.
struct FolderTrash: Identifiable {
    let path: String
    let svgCount: Int
    var id: String { path }
}
