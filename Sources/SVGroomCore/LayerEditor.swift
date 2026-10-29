import Foundation

/// Prepares SVG data for the native (CoreSVG) renderer, which ignores `display:none`:
/// hidden elements are removed, and top-level layers can be forced on or off.
public enum LayerEditor {
    /// Cheap check to skip the XML round trip when nothing would change.
    public static func needsEditing(_ data: Data, overrides: [Int: Bool]) -> Bool {
        if !overrides.isEmpty { return true }
        return data.range(of: Data("display:none".utf8)) != nil
            || data.range(of: Data("display=\"none\"".utf8)) != nil
            || data.range(of: Data("display: none".utf8)) != nil
    }

    /// `overrides` maps a top-level layer index (document order) to its wanted visibility.
    public static func render(_ data: Data, overrides: [Int: Bool]) -> Data? {
        guard let doc = try? XMLDocument(data: data, options: [.nodePreserveAll]), let root = doc.rootElement() else { return nil }

        var layerIndex = 0
        func visit(_ el: XMLElement, insideLayer: Bool) {
            for child in el.children ?? [] {
                guard let c = child as? XMLElement else { continue }
                var isLayer = false
                if !insideLayer, c.localName == "g",
                   c.attributes?.first(where: { $0.name?.hasSuffix("groupmode") == true })?.stringValue == "layer" {
                    isLayer = true
                    let index = layerIndex
                    layerIndex += 1
                    if let visible = overrides[index] {
                        if visible { show(c) } else { c.detach(); continue }
                    }
                }
                if isHidden(c) { c.detach(); continue }
                if c.localName == "defs" { continue }
                visit(c, insideLayer: insideLayer || isLayer)
            }
        }
        visit(root, insideLayer: false)
        return doc.xmlData(options: [.nodePreserveAll])
    }

    /// Enlarges the page to `rect` (page millimetres, may reach past the page) so the renderer,
    /// which clips to the page, also draws what lies outside it.
    public static func expandPage(_ data: Data, to rect: MMRect) -> Data? {
        guard let doc = try? XMLDocument(data: data, options: [.nodePreserveAll]), let root = doc.rootElement() else { return nil }
        let attributes = Dictionary((root.attributes ?? []).compactMap { a in a.name.map { ($0, a.stringValue ?? "") } },
                                    uniquingKeysWith: { first, _ in first })
        let m = SVGUnits.rootTransform(attributes).transform
        guard m.a != 0, m.d != 0 else { return nil }

        let values = [
            ("width", "\(rect.width)mm"),
            ("height", "\(rect.height)mm"),
            ("viewBox", "\((rect.minX - m.e) / m.a) \((rect.minY - m.f) / m.d) \(rect.width / m.a) \(rect.height / m.d)"),
            ("preserveAspectRatio", "none"),
        ]
        for (name, value) in values {
            root.removeAttribute(forName: name)
            root.addAttribute(XMLNode.attribute(withName: name, stringValue: value) as! XMLNode)
        }
        root.removeAttribute(forName: "x")
        root.removeAttribute(forName: "y")
        return doc.xmlData(options: [.nodePreserveAll])
    }

    private static func isHidden(_ el: XMLElement) -> Bool {
        if el.attribute(forName: "display")?.stringValue == "none" { return true }
        guard let style = el.attribute(forName: "style")?.stringValue else { return false }
        return style.split(separator: ";").contains {
            $0.replacingOccurrences(of: " ", with: "").lowercased() == "display:none"
        }
    }

    private static func show(_ el: XMLElement) {
        el.removeAttribute(forName: "display")
        guard let style = el.attribute(forName: "style")?.stringValue else { return }
        let kept = style.split(separator: ";").filter {
            !$0.trimmingCharacters(in: .whitespaces).hasPrefix("display")
        }
        el.attribute(forName: "style")?.stringValue = kept.joined(separator: ";")
    }
}
