import Foundation

struct Point {
    var x: Double
    var y: Double

    func distance(to p: Point) -> Double { ((p.x - x) * (p.x - x) + (p.y - y) * (p.y - y)).squareRoot() }

    /// Distance to the segment from `a` to `b`.
    func distance(toSegment a: Point, _ b: Point) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y, len2 = dx * dx + dy * dy
        guard len2 > 0 else { return distance(to: a) }
        let t = max(0, min(1, ((x - a.x) * dx + (y - a.y) * dy) / len2))
        return distance(to: Point(x: a.x + t * dx, y: a.y + t * dy))
    }
}

/// 2D affine transform, SVG `matrix(a b c d e f)` convention.
struct Affine {
    var a = 1.0, b = 0.0, c = 0.0, d = 1.0, e = 0.0, f = 0.0

    static let identity = Affine()

    static func translate(_ x: Double, _ y: Double) -> Affine { Affine(e: x, f: y) }
    static func scale(_ x: Double, _ y: Double) -> Affine { Affine(a: x, d: y) }
    static func rotate(degrees: Double) -> Affine {
        let r = degrees * .pi / 180
        return Affine(a: cos(r), b: sin(r), c: -sin(r), d: cos(r))
    }

    func apply(_ x: Double, _ y: Double) -> Point { Point(x: a * x + c * y + e, y: b * x + d * y + f) }

    /// `self × m`: `m` is applied first, then `self`.
    func concatenating(_ m: Affine) -> Affine {
        Affine(a: a * m.a + c * m.b, b: b * m.a + d * m.b,
               c: a * m.c + c * m.d, d: b * m.c + d * m.d,
               e: a * m.e + c * m.f + e, f: b * m.e + d * m.f + f)
    }
}

/// Fast number scanner over a NUL-terminated UTF-8 buffer (SVG path data, points, transforms).
struct NumberScanner {
    let buf: UnsafeBufferPointer<UInt8>
    var i = 0

    init(_ buf: UnsafeBufferPointer<UInt8>) { self.buf = buf }

    var current: UInt8 { i < buf.count ? buf[i] : 0 }

    mutating func skipSeparators() {
        while true {
            let c = current
            guard c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x2C else { return }
            i += 1
        }
    }

    mutating func number() -> Double? {
        skipSeparators()
        let c = current
        // Only start on characters that can begin an SVG number, so strtod never sees "inf"/"nan".
        guard (c >= 0x30 && c <= 0x39) || c == 0x2E || c == 0x2D || c == 0x2B else { return nil }
        let start = buf.baseAddress! + i
        var end: UnsafeMutablePointer<CChar>?
        let v = start.withMemoryRebound(to: CChar.self, capacity: buf.count - i) { p -> Double in
            strtod(p, &end)
        }
        guard let end else { return nil }
        let consumed = UnsafeRawPointer(end) - UnsafeRawPointer(start)
        guard consumed > 0 else { return nil }
        i += consumed
        return v
    }

    /// Arc flags may be written without separators ("a10 10 0 0110 10").
    mutating func flag() -> Bool? {
        skipSeparators()
        switch current {
        case 0x30: i += 1; return false
        case 0x31: i += 1; return true
        default: return nil
        }
    }

    /// Reads every number in the buffer.
    static func numbers(in s: String) -> [Double] {
        var bytes = Array(s.utf8); bytes.append(0)
        return bytes.withUnsafeBufferPointer { b in
            var sc = NumberScanner(b)
            var out: [Double] = []
            while let n = sc.number() { out.append(n) }
            return out
        }
    }
}

enum SVGUnits {
    static let mmPerPx = 25.4 / 96

    /// Millimetres per unit, nil for relative units.
    private static func mmPerUnit(_ unit: String) -> Double? {
        switch unit.lowercased() {
        case "", "px": return mmPerPx
        case "mm": return 1
        case "cm": return 10
        case "in": return 25.4
        case "pt": return 25.4 / 72
        case "pc": return 25.4 / 6
        case "q": return 0.25
        default: return nil
        }
    }

