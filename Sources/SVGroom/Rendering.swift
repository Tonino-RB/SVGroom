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
    /// With `area` (page millimetres), the image covers that area instead of the page.
    static func load(_ url: URL, overrides: [Int: Bool], area: MMRect? = nil) async -> NSImage? {
        let data = await Task.detached(priority: .userInitiated) { () -> Data? in
            guard var d = try? Data(contentsOf: url) else { return nil }
            // CoreSVG ignores display:none, so hidden layers are stripped first.
            if LayerEditor.needsEditing(d, overrides: overrides) { d = LayerEditor.render(d, overrides: overrides) ?? d }
            guard let area else { return d }
            return LayerEditor.expandPage(d, to: area) ?? d
        }.value
        return data.flatMap(NSImage.init(data:))
    }

    /// The file as it would be plotted with the simulation settings (the file is not modified).
    static func simulate(_ url: URL, overrides: [Int: Bool], layout: SimulationLayout,
                         settings: SimulationSettings) async -> NSImage? {
        let data = await Task.detached(priority: .userInitiated) { () -> Data? in
            guard let d = try? Data(contentsOf: url),
                  let simulated = Simulator.render(d, layout: layout, settings: settings) else { return nil }
            guard LayerEditor.needsEditing(simulated, overrides: overrides) else { return simulated }
            return LayerEditor.render(simulated, overrides: overrides) ?? simulated
        }.value
        return data.flatMap(NSImage.init(data:))
    }
}
