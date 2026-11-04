import AppKit
import SwiftUI

/// Dragging SVG files out of the app (Finder, other apps): they receive copies of the files.
enum FileDrag {
    /// Starts dragging `urls` from `view`, one preview per file, slightly fanned out under the pointer.
    static func begin(_ urls: [URL], image: NSImage?, event: NSEvent, from view: NSView & NSDraggingSource) {
        guard !urls.isEmpty else { return }
        let p = view.convert(event.locationInWindow, from: nil)
        let side = 72.0
        let items = urls.enumerated().map { i, url -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = image ?? NSWorkspace.shared.icon(forFile: url.path)
            let offset = Double(min(i, 4)) * 6
            item.setDraggingFrame(NSRect(x: p.x - side / 2 + offset, y: p.y - side / 2 - offset, width: side, height: side),
                                  contents: icon)
            return item
        }
        let session = view.beginDraggingSession(with: items, event: event, source: view)
        session.draggingFormation = .pile
    }

    /// Pointer travel before a press becomes a drag.
    static func isDrag(from down: NSEvent, to event: NSEvent) -> Bool {
        hypot(event.locationInWindow.x - down.locationInWindow.x, event.locationInWindow.y - down.locationInWindow.y) > 4
    }
}

/// Transparent layer over a grid cell: handles its left clicks and dragging its files out.
/// Right and control clicks go through, to the cell's context menu.
struct FileDragArea: NSViewRepresentable {
    let image: NSImage?
    /// Called on mouse down (the event carries the click count and modifiers).
    let onMouseDown: (NSEvent) -> Void
    /// Called on mouse up when the press did not become a drag.
    let onClick: (NSEvent) -> Void
    let urls: () -> [URL]

    func makeNSView(context: Context) -> DragView { DragView() }

    func updateNSView(_ view: DragView, context: Context) { view.area = self }

    final class DragView: NSView, NSDraggingSource {
        var area: FileDragArea?
        private var down: NSEvent?

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let e = NSApp.currentEvent, !e.modifierFlags.contains(.control) else { return nil }
            switch e.type {
            case .leftMouseDown, .leftMouseDragged, .leftMouseUp: return super.hitTest(point)
            default: return nil
            }
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            down = event
            area?.onMouseDown(event)
        }

        override func mouseDragged(with event: NSEvent) {
            guard let down, FileDrag.isDrag(from: down, to: event), let area else { return }
            self.down = nil
            FileDrag.begin(area.urls(), image: area.image, event: down, from: self)
        }

        override func mouseUp(with event: NSEvent) {
            if down != nil { area?.onClick(event) }
            down = nil
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .outsideApplication ? .copy : []
        }
    }
}
