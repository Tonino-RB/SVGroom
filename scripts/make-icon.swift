// Draws the SVGroom app icon and writes Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift [preview.png]
import AppKit

let ink = CGColor(red: 0.17, green: 0.29, blue: 0.85, alpha: 1)
let vermilion = CGColor(red: 0.90, green: 0.28, blue: 0.18, alpha: 1)
let amber = CGColor(red: 1.00, green: 0.73, blue: 0.10, alpha: 1)

/// Draws on a 1024 × 1024 canvas (origin bottom-left); the caller scales the context.
func drawIcon(_ c: CGContext) {
    // macOS icon grid: 824 pt rounded square centred on the canvas.
    let tile = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
                      cornerWidth: 185, cornerHeight: 185, transform: nil)
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.35))
    c.addPath(tile)
    c.setFillColor(CGColor(red: 0.07, green: 0.10, blue: 0.17, alpha: 1))
    c.fillPath()
    c.restoreGState()

    c.saveGState()
    c.addPath(tile)
    c.clip()
    let bg = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                        colors: [CGColor(red: 0.16, green: 0.22, blue: 0.36, alpha: 1),
                                 CGColor(red: 0.06, green: 0.09, blue: 0.16, alpha: 1)] as CFArray,
                        locations: [0, 1])!
    c.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    // A sheet of paper (√2 ratio), slightly tilted, carrying plotted wave lines in two pens.
    let w = 440.0, h = w * 2.0.squareRoot()
    c.translateBy(x: 500, y: 520)
    c.rotate(by: 0.07)
    let sheet = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: CGColor(gray: 0, alpha: 0.5))
    c.setFillColor(CGColor(gray: 1, alpha: 1))
    c.fill(sheet)
    c.restoreGState()

    c.setLineCap(.round)
    c.setLineJoin(.round)
    c.setLineWidth(9)
    let margin = 52.0, lines = 11
    for i in 0..<lines {
        let t = Double(i) / Double(lines - 1)
        let y0 = -h / 2 + margin + 30 + t * (h - 2 * margin - 60)
        c.beginPath()
        for k in 0...120 {
            let u = Double(k) / 120
            let x = -w / 2 + margin + u * (w - 2 * margin)
            let y = y0 + 34 * sin(u * 2 * .pi * 1.3 + t * 2.4) * sin(.pi * u)
            k == 0 ? c.move(to: CGPoint(x: x, y: y)) : c.addLine(to: CGPoint(x: x, y: y))
        }
        c.setStrokeColor(i % 3 == 1 ? vermilion : ink)
        c.strokePath()
    }
    c.restoreGState()

    // Rating star, bottom right.
    let centre = CGPoint(x: 735, y: 265), outer = 128.0, inner = outer * 0.45
    let star = CGMutablePath()
    for k in 0..<10 {
        let r = k % 2 == 0 ? outer : inner
        let a = .pi / 2 + Double(k) * .pi / 5
        let p = CGPoint(x: centre.x + r * cos(a), y: centre.y + r * sin(a))
        k == 0 ? star.move(to: p) : star.addLine(to: p)
    }
    star.closeSubpath()
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: CGColor(gray: 0, alpha: 0.45))
    c.addPath(star)
    c.setFillColor(amber)
    c.fillPath()
    c.restoreGState()
    c.addPath(star)
    c.setLineJoin(.round)
    c.setLineWidth(10)
    c.setStrokeColor(CGColor(gray: 1, alpha: 1))
    c.strokePath()
}

func png(size: Int) -> Data {
    let c = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    drawIcon(c)
    return NSBitmapImageRep(cgImage: c.makeImage()!).representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try png(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try png(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
if CommandLine.arguments.count > 1 {
    try png(size: 1024).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
