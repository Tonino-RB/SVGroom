import Foundation
import Testing
@testable import SVGroomCore

@Test func expandPageKeepsDrawingInPlace() throws {
    // 200 × 100 mm page drawn at 2 user units per mm, shifted by the viewBox origin.
    let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="200mm" height="100mm" viewBox="10 20 400 200" x="5"></svg>"#
    let data = try #require(LayerEditor.expandPage(Data(svg.utf8), to: MMRect(minX: -10, minY: -5, maxX: 210, maxY: 100)))
    let root = try #require(try XMLDocument(data: data).rootElement())
    #expect(root.attribute(forName: "width")?.stringValue == "220.0mm")
    #expect(root.attribute(forName: "height")?.stringValue == "105.0mm")
    #expect(root.attribute(forName: "viewBox")?.stringValue == "-10.0 10.0 440.0 210.0")
    #expect(root.attribute(forName: "preserveAspectRatio")?.stringValue == "none")
    #expect(root.attribute(forName: "x") == nil)
}
