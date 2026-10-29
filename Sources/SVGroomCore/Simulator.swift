import Foundation

/// Sheet size in mm.
public struct SheetSize: Codable, Sendable, Equatable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

/// What-if settings for the simulation preview. The file itself is never modified.
public struct SimulationSettings: Codable, Sendable, Equatable {
    /// Key of `penColors` for the content drawn outside any layer.
    public static let unlayered = -1

    /// Sheet to plot on; nil keeps the file's page.
    public var canvas: SheetSize?
    /// Longest side of the drawing in mm; nil keeps the file's scale.
    public var longestSideMM: Double?
    public var penWidthMM = 0.4
    /// Ink colour ("#rrggbb") per top-level layer index, in document order.
    public var penColors: [Int: String] = [:]

    public init() {}
}

/// Where the drawing lands on the simulated sheet.
public struct SimulationLayout: Sendable, Equatable {
    public var canvas: SheetSize
    /// Page mm → sheet mm: `sheet = page × scale + offset`.
    public var scale: Double
    public var offsetX: Double
    public var offsetY: Double
    /// Drawing bounds on the sheet, in mm.
    public var drawing: MMRect?

    /// True when the drawing stays on the sheet (0.5 mm tolerance).
    public var fits: Bool {
        guard let b = drawing else { return true }
        return b.minX >= -0.5 && b.minY >= -0.5 && b.maxX <= canvas.width + 0.5 && b.maxY <= canvas.height + 0.5
    }
}

/// Builds a preview of a file as it would be plotted with other settings:
/// another sheet, another size, other pens (width and colour). Every shape is drawn as
/// a stroke with no fill, like a plotter draws it.
public enum Simulator {
    /// The drawing is centred on the sheet as soon as the sheet or the size is changed.
    public static func layout(_ analysis: SVGAnalysis, _ settings: SimulationSettings,
                              visible: (Int) -> Bool) -> SimulationLayout? {
        guard let pw = analysis.widthMM, let ph = analysis.heightMM else { return nil }
        let canvas = settings.canvas ?? SheetSize(width: pw, height: ph)
        let bounds = analysis.totals(visible: visible).bounds
        let b = bounds ?? MMRect(minX: 0, minY: 0, maxX: pw, maxY: ph)
        let longest = max(b.width, b.height)

        var scale = 1.0
        if let l = settings.longestSideMM, l > 0, longest > 0 { scale = l / longest }
        var ox = 0.0, oy = 0.0
        if settings.canvas != nil || settings.longestSideMM != nil {
            ox = canvas.width / 2 - scale * (b.minX + b.maxX) / 2
            oy = canvas.height / 2 - scale * (b.minY + b.maxY) / 2
        }
        let drawing = bounds.map {
            MMRect(minX: $0.minX * scale + ox, minY: $0.minY * scale + oy,
                   maxX: $0.maxX * scale + ox, maxY: $0.maxY * scale + oy)
        }
        return SimulationLayout(canvas: canvas, scale: scale, offsetX: ox, offsetY: oy, drawing: drawing)
    }

