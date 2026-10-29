import Foundation
import Testing
@testable import SVGroomCore

private let a3 = """
<svg xmlns="http://www.w3.org/2000/svg" xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape" width="420mm" height="297mm" viewBox="0 0 840 594">\
<g inkscape:groupmode="layer" inkscape:label="One" style="stroke:#ff0000"><path d="M 20 20 L 220 20 L 220 120" style="fill:#00ff00;stroke-width:3"/></g>\
<g inkscape:groupmode="layer" inkscape:label="Two" transform="scale(2)"><line x1="10" y1="10" x2="60" y2="10"/></g>\
</svg>
"""

private func near(_ a: Double, _ b: Double, _ tol: Double = 0.01) -> Bool { abs(a - b) <= tol }

@Test func layoutKeepsFileWhenNothingChanges() {
    let analysis = SVGAnalyzer.analyze(data: Data(a3.utf8))!
    let l = Simulator.layout(analysis, SimulationSettings()) { _ in true }!
    #expect(l.canvas == SheetSize(width: 420, height: 297))
    #expect(l.scale == 1 && l.offsetX == 0 && l.offsetY == 0)
    // Drawing spans (10,10)–(110,60) mm.
    #expect(near(l.drawing!.minX, 10) && near(l.drawing!.maxX, 110) && near(l.drawing!.maxY, 60))
}

@Test func layoutScalesLongestSideAndCentres() {
    let analysis = SVGAnalyzer.analyze(data: Data(a3.utf8))!
    var s = SimulationSettings()
    s.canvas = SheetSize(width: 297, height: 420)
    s.longestSideMM = 200
    let l = Simulator.layout(analysis, s) { _ in true }!
    #expect(near(l.scale, 2))
    let d = l.drawing!
    #expect(near(d.width, 200) && near(d.height, 100))
    #expect(near((d.minX + d.maxX) / 2, 148.5) && near((d.minY + d.maxY) / 2, 210))
    #expect(l.fits)

    s.longestSideMM = 400
    #expect(!Simulator.layout(analysis, s) { _ in true }!.fits)
}

@Test func renderSetsSheetPensAndLeavesNoFill() throws {
    let analysis = SVGAnalyzer.analyze(data: Data(a3.utf8))!
    var s = SimulationSettings()
    s.canvas = SheetSize(width: 594, height: 420)
    s.penWidthMM = 0.5
    s.penColors = [1: "#0000ff"]
    let layout = Simulator.layout(analysis, s) { _ in true }!
    let out = try XMLDocument(data: Simulator.render(Data(a3.utf8), layout: layout, settings: s)!)
    let root = out.rootElement()!
    #expect(root.attribute(forName: "width")?.stringValue == "594.0mm")
    #expect(root.attribute(forName: "viewBox")?.stringValue == "0 0 594.0 420.0")

    let path = try #require(try out.nodes(forXPath: "//*[local-name()='path']").first as? XMLElement)
    let pathStyle = path.attribute(forName: "style")!.stringValue!
    // Root scale is 0.5 mm per unit, so 0.5 mm of pen is 1 user unit; layer one keeps its red.
    #expect(pathStyle.contains("stroke-width:1.0") && pathStyle.contains("fill:none"))
    #expect(!pathStyle.contains("#00ff00") && !pathStyle.contains("stroke:"))

    let line = try #require(try out.nodes(forXPath: "//*[local-name()='line']").first as? XMLElement)
    let lineStyle = line.attribute(forName: "style")!.stringValue!
    // Layer two is scaled ×2 more, so the same pen is half as many user units.
    #expect(lineStyle.contains("stroke-width:0.5") && lineStyle.contains("stroke:#0000ff"))

    // Hidden layers can still be stripped afterwards with the same numbering.
    let edited = LayerEditor.render(Simulator.render(Data(a3.utf8), layout: layout, settings: s)!, overrides: [1: false])!
    #expect(try XMLDocument(data: edited).nodes(forXPath: "//*[local-name()='line']").isEmpty)
}
