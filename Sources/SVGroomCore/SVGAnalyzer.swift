import Foundation
import CryptoKit

/// Streams an SVG once (SAX) and measures what a pen plotter would draw:
/// page size, Inkscape layers, pen-down / pen-up distances and pen lifts.
public enum SVGAnalyzer {
    /// Bump when the analysis changes, so cached results in catalogs are recomputed.
    public static let version = 1

    public static func analyze(data: Data) -> SVGAnalysis? {
        let handler = SAXHandler()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        parser.delegate = handler
        _ = parser.parse() // A truncated file still yields what was read before the error.
        guard handler.sawRoot else { return nil }
        return handler.result()
    }

    /// Reads the file once; returns the analysis and the SHA-256 of its content.
    public static func analyze(url: URL) throws -> (analysis: SVGAnalysis?, hash: String) {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return (analyze(data: data), contentHash(data))
    }

    public static func contentHash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Accumulates one plotting job (a layer, or the unlayered content). Points are in mm.
final class StrokeAccumulator {
    var stats: LayerStats
    private var pen = Point(x: 0, y: 0)
    private var pending: Point?

    init(name: String, hidden: Bool = false) { stats = LayerStats(name: name, hiddenInFile: hidden) }

    func move(_ p: Point) { pending = p }

    func line(_ p: Point) {
        if let start = pending {
            stats.travelMM += pen.distance(to: start)
            stats.strokes += 1
            pen = start
            include(start)
            pending = nil
        }
        stats.drawMM += pen.distance(to: p)
        pen = p
        include(p)
    }

    func finish() -> LayerStats {
        if stats.strokes > 0 { stats.travelMM += pen.distance(to: Point(x: 0, y: 0)) }
        return stats
    }

    private func include(_ p: Point) {
        if var b = stats.bounds {
            b.minX = min(b.minX, p.x); b.minY = min(b.minY, p.y)
            b.maxX = max(b.maxX, p.x); b.maxY = max(b.maxY, p.y)
            stats.bounds = b
        } else {
            stats.bounds = MMRect(minX: p.x, minY: p.y, maxX: p.x, maxY: p.y)
        }
    }
}

private final class SAXHandler: NSObject, XMLParserDelegate {
    private static let skippedElements: Set<String> = [
        "defs", "clipPath", "mask", "symbol", "marker", "pattern", "metadata", "title", "desc",
        "style", "script", "namedview", "linearGradient", "radialGradient", "filter", "foreignObject",
    ]

    private(set) var sawRoot = false
    private var widthMM: Double?
    private var heightMM: Double?
    private var depth = 0
    private var skipDepth = 0
    private var ctm: [Affine] = []
    private var strokeColor: [String?] = []
    private var layers: [StrokeAccumulator] = []
    private let unlayered = StrokeAccumulator(name: "")
    private var layerIndex: Int?
    private var layerDepth = 0
    private var textCount = 0, imageCount = 0, useCount = 0

    private var acc: StrokeAccumulator { layerIndex.map { layers[$0] } ?? unlayered }

    func result() -> SVGAnalysis {
        SVGAnalysis(version: SVGAnalyzer.version, widthMM: widthMM, heightMM: heightMM,
                    layers: layers.map { $0.finish() }, unlayered: unlayered.finish(),
                    textCount: textCount, imageCount: imageCount, useCount: useCount)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes a: [String: String] = [:]) {
        depth += 1
        if skipDepth > 0 { skipDepth += 1; return }
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName

        if Self.skippedElements.contains(name) { skipDepth = 1; return }
        switch name {
        case "text": textCount += 1; skipDepth = 1; return
        case "image": imageCount += 1; skipDepth = 1; return
        case "use": useCount += 1; skipDepth = 1; return
        default: break
        }

        let style = a["style"]
        let hidden = a["display"] == "none" || style.map { Self.styleValue($0, "display") == "none" } == true
        let isLayer = name == "g" && layerIndex == nil
            && a.first(where: { $0.key.hasSuffix("groupmode") })?.value == "layer"
        if hidden && !isLayer { skipDepth = 1; return }

        var m = ctm.last ?? .identity
        if name == "svg" {
            if !sawRoot {
                sawRoot = true
                m = rootTransform(a)
            } else {
                m = m.concatenating(.translate(SVGUnits.user(a["x"]), SVGUnits.user(a["y"])))
            }
        }
        if let t = a["transform"] { m = m.concatenating(TransformParser.parse(t)) }
        ctm.append(m)

        let ownStroke = a["stroke"] ?? style.flatMap { Self.styleValue($0, "stroke") }
        let stroke = ownStroke ?? strokeColor.last ?? nil
        strokeColor.append(stroke)

        if isLayer {
            let label = a.first(where: { $0.key.hasSuffix(":label") })?.value ?? a["id"] ?? "Layer \(layers.count + 1)"
            layers.append(StrokeAccumulator(name: label, hidden: hidden))
            layerIndex = layers.count - 1
            layerDepth = depth
            return
        }

        guard Self.isShape(name) else { return }
        let target = acc
        target.stats.elements += 1
        if target.stats.color == nil, let s = stroke, s != "none" { target.stats.color = s }
        addShape(name, a, m, target)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        defer { depth -= 1 }
        if skipDepth > 0 { skipDepth -= 1; return }
        ctm.removeLast()
        strokeColor.removeLast()
        if layerIndex != nil && depth == layerDepth { layerIndex = nil }
    }

