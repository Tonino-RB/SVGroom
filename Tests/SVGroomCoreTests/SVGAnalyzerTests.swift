import Foundation
import Testing
@testable import SVGroomCore

private func analyze(_ body: String, root: String = #"width="420mm" height="297mm" viewBox="0 0 420 297""#) -> SVGAnalysis {
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape" \(root)>\(body)</svg>
    """
    return SVGAnalyzer.analyze(data: Data(svg.utf8))!
}

private func near(_ a: Double, _ b: Double, _ tol: Double = 0.05) -> Bool { abs(a - b) <= tol }

@Test func pageSizeAndFormat() {
    let a = analyze("")
    #expect(a.widthMM == 420 && a.heightMM == 297)
    #expect(a.format?.label == "A3 Landscape")

    let px = analyze("", root: #"width="793.7" height="1122.5""#)
    #expect(px.format?.label == "A4 Portrait")

    let inches = analyze("", root: #"width="8.5in" height="11in" viewBox="0 0 850 1100""#)
    #expect(inches.format?.name == "Letter")
}

@Test func lineLengthTravelAndLifts() {
    let a = analyze(#"<path d="M 10 0 L 40 0 M 40 40 l 0 -10"/>"#)
    let t = a.fileTotals
    #expect(t.strokes == 2)
    #expect(near(t.drawMM, 30 + 10))
    // home → (10,0) = 10, (40,0) → (40,40) = 40, (40,30) → home = 50
    #expect(near(t.travelMM, 10 + 40 + 50))
}

@Test func circleAndArcLengths() {
    let c = analyze(#"<circle cx="100" cy="100" r="50"/>"#).fileTotals
    #expect(near(c.drawMM, 2 * .pi * 50, 0.2))

    // Two half circles of radius 10 written as arcs, compact flag syntax.
    let arc = analyze(#"<path d="M0 0a10 10 0 0120 0a10 10 0 01-20 0z"/>"#).fileTotals
    #expect(near(arc.drawMM, 2 * .pi * 10, 0.15))
}

@Test func cubicMatchesQuarterCircle() {
    // Standard 4-arc Bézier circle approximation, r = 100.
    let k = 55.228475
    let d = "M100 0 C100 \(k) \(k) 100 0 100 C-\(k) 100 -100 \(k) -100 0 C-100 -\(k) -\(k) -100 0 -100 C\(k) -100 100 -\(k) 100 0Z"
    let t = analyze(#"<path d="\#(d)"/>"#).fileTotals
    #expect(near(t.drawMM, 2 * .pi * 100, 0.5))
}

@Test func transformsAndViewBoxScaling() {
    // viewBox is half the page size: every user unit is 2 mm.
    let a = analyze(#"<g transform="translate(10 0) scale(2)"><line x1="0" y1="0" x2="5" y2="0"/></g>"#,
                    root: #"width="200mm" height="100mm" viewBox="0 0 100 50""#)
    #expect(near(a.fileTotals.drawMM, 20))
    #expect(near(a.fileTotals.bounds!.minX, 20))
}

@Test func layersHiddenAndColors() {
    let a = analyze("""
    <g inkscape:groupmode="layer" inkscape:label="1 black" stroke="#000"><rect x="0" y="0" width="10" height="10"/></g>
    <g inkscape:groupmode="layer" inkscape:label="2 red" style="display:none"><path stroke="red" d="M0 0 H 100"/></g>
    <line x1="0" y1="0" x2="0" y2="5"/>
    <text>ignored</text><defs><path d="M0 0 H 1000"/></defs>
    """)
    #expect(a.layers.map(\.name) == ["1 black", "2 red"])
    #expect(a.layers[0].color == "#000" && a.layers[1].color == "red")
    #expect(a.layers[1].hiddenInFile)
    #expect(near(a.layers[0].drawMM, 40))
    #expect(near(a.layers[1].drawMM, 100))
    #expect(near(a.fileTotals.drawMM, 45))
    #expect(near(a.totals { _ in true }.drawMM, 145))
    #expect(a.textCount == 1)
}

@Test func plotTimeMatchesAxiDraw() {
    // References: AxiDraw software 3.9.5 in preview mode (pt_estimate), model A3, default PlotSettings
    // (pen-down 20 %, pen-up 75 %, accel 50 %, up 60 / down 30, raise 100 %, lower 50 %).
    let line = analyze(#"<path d="M 20 20 L 400 20"/>"#).fileTotals
    #expect(near(line.seconds, 13.036, 0.05))
    let dashes = (0..<10).map { #"<path d="M\#(20 + Double($0) * 6.3) 20 L\#(22 + Double($0) * 6.3) 21"/>"# }.joined()
    #expect(near(analyze(dashes).fileTotals.seconds, 7.629, 0.05))
    let circle = analyze(#"<path d="M105 100 A5 5 0 1 0 95 100 A5 5 0 1 0 105 100"/>"#).fileTotals
    #expect(near(circle.seconds, 3.368, 0.05))
    #expect(PlotSettings.format(seconds: 3725) == "1 h 02")
}

@Test func motionModel() {
    let m = MotionModel(PlotSettings())
    // A long move cruises: d/v plus v/a lost to speeding up and slowing down.
    #expect(near(MotionModel.moveTime(1000, v0: 0, v1: 0, vmax: 40, accel: 500), 1000.0 / 40 + 40.0 / 500, 1e-9))
    // A move too short for two ramps (AxiDraw: under 5 time slices) ramps down from half its peak speed: 4·√(d/a).
    #expect(near(MotionModel.moveTime(2, v0: 0, v1: 0, vmax: 40, accel: 500), 4 * (2.0 / 500).squareRoot(), 1e-9))
    // Same length: straight is faster than with a U-turn, and collinear points don't slow down.
    let straight = m.strokeTime([Point(x: 0, y: 0), Point(x: 100, y: 0)])
    let split = m.strokeTime([Point(x: 0, y: 0), Point(x: 50, y: 0), Point(x: 100, y: 0)])
    let uTurn = m.strokeTime([Point(x: 0, y: 0), Point(x: 50, y: 0), Point(x: 0, y: 0)])
    #expect(near(straight, split, 1e-9))
    #expect(near(uTurn - straight, m.downSpeed / m.downAccel, 1e-9))
}

@Test func touchingPathsAreJoined() {
    let t = analyze(#"<path d="M 10 10 L 20 10"/><path d="M 20 10 L 30 10"/><path d="M 40 10 L 50 10"/>"#).fileTotals
    #expect(t.strokes == 2)
}

@Test func layerEditorRemovesHiddenAndAppliesOverrides() {
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape">
    <g inkscape:groupmode="layer" id="a"/><g inkscape:groupmode="layer" id="b" style="display:none;opacity:1"/>
    </svg>
    """
    let data = Data(svg.utf8)
    #expect(LayerEditor.needsEditing(data, overrides: [:]))
    let hidden = String(decoding: LayerEditor.render(data, overrides: [:])!, as: UTF8.self)
    #expect(hidden.contains("id=\"a\"") && !hidden.contains("id=\"b\""))
    let swapped = String(decoding: LayerEditor.render(data, overrides: [0: false, 1: true])!, as: UTF8.self)
    #expect(!swapped.contains("id=\"a\"") && swapped.contains("id=\"b\"") && !swapped.contains("display"))
}
