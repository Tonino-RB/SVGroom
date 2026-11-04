import AppKit
import SVGroomCore
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
    @State private var imagePage: CGRect?
    @State private var imageMM: CGSize?
    @State private var loading = false
    @AppStorage("showOutsidePage") private var showOutside = false

    private struct Key: Equatable {
        let path: String
        let modified: Date
        let overrides: [Int: Bool]
        let missing: Bool
        let area: MMRect?
    }

    /// Page and drawing together (page mm), when the drawing goes past the page and that is shown.
    private var outsideArea: MMRect? {
        guard showOutside, let a = item.analysis, let w = a.widthMM, let h = a.heightMM else { return nil }
        let totals = a.totals { library.isLayerVisible($0, in: a) }
        guard a.exceedsPage(totals), let b = totals.bounds else { return nil }
        let margin = 2.0 // Bounds follow the stroke centre lines.
        return MMRect(minX: 0, minY: 0, maxX: w, maxY: h)
            .union(MMRect(minX: b.minX - margin, minY: b.minY - margin, maxX: b.maxX + margin, maxY: b.maxY + margin))
    }

    var body: some View {
        @Bindable var library = library
        ZStack {
            PaperView(image: imagePath == item.path ? image : nil, zoom: $library.loupeZoom,
                      actualSize: $library.loupeActualSize, imageMM: imageMM, page: imagePage,
                      dragURLs: { library.dragURLs(from: item) })
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
        .overlay(alignment: .bottom) { LoupeControls(item: item, showOutside: $showOutside) }
        .task(id: Key(path: item.path, modified: item.modified, overrides: overrides, missing: item.missing, area: outsideArea)) {
            guard !item.missing else { image = nil; imagePath = nil; return }
            loading = true
            let path = item.path
            let area = outsideArea
            let loaded = await LoupeRenderer.load(item.url, overrides: overrides, area: area)
            guard !Task.isCancelled else { return }
            image = loaded
            imagePath = path
            // Where the page sits in the enlarged image, in unit coordinates.
            imagePage = area.map {
                CGRect(x: -$0.minX / $0.width, y: -$0.minY / $0.height,
                       width: (item.analysis?.widthMM ?? 0) / $0.width, height: (item.analysis?.heightMM ?? 0) / $0.height)
            }
            imageMM = area.map { CGSize(width: $0.width, height: $0.height) }
                ?? item.analysis.flatMap { a in a.widthMM.flatMap { w in a.heightMM.map { CGSize(width: w, height: $0) } } }
            loading = false
        }
    }
}

/// Previous / next, file name and zoom, floating at the bottom of the loupe.
struct LoupeControls: View {
    @Environment(Library.self) private var library
    let item: SVGItem
    /// Shows the button for drawing outside the page when set.
    var showOutside: Binding<Bool>?
    @State private var calibrationScreen: NSScreen?

