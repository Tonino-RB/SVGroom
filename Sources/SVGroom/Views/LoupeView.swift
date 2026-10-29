import AppKit
import SwiftUI

struct LoupeView: View {
    @Environment(Library.self) private var library

    var body: some View {
        if let item = library.focused {
            LoupeContent(item: item, overrides: library.layerOverrides)
        } else {
            ContentUnavailableView("No SVG Selected", systemImage: "square.dashed")
        }
    }
}

private struct LoupeContent: View {
    @Environment(Library.self) private var library
    let item: SVGItem
    let overrides: [Int: Bool]
    @State private var image: NSImage?
    @State private var imagePath: String?
    @State private var loading = false

    private struct Key: Equatable {
        let path: String
        let modified: Date
        let overrides: [Int: Bool]
        let missing: Bool
    }

    var body: some View {
        @Bindable var library = library
        ZStack {
            PaperView(image: imagePath == item.path ? image : nil, zoom: $library.loupeZoom)
            if item.missing {
                VStack(spacing: 10) {
                    Image(systemName: "questionmark.square.dashed").font(.system(size: 48)).foregroundStyle(.secondary)
                    Text("File not found").font(.title3)
                    Text(item.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Button("Locate…") { library.locatePanel(item) }
                }
            } else if loading && imagePath != item.path {
                ProgressView()
            } else if !loading && image == nil {
                Text("This SVG could not be rendered.").foregroundStyle(.secondary)
            }
        }
        .overlay(alignment: .bottom) { LoupeControls(item: item) }
        .task(id: Key(path: item.path, modified: item.modified, overrides: overrides, missing: item.missing)) {
            guard !item.missing else { image = nil; imagePath = nil; return }
            loading = true
            let path = item.path
            let loaded = await LoupeRenderer.load(item.url, overrides: overrides)
            guard !Task.isCancelled else { return }
            image = loaded
            imagePath = path
            loading = false
        }
    }
}

/// Previous / next, file name and zoom, floating at the bottom of the loupe.
struct LoupeControls: View {
    @Environment(Library.self) private var library
    let item: SVGItem

    var body: some View {
        HStack(spacing: 10) {
            Button { library.moveFocus(by: -1) } label: { Image(systemName: "chevron.left") }
                .help("Previous (←)")
            Text(item.name).lineLimit(1).truncationMode(.middle).frame(maxWidth: 280)
            Button { library.moveFocus(by: 1) } label: { Image(systemName: "chevron.right") }
                .help("Next (→)")
            Divider().frame(height: 14)
            Button { library.loupeZoom = max(1, library.loupeZoom / 1.5) } label: { Image(systemName: "minus.magnifyingglass") }
            Text("\(Int((library.loupeZoom * 100).rounded())) %").monospacedDigit().frame(width: 52)
            Button { library.loupeZoom = min(40, library.loupeZoom * 1.5) } label: { Image(systemName: "plus.magnifyingglass") }
            Button("Fit") { library.loupeZoom = 1 }.help("Fit (Z toggles zoom)")
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .padding(12)
    }
}

/// Magnifiable scroll view showing the SVG on a white sheet. The image keeps its vector
/// representation, so it is redrawn sharply at every zoom level.
struct PaperView: NSViewRepresentable {
    let image: NSImage?
    @Binding var zoom: CGFloat
    /// Sheet size in mm, and the size in mm that fills the view, so two sheets side by side
    /// are drawn at the same scale. Nil fits the image.
    var sheetMM: CGSize?
    var fitMM: CGSize?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = FittingScrollView()
        scroll.allowsMagnification = true
        scroll.minMagnification = 1
        scroll.maxMagnification = 40
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.documentView = PaperDocumentView()
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.didMagnify(_:)),
                                               name: NSScrollView.didEndLiveMagnifyNotification, object: scroll)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        if let doc = scroll.documentView as? PaperDocumentView,
           doc.image !== image || doc.sheetMM != sheetMM || doc.fitMM != fitMM {
            doc.image = image
            doc.sheetMM = sheetMM
            doc.fitMM = fitMM
            doc.needsDisplay = true
        }
        if abs(scroll.magnification - zoom) > 0.001 {
            let visible = scroll.contentView.documentVisibleRect
            scroll.setMagnification(zoom, centeredAt: NSPoint(x: visible.midX, y: visible.midY))
        }
    }

    final class Coordinator: NSObject {
        var parent: PaperView
        init(_ parent: PaperView) { self.parent = parent }

        @objc func didMagnify(_ note: Notification) {
            guard let scroll = note.object as? NSScrollView else { return }
            parent.zoom = scroll.magnification
        }
    }
}

/// Keeps the document exactly as large as the visible area at 100 %, so "fit" is the unzoomed state.
private final class FittingScrollView: NSScrollView {
    override func tile() {
        super.tile()
        let size = contentView.frame.size
        if let doc = documentView, doc.frame.size != size { doc.setFrameSize(size) }
    }
}

private final class PaperDocumentView: NSView {
    var image: NSImage?
    var sheetMM: CGSize?
    var fitMM: CGSize?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let image, image.size.width > 0, image.size.height > 0 else { return }
        let sheetSize = sheetMM ?? image.size, fitSize = fitMM ?? sheetSize
        guard fitSize.width > 0, fitSize.height > 0 else { return }
        let area = bounds.insetBy(dx: 28, dy: 28)
        let s = min(area.width / fitSize.width, area.height / fitSize.height)
        let w = sheetSize.width * s, h = sheetSize.height * s
        let sheet = NSRect(x: bounds.midX - w / 2, y: bounds.midY - h / 2, width: w, height: h)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowBlurRadius = 6
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.set()
        NSColor.white.setFill()
        sheet.fill()
        NSGraphicsContext.restoreGraphicsState()

        image.draw(in: sheet, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}
