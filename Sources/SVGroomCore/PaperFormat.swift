import Foundation

public struct PaperFormat: Sendable, Hashable {
    public let name: String
    public let shortMM: Double
    public let longMM: Double

    public enum Orientation: String, Sendable { case portrait = "Portrait", landscape = "Landscape", square = "Square" }

    public struct Match: Sendable, Hashable {
        /// Format name ("A3", "Letter"…) or "Custom".
        public let name: String
        public let orientation: Orientation
        public var label: String { "\(name) \(orientation.rawValue)" }
    }

    public static let all: [PaperFormat] = [
        .init(name: "A0", shortMM: 841, longMM: 1189),
        .init(name: "A1", shortMM: 594, longMM: 841),
        .init(name: "A2", shortMM: 420, longMM: 594),
        .init(name: "A3", shortMM: 297, longMM: 420),
        .init(name: "A4", shortMM: 210, longMM: 297),
        .init(name: "A5", shortMM: 148, longMM: 210),
        .init(name: "A6", shortMM: 105, longMM: 148),
        .init(name: "B3", shortMM: 353, longMM: 500),
        .init(name: "B4", shortMM: 250, longMM: 353),
        .init(name: "B5", shortMM: 176, longMM: 250),
        .init(name: "Letter", shortMM: 215.9, longMM: 279.4),
        .init(name: "Legal", shortMM: 215.9, longMM: 355.6),
        .init(name: "Tabloid", shortMM: 279.4, longMM: 431.8),
    ]

    public static let customName = "Custom"

    public static func match(widthMM w: Double, heightMM h: Double, tolerance: Double = 1.5) -> Match {
        let orientation: Orientation = abs(w - h) < tolerance ? .square : (w > h ? .landscape : .portrait)
        let short = min(w, h), long = max(w, h)
        let name = all.first { abs($0.shortMM - short) <= tolerance && abs($0.longMM - long) <= tolerance }?.name
        return Match(name: name ?? customName, orientation: orientation)
    }
}