    var body: some View {
        HStack(spacing: 10) {
            Button { library.moveFocus(by: -1) } label: { Image(systemName: "chevron.left") }
                .help("Previous (←)")
            Text(item.name).lineLimit(1).truncationMode(.middle).frame(maxWidth: 280)
            Button { library.moveFocus(by: 1) } label: { Image(systemName: "chevron.right") }
                .help("Next (→)")
            Divider().frame(height: 14)
            Button { zoom(max(1, library.loupeZoom / 1.5)) } label: { Image(systemName: "minus.magnifyingglass") }
            Text(library.loupeActualSize ? "1:1" : "\(Int((library.loupeZoom * 100).rounded())) %").monospacedDigit().frame(width: 52)
            Button { zoom(min(40, library.loupeZoom * 1.5)) } label: { Image(systemName: "plus.magnifyingglass") }
            Button("Fit") { zoom(1) }.help("Fit (Z toggles zoom)")
            Button("1:1") { library.loupeActualSize = true }
                .foregroundStyle(library.loupeActualSize ? Color.accentColor : .primary)
                .disabled(item.analysis?.widthMM == nil)
                .help("Real Size — the sheet as large on screen as on paper")
            Button { calibrationScreen = NSApp.keyWindow?.screen ?? NSScreen.main } label: { Image(systemName: "ruler") }
                .help("Calibrate Real Size…")
            if let showOutside {
                Divider().frame(height: 14)
                Button { showOutside.wrappedValue.toggle() } label: { Image(systemName: "rectangle.dashed") }
                    .foregroundStyle(showOutside.wrappedValue ? Color(nsColor: PaperDocumentView.outsideColor) : .primary)
                    .help(showOutside.wrappedValue ? "Hide Drawing Outside the Page" : "Show Drawing Outside the Page")
            }
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .padding(12)
        .sheet(isPresented: Binding(get: { calibrationScreen != nil }, set: { if !$0 { calibrationScreen = nil } })) {
            if let calibrationScreen { CalibrationView(screen: calibrationScreen) }
        }
    }

    private func zoom(_ z: CGFloat) {
        library.loupeActualSize = false
        library.loupeZoom = z
    }
}

/// Magnifiable scroll view showing the SVG on a white sheet. The image keeps its vector
/// representation, so it is redrawn sharply at every zoom level.
struct PaperView: NSViewRepresentable {
    let image: NSImage?
    @Binding var zoom: CGFloat
    @Binding var actualSize: Bool
    /// Real size of the image in mm when there is no sheet, for the real-size zoom.
    var imageMM: CGSize?
    /// Sheet size in mm, and the size in mm that fills the view, so two sheets side by side
    /// are drawn at the same scale. Nil fits the image.
    var sheetMM: CGSize?
    var fitMM: CGSize?
    /// Where the page sits in an image that reaches past it (unit coordinates, y down).
    var page: CGRect?
    /// A click on the sheet that did not become a drag.
    var onClick: (() -> Void)?
    /// Files dragged out when the sheet is dragged; nil leaves dragging off.
    var dragURLs: (() -> [URL])?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> FittingScrollView {
        let scroll = FittingScrollView()
        scroll.allowsMagnification = true
        scroll.minMagnification = 1
        scroll.maxMagnification = 40
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.documentView = PaperDocumentView()
        let coordinator = context.coordinator
        scroll.onActualSize = { z in
            // Not during the SwiftUI update that may have triggered it.
            DispatchQueue.main.async { if abs(coordinator.parent.zoom - z) > 0.0001 { coordinator.parent.zoom = z } }
        }
        scroll.onLeaveActualSize = { coordinator.parent.actualSize = false }
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.didMagnify(_:)),
                                               name: NSScrollView.didEndLiveMagnifyNotification, object: scroll)
        return scroll
    }

    func updateNSView(_ scroll: FittingScrollView, context: Context) {
        context.coordinator.parent = self
        if let doc = scroll.documentView as? PaperDocumentView {
            doc.onClick = onClick
            doc.dragURLs = dragURLs
        }
        if let doc = scroll.documentView as? PaperDocumentView,
           doc.image !== image || doc.sheetMM != sheetMM || doc.fitMM != fitMM || doc.page != page || doc.imageMM != imageMM {
            doc.image = image
            doc.sheetMM = sheetMM
            doc.fitMM = fitMM
            doc.page = page
            doc.imageMM = imageMM
            doc.needsDisplay = true
        }
        scroll.actualSize = actualSize
        if actualSize {
            scroll.applyActualSize()
        } else if abs(scroll.magnification - zoom) > 0.001 {
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
final class FittingScrollView: NSScrollView {
    /// Holds the magnification at real size on the current screen, through resizing,
    /// moving to another display and calibrating.
    var actualSize = false
    /// The magnification real size took.
    var onActualSize: ((CGFloat) -> Void)?
    /// Pinching left real size.
    var onLeaveActualSize: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        contentView = CenteringClipView()
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged),
                                               name: ScreenCalibration.didChange, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func tile() {
        super.tile()
        let size = contentView.frame.size
        if let doc = documentView, doc.frame.size != size { doc.setFrameSize(size) }
        applyActualSize()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeScreenNotification, object: nil)
        if let window {
            NotificationCenter.default.addObserver(self, selector: #selector(screenChanged),
                                                   name: NSWindow.didChangeScreenNotification, object: window)
        }
        applyActualSize()
    }

    @objc private func screenChanged() { applyActualSize() }

    func applyActualSize() {
        guard actualSize else { minMagnification = 1; return }
        guard let doc = documentView as? PaperDocumentView, let fit = doc.pointsPerMM, let screen = window?.screen else { return }
        let target = ScreenCalibration.pointsPerMM(screen) / fit
        // A small sheet on a large screen is smaller at real size than fitted.
        minMagnification = min(1, target)
        if abs(magnification - target) > 0.0001 {
            let visible = contentView.documentVisibleRect
            setMagnification(target, centeredAt: NSPoint(x: visible.midX, y: visible.midY))
        }
        onActualSize?(target)
    }

    override func magnify(with event: NSEvent) {
        leaveActualSize()
        super.magnify(with: event)
    }

    override func smartMagnify(with event: NSEvent) {
        leaveActualSize()
        super.smartMagnify(with: event)
    }

    private func leaveActualSize() {
        guard actualSize else { return }
        actualSize = false
        onLeaveActualSize?()
    }
}