    private static func split(_ s: String) -> (Double, String)? {
        let t = s.trimmingCharacters(in: .whitespaces)
        var bytes = Array(t.utf8); bytes.append(0)
        let r: (Double, Int)? = bytes.withUnsafeBufferPointer { b in
            var sc = NumberScanner(b)
            guard let v = sc.number() else { return nil }
            return (v, sc.i)
        }
        guard let (v, idx) = r else { return nil }
        let unit = String(decoding: Array(t.utf8.dropFirst(idx)), as: UTF8.self)
        return (v, unit.trimmingCharacters(in: .whitespaces))
    }

    /// Absolute length in mm ("210mm", "8.5in", "800" = px). Nil for %, em, missing.
    static func mm(_ s: String?) -> Double? {
        guard let s, let (v, unit) = split(s), let k = mmPerUnit(unit) else { return nil }
        return v * k
    }

    /// Length in user units (px), used for shape attributes.
    static func user(_ s: String?) -> Double {
        guard let s, let (v, unit) = split(s) else { return 0 }
        guard let k = mmPerUnit(unit) else { return v }
        return v * k / mmPerPx
    }

    /// Root `<svg>` user units → page millimetres, with the page size when known.
    static func rootTransform(_ a: [String: String]) -> (transform: Affine, widthMM: Double?, heightMM: Double?) {
        let w = mm(a["width"]), h = mm(a["height"])
        let vb = a["viewBox"].map(NumberScanner.numbers(in:)) ?? []
        if vb.count == 4, vb[2] > 0, vb[3] > 0 {
            let pageW = w ?? vb[2] * mmPerPx
            let pageH = h ?? vb[3] * mmPerPx
            let sx = pageW / vb[2], sy = pageH / vb[3]
            if a["preserveAspectRatio"]?.hasPrefix("none") == true {
                return (Affine.scale(sx, sy).concatenating(.translate(-vb[0], -vb[1])), pageW, pageH)
            }
            // Default xMidYMid meet.
            let s = min(sx, sy)
            let tx = (pageW - vb[2] * s) / 2, ty = (pageH - vb[3] * s) / 2
            return (Affine.translate(tx, ty).concatenating(.scale(s, s)).concatenating(.translate(-vb[0], -vb[1])), pageW, pageH)
        }
        return (.scale(mmPerPx, mmPerPx), w, h)
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

enum TransformParser {
    static func parse(_ s: String) -> Affine {
        var result = Affine.identity
        var rest = Substring(s)
        while let open = rest.firstIndex(of: "("), let close = rest[open...].firstIndex(of: ")") {
            let name = rest[..<open].trimmingCharacters(in: CharacterSet(charactersIn: " ,\t\n\r"))
            let v = NumberScanner.numbers(in: String(rest[rest.index(after: open)..<close]))
            rest = rest[rest.index(after: close)...]
            let m: Affine
            switch name {
            case "matrix" where v.count >= 6:
                m = Affine(a: v[0], b: v[1], c: v[2], d: v[3], e: v[4], f: v[5])
            case "translate" where v.count >= 1:
                m = .translate(v[0], v.count > 1 ? v[1] : 0)
            case "scale" where v.count >= 1:
                m = .scale(v[0], v.count > 1 ? v[1] : v[0])
            case "rotate" where v.count >= 1:
                if v.count >= 3 {
                    m = Affine.translate(v[1], v[2]).concatenating(.rotate(degrees: v[0])).concatenating(.translate(-v[1], -v[2]))
                } else {
                    m = .rotate(degrees: v[0])
                }
            case "skewX" where v.count >= 1:
                m = Affine(c: tan(v[0] * .pi / 180))
            case "skewY" where v.count >= 1:
                m = Affine(b: tan(v[0] * .pi / 180))
            default:
                continue
            }
            result = result.concatenating(m)
        }
        return result
    }
}
