import Foundation

/// File names for copying files from many folders into one.
public enum CopyNames {
    /// Each name is prefixed with its folder ("coral_a.svg"), and with more parent folders when that is not
    /// enough to tell it apart from the others ("f1_coral_a.svg"). Names still the same, or already in
    /// `taken`, are numbered like the Finder does ("coral_a 2.svg"). Compared ignoring case, like APFS.
    public static func names(for paths: [String], taken: Set<String> = []) -> [String] {
        let parts = paths.map { $0.split(separator: "/").map(String.init) }
        var depth = Array(repeating: 1, count: paths.count)
        func name(_ i: Int) -> String { parts[i].suffix(depth[i] + 1).joined(separator: "_") }

        var grew = true
        while grew {
            grew = false
            for group in Dictionary(grouping: paths.indices, by: { name($0).lowercased() }).values where group.count > 1 {
                for i in group where depth[i] + 1 < parts[i].count {
                    depth[i] += 1
                    grew = true
                }
            }
        }

        var used = Set(taken.map { $0.lowercased() })
        return paths.indices.map { i in
            let base = name(i) as NSString
            var candidate = base as String
            var n = 2
            while used.contains(candidate.lowercased()) {
                candidate = base.deletingPathExtension + " \(n)" + (base.pathExtension.isEmpty ? "" : "." + base.pathExtension)
                n += 1
            }
            used.insert(candidate.lowercased())
            return candidate
        }
    }
}