    // MARK: - Geometry

    private static func isShape(_ n: String) -> Bool {
        switch n {
        case "path", "line", "polyline", "polygon", "rect", "circle", "ellipse": return true
        default: return false
        }
    }

    private func rootTransform(_ a: [String: String]) -> Affine {
        let w = SVGUnits.mm(a["width"]), h = SVGUnits.mm(a["height"])
        let vb = a["viewBox"].map(NumberScanner.numbers(in:)) ?? []
        if vb.count == 4, vb[2] > 0, vb[3] > 0 {
            let pageW = w ?? vb[2] * SVGUnits.mmPerPx
            let pageH = h ?? vb[3] * SVGUnits.mmPerPx
            widthMM = pageW; heightMM = pageH
            let sx = pageW / vb[2], sy = pageH / vb[3]
            if a["preserveAspectRatio"]?.hasPrefix("none") == true {
                return Affine.scale(sx, sy).concatenating(.translate(-vb[0], -vb[1]))
            }
            // Default xMidYMid meet.
            let s = min(sx, sy)
            let tx = (pageW - vb[2] * s) / 2, ty = (pageH - vb[3] * s) / 2
            return Affine.translate(tx, ty).concatenating(.scale(s, s)).concatenating(.translate(-vb[0], -vb[1]))
        }
        widthMM = w; heightMM = h
        return .scale(SVGUnits.mmPerPx, SVGUnits.mmPerPx)
    }

    private func addShape(_ name: String, _ a: [String: String], _ m: Affine, _ acc: StrokeAccumulator) {
        func u(_ k: String) -> Double { SVGUnits.user(a[k]) }
        switch name {
        case "path":
            if let d = a["d"] { PathWalker.walk(d, m, acc) }
        case "line":
            acc.move(m.apply(u("x1"), u("y1")))
            acc.line(m.apply(u("x2"), u("y2")))
        case "polyline", "polygon":
            let v = NumberScanner.numbers(in: a["points"] ?? "")
            guard v.count >= 4 else { return }
            acc.move(m.apply(v[0], v[1]))
            var i = 2
            while i + 1 < v.count { acc.line(m.apply(v[i], v[i + 1])); i += 2 }
            if name == "polygon" { acc.line(m.apply(v[0], v[1])) }
        case "rect":
            let x = u("x"), y = u("y"), w = u("width"), h = u("height")
            guard w > 0, h > 0 else { return }
            acc.move(m.apply(x, y))
            acc.line(m.apply(x + w, y)); acc.line(m.apply(x + w, y + h))
            acc.line(m.apply(x, y + h)); acc.line(m.apply(x, y))
        case "circle":
            let r = u("r")
            ellipse(u("cx"), u("cy"), r, r, m, acc)
        case "ellipse":
            ellipse(u("cx"), u("cy"), u("rx"), u("ry"), m, acc)
        default:
            break
        }
    }

    private func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ m: Affine, _ acc: StrokeAccumulator) {
        guard rx > 0, ry > 0 else { return }
        let n = 64
        acc.move(m.apply(cx + rx, cy))
        for k in 1...n {
            let t = Double(k) / Double(n) * 2 * .pi
            acc.line(m.apply(cx + rx * cos(t), cy + ry * sin(t)))
        }
    }

