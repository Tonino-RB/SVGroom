import Foundation

/// Axis-aligned rectangle in millimetres (page coordinates, y down).
public struct MMRect: Codable, Sendable, Equatable {
    public var minX, minY, maxX, maxY: Double

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX; self.minY = minY; self.maxX = maxX; self.maxY = maxY
    }

    public func union(_ o: MMRect) -> MMRect {
        MMRect(minX: min(minX, o.minX), minY: min(minY, o.minY),
               maxX: max(maxX, o.maxX), maxY: max(maxY, o.maxY))
    }

    public var width: Double { maxX - minX }
    public var height: Double { maxY - minY }
}

/// Plotting statistics for one Inkscape layer (or for content outside any layer).
public struct LayerStats: Codable, Sendable, Equatable {
    public var name: String
    public var hiddenInFile: Bool
    /// First stroke colour found in the layer, as written in the file (e.g. "#ff0000").
    public var color: String?
    /// Number of drawable elements (path, line, circle…).
    public var elements: Int = 0
    /// Pen-down strokes, i.e. number of pen lifts.
    public var strokes: Int = 0
    /// Pen-down distance in mm.
    public var drawMM: Double = 0
    /// Pen-up distance in mm, starting from and returning to the home corner (0,0).
    public var travelMM: Double = 0
    public var bounds: MMRect?

    public init(name: String, hiddenInFile: Bool = false) {
        self.name = name
        self.hiddenInFile = hiddenInFile
    }

    public mutating func add(_ o: LayerStats) {
        elements += o.elements
        strokes += o.strokes
        drawMM += o.drawMM
        travelMM += o.travelMM
        if let b = o.bounds { bounds = bounds.map { $0.union(b) } ?? b }
    }
}

public struct SVGAnalysis: Codable, Sendable, Equatable {
    public var version: Int
    public var widthMM: Double?
    public var heightMM: Double?
    /// Top-level Inkscape layers, in document order.
    public var layers: [LayerStats]
    /// Everything drawn outside of a layer.
    public var unlayered: LayerStats
    public var textCount = 0
    public var imageCount = 0
    public var useCount = 0

    /// Sum of the unlayered content and every layer for which `visible(index)` is true.
    public func totals(visible: (Int) -> Bool) -> LayerStats {
        var t = unlayered
        t.name = "Total"
        for (i, l) in layers.enumerated() where visible(i) { t.add(l) }
        return t
    }

    /// Totals using the visibility saved in the file.
    public var fileTotals: LayerStats { totals { !layers[$0].hiddenInFile } }

    public var format: PaperFormat.Match? {
        guard let w = widthMM, let h = heightMM else { return nil }
        return PaperFormat.match(widthMM: w, heightMM: h)
    }

    /// True when the drawing extends more than 0.5 mm past the page.
    public func exceedsPage(_ stats: LayerStats) -> Bool {
        guard let b = stats.bounds, let w = widthMM, let h = heightMM else { return false }
        let tol = 0.5
        return b.minX < -tol || b.minY < -tol || b.maxX > w + tol || b.maxY > h + tol
    }
}

/// Rough pen-plotter timing model: constant speeds, fixed time per pen lift, no acceleration.
public struct PlotSettings: Sendable, Equatable {
    public var drawSpeed: Double   // mm/s, pen down
    public var travelSpeed: Double // mm/s, pen up
    public var liftTime: Double    // s per pen up + pen down

    public init(drawSpeed: Double = 40, travelSpeed: Double = 120, liftTime: Double = 0.3) {
        self.drawSpeed = drawSpeed; self.travelSpeed = travelSpeed; self.liftTime = liftTime
    }

    public func seconds(_ s: LayerStats) -> Double {
        s.drawMM / max(drawSpeed, 0.1) + s.travelMM / max(travelSpeed, 0.1) + Double(s.strokes) * liftTime
    }

    public static func format(seconds: Double) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s) s" }
        if s < 3600 { return "\(s / 60) min" }
        return "\(s / 3600) h \(String(format: "%02d", (s % 3600) / 60))"
    }
}
