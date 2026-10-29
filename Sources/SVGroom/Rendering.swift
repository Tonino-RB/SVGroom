import AppKit
import QuickLookThumbnailing
import SVGroomCore

/// Grid thumbnails come from Quick Look (WebKit rendering, out of process, cached by the system).
@MainActor
final class Thumbnailer {
    static let shared = Thumbnailer()
    private let cache = NSCache<NSString, NSImage>()

    private init() { cache.countLimit = 3000 }

    static func pixelSize(for points: Double) -> Int {
        let wanted = Int(points * 2)
        return [256, 512, 1024].first { $0 >= wanted } ?? 1024
    }

    func image(for url: URL, modified: Date, pixels: Int) async -> NSImage? {
        let key = "\(url.path)|\(modified.timeIntervalSinceReferenceDate)|\(pixels)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: pixels, height: pixels),
                                                   scale: 1, representationTypes: .thumbnail)
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return nil }
        let image = rep.nsImage
        cache.setObject(image, forKey: key)
        return image
    }
}

/// Full-size preview through CoreSVG (vector, stays sharp when zooming).
enum LoupeRenderer {
    static func load(_ url: URL, overrides: [Int: Bool]) async -> NSImage? {
        let data = await Task.detached(priority: .userInitiated) { () -> Data? in
            guard let d = try? Data(contentsOf: url) else { return nil }
            // CoreSVG ignores display:none, so hidden layers are stripped first.
            guard LayerEditor.needsEditing(d, overrides: overrides) else { return d }
            return LayerEditor.render(d, overrides: overrides) ?? d
        }.value
        return data.flatMap(NSImage.init(data:))
    }
}
