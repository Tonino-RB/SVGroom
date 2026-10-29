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

    public static func unlink(_ folder: String, in groups: [[String]]) -> [[String]] {
        groups.map { $0.filter { $0 != folder } }.filter { $0.count > 1 }
    }
}
