import Foundation

/// Groups of folders whose files mirror each other by relative path (e.g. one export at several settings).
/// A folder belongs to at most one group.
public enum FolderLinks {
    /// The files at the same place as `path` in the folders linked to the ones containing it.
    public static func counterparts(of path: String, in groups: [[String]]) -> [String] {
        var result: [String] = []
        for group in groups {
            for folder in group where path.hasPrefix(folder + "/") {
                let relative = path.dropFirst(folder.count)
                result += group.filter { $0 != folder }.map { $0 + relative }
            }
        }
        return result
    }

    /// The indices of `paths` that are not a version of an earlier one (same relative path in the same link group).
    public static func firstVersions(_ paths: [String], in groups: [[String]]) -> [Int] {
        var seen = Set<String>()
        return paths.indices.filter { i in
            let path = paths[i]
            for (g, group) in groups.enumerated() {
                if let folder = group.first(where: { path.hasPrefix($0 + "/") }) {
                    return seen.insert("\(g)\u{0}\(path.dropFirst(folder.count))").inserted
                }
            }
            return true
        }
    }

    /// Links `folder` with `others`, merging the groups they already belong to.
    /// The folder itself and folders nested in or around it are ignored.
    public static func link(_ folder: String, with others: [String], in groups: [[String]]) -> [[String]] {
        let others = others.filter { $0 != folder && !$0.hasPrefix(folder + "/") && !folder.hasPrefix($0 + "/") }
        guard !others.isEmpty else { return groups }
        var merged = Set([folder] + others)
        var rest: [[String]] = []
        for g in groups {
            if g.contains(where: merged.contains) { merged.formUnion(g) } else { rest.append(g) }
        }
        return rest + [merged.sorted()]
    }

    /// Syncing the tags of a link group's files (`tags`: path → tag, nil when untagged).
    /// Files at the same relative path whose tagged versions agree: the untagged ones get that tag.
    /// Tagged versions that differ: a conflict, left for review.
    public static func syncTags<Tag: Equatable>(in group: [String], tags: [String: Tag?]) -> TagSync<Tag> {
        var versions: [Substring: [String]] = [:]
        for folder in group {
            for path in tags.keys where path.hasPrefix(folder + "/") {
                versions[path.dropFirst(folder.count), default: []].append(path)
            }
        }
        var result = TagSync<Tag>()
        for relative in versions.keys.sorted() {
            let paths = versions[relative]!
            var distinct: [Tag] = []
            for p in paths { if let t = tags[p] ?? nil, !distinct.contains(t) { distinct.append(t) } }
            if distinct.count > 1 {
                result.conflicts.append(paths)
            } else if let t = distinct.first {
                for p in paths where tags[p]! == nil { result.copies[p] = t }
            }
        }
        return result
    }

    public static func unlink(_ folder: String, in groups: [[String]]) -> [[String]] {
        groups.map { $0.filter { $0 != folder } }.filter { $0.count > 1 }
    }
}

public struct TagSync<Tag: Equatable> {
    /// Untagged files and the tag they get.
    public var copies: [String: Tag] = [:]
    /// The versions of each file whose tags differ, in folder order.
    public var conflicts: [[String]] = []
}