    /// Rewrites the SVG for the native renderer: page set to the sheet, content moved and scaled,
    /// strokes set to the pen width (in mm on the sheet) and pen colours.
    public static func render(_ data: Data, layout: SimulationLayout, settings: SimulationSettings) -> Data? {
        guard let doc = try? XMLDocument(data: data, options: [.nodePreserveAll]), let root = doc.rootElement() else { return nil }

        let rootAttributes = Dictionary((root.attributes ?? []).compactMap { a in a.name.map { ($0, a.stringValue ?? "") } },
                                        uniquingKeysWith: { first, _ in first })
        let m = Affine.translate(layout.offsetX, layout.offsetY)
            .concatenating(.scale(layout.scale, layout.scale))
            .concatenating(SVGUnits.rootTransform(rootAttributes).transform)

        // Drawn content goes into one group carrying the new placement; definitions stay at the root.
        let content = XMLElement(name: "g")
        content.setAttributesWith(["transform": "matrix(\(m.a) \(m.b) \(m.c) \(m.d) \(m.e) \(m.f))"])
        for child in root.children ?? [] {
            guard let el = child as? XMLElement, !keptAtRoot.contains(el.localName ?? "") else { continue }
            el.detach()
            content.addChild(el)
        }
        root.addChild(content)

        let w = layout.canvas.width, h = layout.canvas.height
        root.removeAttribute(forName: "preserveAspectRatio")
        root.removeAttribute(forName: "x")
        root.removeAttribute(forName: "y")
        set(root, "width", "\(w)mm")
        set(root, "height", "\(h)mm")
        set(root, "viewBox", "0 0 \(w) \(h)")

        var layerIndex = 0
        func paint(_ el: XMLElement, ctm: Affine, pen: String?, insideLayer: Bool, stroke: String?) {
            for child in el.children ?? [] {
                guard let c = child as? XMLElement, let name = c.localName, !skipped.contains(name) else { continue }
                let style = c.attribute(forName: "style")?.stringValue
                let isLayer = !insideLayer && name == "g"
                    && c.attributes?.first(where: { $0.name?.hasSuffix("groupmode") == true })?.stringValue == "layer"
                let hidden = c.attribute(forName: "display")?.stringValue == "none"
                    || style.flatMap { SVGUnits.styleValue($0, "display") } == "none"
                if hidden && !isLayer { continue } // Same layer numbering as the analyzer.

                var t = ctm
                if let tr = c.attribute(forName: "transform")?.stringValue { t = t.concatenating(TransformParser.parse(tr)) }
                var pen = pen
                if isLayer {
                    pen = settings.penColors[layerIndex]
                    layerIndex += 1
                }
                let ownStroke = c.attribute(forName: "stroke")?.stringValue ?? style.flatMap { SVGUnits.styleValue($0, "stroke") }
                let stroke = ownStroke ?? stroke

                if shapes.contains(name) {
                    let k = abs(t.a * t.d - t.b * t.c).squareRoot()
                    var props = [
                        ("stroke-width", "\(k > 0 ? settings.penWidthMM / k : settings.penWidthMM)"),
                        ("fill", "none"), ("stroke-linecap", "round"), ("stroke-linejoin", "round"),
                    ]
                    if let color = pen ?? (stroke == nil || stroke == "none" ? "#000000" : nil) {
                        props.append(("stroke", color))
                    }
                    setStyle(c, props)
                } else {
                    paint(c, ctm: t, pen: pen, insideLayer: insideLayer || isLayer, stroke: stroke)
                }
            }
        }
        paint(content, ctm: m, pen: settings.penColors[SimulationSettings.unlayered], insideLayer: false, stroke: nil)
        return doc.xmlData(options: [.nodePreserveAll])
    }

    private static let keptAtRoot: Set<String> = ["defs", "style", "metadata", "namedview", "title", "desc", "script"]
    private static let skipped: Set<String> = [
        "defs", "clipPath", "mask", "symbol", "marker", "pattern", "metadata", "title", "desc",
        "style", "script", "namedview", "linearGradient", "radialGradient", "filter", "foreignObject",
    ]
    private static let shapes: Set<String> = ["path", "line", "polyline", "polygon", "rect", "circle", "ellipse"]

    private static func set(_ el: XMLElement, _ name: String, _ value: String) {
        el.removeAttribute(forName: name)
        el.addAttribute(XMLNode.attribute(withName: name, stringValue: value) as! XMLNode)
    }

    /// Inline style wins over attributes and stylesheets, so the new values go there.
    private static func setStyle(_ el: XMLElement, _ props: [(String, String)]) {
        let names = Set(props.map(\.0))
        let kept = (el.attribute(forName: "style")?.stringValue ?? "").split(separator: ";").filter { decl in
            let key = decl.split(separator: ":").first?.trimmingCharacters(in: .whitespaces) ?? ""
            return !key.isEmpty && !names.contains(key)
        }
        let style = (kept.map(String.init) + props.map { "\($0.0):\($0.1)" }).joined(separator: ";")
        set(el, "style", style)
    }
}