/// Keeps the document centred when it is smaller than the view (zoomed out below fit).
private final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var r = super.constrainBoundsRect(proposedBounds)
        guard let doc = documentView else { return r }
        if r.width > doc.frame.width { r.origin.x = (doc.frame.width - r.width) / 2 }
        if r.height > doc.frame.height { r.origin.y = (doc.frame.height - r.height) / 2 }
        return r
    }
}

final class PaperDocumentView: NSView, NSDraggingSource {
    /// Drawing outside the page, chosen to stand out from the grey background and the white sheet.
    static let outsideColor = NSColor(srgbRed: 1, green: 0, blue: 0.85, alpha: 1)

    var image: NSImage?
    var sheetMM: CGSize?
    var fitMM: CGSize?
    var page: CGRect?
    var imageMM: CGSize?
    var onClick: (() -> Void)?
    var dragURLs: (() -> [URL])?
    private var down: NSEvent?

    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) { down = event }

    override func mouseDragged(with event: NSEvent) {
        guard let down, FileDrag.isDrag(from: down, to: event), let dragURLs else { return }
        self.down = nil
        FileDrag.begin(dragURLs(), image: nil, event: down, from: self)
    }

    override func mouseUp(with event: NSEvent) {
        if down != nil { onClick?() }
        down = nil
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }

    /// Size of the drawn image at 100 %, nil when there is nothing to draw.
    private var imageSize: CGSize? {
        guard let image, image.size.width > 0, image.size.height > 0 else { return nil }
        let sheetSize = sheetMM ?? image.size, fitSize = fitMM ?? sheetSize
        guard fitSize.width > 0, fitSize.height > 0 else { return nil }
        let area = bounds.insetBy(dx: 28, dy: 28)
        let s = min(area.width / fitSize.width, area.height / fitSize.height)
        return CGSize(width: sheetSize.width * s, height: sheetSize.height * s)
    }

    /// Points per mm at 100 %, nil when the real size is unknown.
    var pointsPerMM: CGFloat? {
        guard let size = imageSize, let mm = sheetMM ?? imageMM, mm.width > 0 else { return nil }
        return size.width / mm.width
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let image, let size = imageSize else { return }
        let w = size.width, h = size.height
        let full = NSRect(x: bounds.midX - w / 2, y: bounds.midY - h / 2, width: w, height: h)
        let p = page ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        let sheet = NSRect(x: full.minX + p.minX * w, y: full.minY + p.minY * h, width: p.width * w, height: p.height * h)

        // Everything in one flat colour first; the sheet then covers what is on the page.
        if page != nil, let cg = NSGraphicsContext.current?.cgContext {
            cg.beginTransparencyLayer(in: full, auxiliaryInfo: nil)
            image.draw(in: full, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            Self.outsideColor.setFill()
            full.fill(using: .sourceAtop)
            cg.endTransparencyLayer()
        }

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowBlurRadius = 6
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.set()
        NSColor.white.setFill()
        sheet.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        sheet.clip()
        image.draw(in: full, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
    }
}
