import SwiftUI
import SVGroomCore

extension ColorLabel {
    var title: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .none: .clear
        case .red: .red
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        }
    }

    /// Lightroom keys: 6 red, 7 yellow, 8 green, 9 blue.
    var key: String? {
        switch self {
        case .red: "6"
        case .yellow: "7"
        case .green: "8"
        case .blue: "9"
        default: nil
        }
    }
}

extension Color {
    /// Parses the SVG colours a plotter file usually contains (hex, rgb(), common names).
    init?(svg: String) {
        let s = svg.trimmingCharacters(in: .whitespaces).lowercased()
        if s.hasPrefix("#") {
            var hex = String(s.dropFirst())
            if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
            guard hex.count == 6, let v = UInt32(hex, radix: 16) else { return nil }
            self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
        } else if s.hasPrefix("rgb(") {
            let n = s.dropFirst(4).dropLast().split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard n.count == 3 else { return nil }
            self.init(red: n[0] / 255, green: n[1] / 255, blue: n[2] / 255)
        } else {
            let named: [String: Color] = [
                "black": .black, "white": .white, "red": .red, "green": .green, "blue": .blue,
                "yellow": .yellow, "orange": .orange, "purple": .purple, "pink": .pink, "brown": .brown,
                "gray": .gray, "grey": .gray, "cyan": .cyan, "magenta": Color(red: 1, green: 0, blue: 1),
            ]
            guard let c = named[s] else { return nil }
            self = c
        }
    }
}

struct StarsView: View {
    let rating: Int
    var size: CGFloat = 9

    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= rating ? "star.fill" : "star")
                    .foregroundStyle(i <= rating ? AnyShapeStyle(.primary) : AnyShapeStyle(.quaternary))
            }
        }
        .font(.system(size: size))
    }
}

/// Clickable stars; clicking the current rating clears it. `rating` is nil for a mixed selection.
struct StarsEditor: View {
    let rating: Int?
    let set: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { i in
                Button { set(rating == i ? 0 : i) } label: {
                    Image(systemName: i <= (rating ?? 0) ? "star.fill" : "star")
                        .font(.system(size: 15))
                        .foregroundStyle(i <= (rating ?? 0) ? Color.primary : Color.secondary)
                }
                .buttonStyle(.plain)
                .help("\(i) star\(i > 1 ? "s" : "") (\(i))")
            }
            if rating == nil { Text("Mixed").font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct FlagIcon: View {
    let flag: Flag

    var body: some View {
        switch flag {
        case .none: EmptyView()
        case .picked: Image(systemName: "flag.fill").foregroundStyle(.primary)
        case .rejected: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }
}

struct LabelDot: View {
    let label: ColorLabel
    var size: CGFloat = 9

    var body: some View {
        if label != .none {
            Circle().fill(label.color).frame(width: size, height: size)
        }
    }
}

/// One AxiDraw setting in percent, stored in UserDefaults.
struct PercentField: View {
    let label: String
    @AppStorage private var value: Double

    init(key: String, label: String, default value: Double) {
        self.label = label
        _value = AppStorage(wrappedValue: value, key)
    }

    var body: some View {
        TextField(label, value: $value, format: .number)
            .overlay(alignment: .trailing) { Text("%").foregroundStyle(.secondary).padding(.trailing, 4) }
    }
}

/// Context menu shared by grid cells. Right-clicking outside the selection acts on that item only.
struct ItemContextMenu: View {
    @Environment(Library.self) private var library
    let item: SVGItem

    private func act(_ f: () -> Void) {
        if !library.selection.contains(item.id) { library.focus(item.id) }
        f()
    }

    var body: some View {
        Menu("Set Rating") {
            ForEach(0...5, id: \.self) { r in
                Button(r == 0 ? "None" : String(repeating: "★", count: r)) { act { library.setRating(r) } }
            }
        }
        Menu("Set Flag") {
            Button("Picked") { act { library.setFlag(.picked) } }
            Button("Rejected") { act { library.setFlag(.rejected) } }
            Button("Unflagged") { act { library.setFlag(.none) } }
        }
        Menu("Set Color Label") {
            ForEach(ColorLabel.allCases.dropFirst(), id: \.self) { l in
                Button(l.title) { act { library.toggleLabel(l) } }
            }
        }
        Divider()
        if item.missing {
            Button("Locate…") { library.locatePanel(item) }
            Button("Remove from Catalog") { act { library.removeMissingFromCatalog(library.targetIDs) } }
        } else {
            Button("Reveal in Finder") { act { library.reveal(library.targetItems) } }
            Button("Open in Default App") { act { library.openInDefaultApp(library.targetItems) } }
            OpenWithMenu(url: item.url)
            Divider()
            Button("Move to Trash…") { act { library.requestTrash(library.targetIDs) } }
        }
    }
}

struct OpenWithMenu: View {
    let url: URL

    var body: some View {
        Menu("Open With") {
            ForEach(NSWorkspace.shared.urlsForApplications(toOpen: url), id: \.self) { app in
                Button(FileManager.default.displayName(atPath: app.path)) {
                    NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
                }
            }
        }
    }
}
