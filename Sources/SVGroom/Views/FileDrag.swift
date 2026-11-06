import AppKit
import SVGroomCore
import SwiftUI

/// Dragging SVG files out of the app (Finder, other apps): they receive copies of the files,
/// named after their folders like “Copy to Folder” does, so many “01Front.svg” don't clash.
enum FileDrag {
    /// Where the renamed copies for drags are made. Emptied when the app launches.
    static let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SVGroom Drags")

    /// Starts dragging `urls` from `view`, one preview per file, slightly fanned out under the pointer.
    static func begin(_ urls: [URL], image: NSImage?, event: NSEvent, from view: NSView & NSDraggingSource) {
        guard !urls.isEmpty else { return }
        let urls = renamedCopies(urls)
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

    /// Copies of `urls` in a new temporary folder, named with `CopyNames` (“coral_01Front.svg”).
    /// The originals when copying fails.
    private static func renamedCopies(_ urls: [URL]) -> [URL] {
        let dir = folder.appendingPathComponent(UUID().uuidString)
        let names = CopyNames.names(for: urls.map(\.path))
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return try zip(urls, names).map { url, name in
                let copy = dir.appendingPathComponent(name)
                try FileManager.default.copyItem(at: url, to: copy)
                return copy
            }
        } catch {
            return urls
        }
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
