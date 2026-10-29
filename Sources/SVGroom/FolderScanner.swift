import Foundation

struct ScannedFile: Sendable {
    let path: String
    let size: Int64
    let modified: Date
    let dataless: Bool
}

struct ScanResult: Sendable {
    let root: String
    let exists: Bool
    let files: [ScannedFile]
}

/// Lists SVG files recursively. Only reads metadata, so cloud placeholders are not downloaded.
enum FolderScanner {
    static func scan(_ root: String) -> ScanResult {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root, isDirectory: &isDir), isDir.boolValue else {
            return ScanResult(root: root, exists: false, files: [])
        }
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: root), includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
        var files: [ScannedFile] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension.lowercased() == "svg",
                  let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            files.append(ScannedFile(path: url.standardizedFileURL.path, size: Int64(v.fileSize ?? 0),
                                     modified: v.contentModificationDate ?? .distantPast,
                                     dataless: isDataless(url.path)))
        }
        return ScanResult(root: root, exists: true, files: files)
    }

    static func isDataless(_ path: String) -> Bool {
        var st = stat()
        guard lstat(path, &st) == 0 else { return false }
        return st.st_flags & 0x4000_0000 != 0 // SF_DATALESS
    }
}