    static func styleValue(_ style: String, _ key: String) -> String? {
        for decl in style.split(separator: ";") {
            guard let colon = decl.firstIndex(of: ":") else { continue }
            if decl[..<colon].trimmingCharacters(in: .whitespaces) == key {
                return decl[decl.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}

/// Walks SVG path data, feeding flattened segments (in mm) to an accumulator.
enum PathWalker {
    static func walk(_ d: String, _ m: Affine, _ acc: StrokeAccumulator) {
        var bytes = Array(d.utf8); bytes.append(0)
        bytes.withUnsafeBufferPointer { buf in
            var s = NumberScanner(buf)
            var cmd: UInt8 = 0
            var prev: UInt8 = 0
            var cx = 0.0, cy = 0.0, sx = 0.0, sy = 0.0   // current point, subpath start
            var lcx = 0.0, lcy = 0.0                     // last control point (for S/T)

            loop: while true {
                s.skipSeparators()
                let c = s.current
                if c == 0 { break }
                let isLetter = (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)
                if isLetter {
                    cmd = c; s.i += 1
                } else if cmd == 0 || cmd == UInt8(ascii: "Z") || cmd == UInt8(ascii: "z") {
                    break
                }
                let rel = cmd >= 0x61
                let ox = rel ? cx : 0, oy = rel ? cy : 0
                let up = rel ? cmd - 0x20 : cmd

                switch up {
                case UInt8(ascii: "M"):
                    guard let x = s.number(), let y = s.number() else { break loop }
                    cx = ox + x; cy = oy + y; sx = cx; sy = cy
                    acc.move(m.apply(cx, cy))
                    cmd = rel ? UInt8(ascii: "l") : UInt8(ascii: "L")
                case UInt8(ascii: "L"):
                    guard let x = s.number(), let y = s.number() else { break loop }
                    cx = ox + x; cy = oy + y
                    acc.line(m.apply(cx, cy))
                case UInt8(ascii: "H"):
                    guard let x = s.number() else { break loop }
                    cx = ox + x
                    acc.line(m.apply(cx, cy))
                case UInt8(ascii: "V"):
                    guard let y = s.number() else { break loop }
                    cy = (rel ? cy : 0) + y
                    acc.line(m.apply(cx, cy))
                case UInt8(ascii: "C"):
                    guard let x1 = s.number(), let y1 = s.number(), let x2 = s.number(), let y2 = s.number(),
                          let x = s.number(), let y = s.number() else { break loop }
                    cubic(cx, cy, ox + x1, oy + y1, ox + x2, oy + y2, ox + x, oy + y, m, acc)
                    lcx = ox + x2; lcy = oy + y2; cx = ox + x; cy = oy + y
                case UInt8(ascii: "S"):
                    guard let x2 = s.number(), let y2 = s.number(), let x = s.number(), let y = s.number() else { break loop }
                    let smooth = prev == UInt8(ascii: "C") || prev == UInt8(ascii: "S")
                    let x1 = smooth ? 2 * cx - lcx : cx, y1 = smooth ? 2 * cy - lcy : cy
                    cubic(cx, cy, x1, y1, ox + x2, oy + y2, ox + x, oy + y, m, acc)
                    lcx = ox + x2; lcy = oy + y2; cx = ox + x; cy = oy + y
                case UInt8(ascii: "Q"):
                    guard let x1 = s.number(), let y1 = s.number(), let x = s.number(), let y = s.number() else { break loop }
                    quad(cx, cy, ox + x1, oy + y1, ox + x, oy + y, m, acc)
                    lcx = ox + x1; lcy = oy + y1; cx = ox + x; cy = oy + y
                case UInt8(ascii: "T"):
                    guard let x = s.number(), let y = s.number() else { break loop }
                    let smooth = prev == UInt8(ascii: "Q") || prev == UInt8(ascii: "T")
                    let x1 = smooth ? 2 * cx - lcx : cx, y1 = smooth ? 2 * cy - lcy : cy
                    quad(cx, cy, x1, y1, ox + x, oy + y, m, acc)
                    lcx = x1; lcy = y1; cx = ox + x; cy = oy + y
                case UInt8(ascii: "A"):
                    guard let rx = s.number(), let ry = s.number(), let rot = s.number(),
                          let large = s.flag(), let sweep = s.flag(),
                          let x = s.number(), let y = s.number() else { break loop }
                    arc(cx, cy, rx, ry, rot, large, sweep, ox + x, oy + y, m, acc)
                    cx = ox + x; cy = oy + y
                case UInt8(ascii: "Z"):
                    acc.line(m.apply(sx, sy))
                    cx = sx; cy = sy
                default:
                    break loop
                }
                prev = up
            }
        }
    }

    private static func segments(_ polyLength: Double) -> Int { min(32, max(1, Int((polyLength / 0.5).rounded(.up)))) }

    private static func cubic(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double,
                              _ x3: Double, _ y3: Double, _ m: Affine, _ acc: StrokeAccumulator) {
        // Affine maps Béziers to Béziers: flatten the transformed control polygon.
        let p0 = m.apply(x0, y0), p1 = m.apply(x1, y1), p2 = m.apply(x2, y2), p3 = m.apply(x3, y3)
        let n = segments(p0.distance(to: p1) + p1.distance(to: p2) + p2.distance(to: p3))
        for k in 1...n {
            let t = Double(k) / Double(n), u = 1 - t
            let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
            acc.line(Point(x: a * p0.x + b * p1.x + c * p2.x + d * p3.x, y: a * p0.y + b * p1.y + c * p2.y + d * p3.y))
        }
    }

    private static func quad(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double,
                             _ m: Affine, _ acc: StrokeAccumulator) {
        let p0 = m.apply(x0, y0), p1 = m.apply(x1, y1), p2 = m.apply(x2, y2)
        let n = segments(p0.distance(to: p1) + p1.distance(to: p2))
        for k in 1...n {
            let t = Double(k) / Double(n), u = 1 - t
            acc.line(Point(x: u * u * p0.x + 2 * u * t * p1.x + t * t * p2.x, y: u * u * p0.y + 2 * u * t * p1.y + t * t * p2.y))
        }
    }

    /// SVG 1.1 implementation notes F.6.5: endpoint to centre parameterisation.
    private static func arc(_ x1: Double, _ y1: Double, _ rxIn: Double, _ ryIn: Double, _ rotDeg: Double,
                            _ large: Bool, _ sweep: Bool, _ x2: Double, _ y2: Double,
                            _ m: Affine, _ acc: StrokeAccumulator) {
        var rx = abs(rxIn), ry = abs(ryIn)
        if x1 == x2 && y1 == y2 { return }
        if rx == 0 || ry == 0 { acc.line(m.apply(x2, y2)); return }
        let phi = rotDeg * .pi / 180, cp = cos(phi), sp = sin(phi)
        let dx = (x1 - x2) / 2, dy = (y1 - y2) / 2
        let x1p = cp * dx + sp * dy, y1p = -sp * dx + cp * dy
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 { rx *= lambda.squareRoot(); ry *= lambda.squareRoot() }
        let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        let coef = (large != sweep ? 1.0 : -1.0) * (den > 0 ? max(0, num / den).squareRoot() : 0)
        let cxp = coef * rx * y1p / ry, cyp = -coef * ry * x1p / rx
        let cx = cp * cxp - sp * cyp + (x1 + x2) / 2
        let cy = sp * cxp + cp * cyp + (y1 + y2) / 2

        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        }
        let ux = (x1p - cxp) / rx, uy = (y1p - cyp) / ry
        let vx = (-x1p - cxp) / rx, vy = (-y1p - cyp) / ry
        let theta1 = angle(1, 0, ux, uy)
        var dTheta = angle(ux, uy, vx, vy)
        if !sweep && dTheta > 0 { dTheta -= 2 * .pi }
        if sweep && dTheta < 0 { dTheta += 2 * .pi }

        let n = min(64, max(2, Int((abs(dTheta) / (.pi / 32)).rounded(.up))))
        for k in 1...n {
            let t = theta1 + dTheta * Double(k) / Double(n)
            let ex = rx * cos(t), ey = ry * sin(t)
            acc.line(m.apply(cx + ex * cp - ey * sp, cy + ex * sp + ey * cp))
        }
    }
}
