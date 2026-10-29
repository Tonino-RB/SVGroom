import SwiftUI
import SVGroomCore

/// Centre area: filter bar, then the grid or the loupe. Owns the Lightroom-style keyboard shortcuts.
struct BrowserView: View {
    @Environment(Library.self) private var library
    @AppStorage("thumbSize") private var thumbSize = 190.0
    @FocusState private var keyFocus: Bool

    var body: some View {
        @Bindable var library = library
        VStack(spacing: 0) {
            FilterBar()
            Divider()
            Group {
                if library.viewMode == .grid {
                    GridView(thumbSize: thumbSize) { keyFocus = true }
                } else {
                    LoupeView()
                }
            }
            .focusable()
            .focusEffectDisabled()
            .focused($keyFocus)
            .onKeyPress(phases: [.down, .repeat], action: handleKey)
            .onAppear { keyFocus = true }
            .onChange(of: library.viewMode) { keyFocus = true }
        }
        .toolbar {
            ToolbarItemGroup {
                Picker("View", selection: $library.viewMode) {
                    Label("Grid", systemImage: "square.grid.2x2").tag(ViewMode.grid)
                    Label("Loupe", systemImage: "rectangle").tag(ViewMode.loupe)
                }
                .pickerStyle(.segmented)
                .help("Grid (G) · Loupe (E or Space)")

                if library.viewMode == .grid {
                    Slider(value: $thumbSize, in: 110...440)
                        .frame(width: 110)
                        .help("Thumbnail size")
                }

                Menu {
                    Picker("Sort By", selection: $library.sort) {
                        ForEach(SortKey.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Toggle("Ascending", isOn: $library.sortAscending)
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .help("Sort by \(library.sort.rawValue)")
            }
        }
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        if press.modifiers.contains(.command) {
            if press.characters == "a" { library.selectAll(); return .handled }
            return .ignored
        }
        let rowStep = library.viewMode == .grid ? library.gridColumns : 1
        // Holding an arrow keeps sliding; other keys act once per press.
        let arrows: [KeyEquivalent] = [.leftArrow, .rightArrow, .upArrow, .downArrow]
        if press.phase == .repeat && !arrows.contains(press.key) { return .ignored }
        switch press.key {
        case .leftArrow: library.moveFocus(by: -1); return .handled
        case .rightArrow: library.moveFocus(by: 1); return .handled
        case .upArrow: library.moveFocus(by: -rowStep); return .handled
        case .downArrow: library.moveFocus(by: rowStep); return .handled
        case .space, .return:
            library.viewMode = library.viewMode == .grid ? .loupe : .grid
            return .handled
        case .escape:
            library.viewMode = .grid
            return .handled
        case .delete, .deleteForward:
            library.requestTrash(library.targetIDs)
            return .handled
        default:
            break
        }
        switch press.characters.lowercased() {
        case let c where c.count == 1 && "012345".contains(c):
            library.setRating(Int(c)!, advance: true)
        case "6": library.toggleLabel(.red, advance: true)
        case "7": library.toggleLabel(.yellow, advance: true)
        case "8": library.toggleLabel(.green, advance: true)
        case "9": library.toggleLabel(.blue, advance: true)
        case "p": library.setFlag(.picked, advance: true)
        case "x": library.setFlag(.rejected, advance: true)
        case "u": library.setFlag(.none, advance: true)
        case "g": library.viewMode = .grid
        case "e": library.viewMode = .loupe
        case "z":
            library.viewMode = .loupe
            library.loupeZoom = library.loupeZoom > 1 ? 1 : 4
        default:
            return .ignored
        }
        return .handled
    }
}

private struct FilterBar: View {
    @Environment(Library.self) private var library

    var body: some View {
        @Bindable var library = library
        HStack(spacing: 10) {
            // Scrolls sideways instead of widening the window when space is tight.
            ScrollView(.horizontal, showsIndicators: false) {
                controls
            }
            if library.analysisPending > 0 {
                ProgressView().controlSize(.mini)
                Text("Analyzing \(library.analysisPending)…").foregroundStyle(.secondary).fixedSize()
            }
            Text("\(library.displayed.count) SVG\(library.displayed.count == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .fixedSize()
        }
        .controlSize(.small)
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var controls: some View {
        @Bindable var library = library
        return HStack(spacing: 10) {
            TextField("Search names", text: $library.filter.text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)

            FilterMenu(title: library.filter.minRating == 0 ? "Any Rating" : "≥ " + String(repeating: "★", count: library.filter.minRating)) {
                Picker("Rating", selection: $library.filter.minRating) {
                    Text("Any Rating").tag(0)
                    ForEach(1...5, id: \.self) { Text("≥ " + String(repeating: "★", count: $0)).tag($0) }
                }
            }

            FilterMenu(title: library.filter.flag == .all ? "Any Flag" : library.filter.flag.rawValue) {
                Picker("Flag", selection: $library.filter.flag) {
                    ForEach(FlagFilter.allCases, id: \.self) { Text($0 == .all ? "Any Flag" : $0.rawValue).tag($0) }
                }
            }

            HStack(spacing: 5) {
                ForEach(ColorLabel.allCases.dropFirst(), id: \.self) { l in
                    Button {
                        library.filter.label = library.filter.label == l ? nil : l
                    } label: {
                        Circle()
                            .fill(l.color)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().strokeBorder(.primary, lineWidth: library.filter.label == l ? 2 : 0))
                    }
                    .buttonStyle(.plain)
                    .help("Only \(l.title.lowercased()) label")
                }
            }

            FilterMenu(title: library.filter.format ?? "Any Format") {
                Picker("Format", selection: $library.filter.format) {
                    Text("Any Format").tag(String?.none)
                    ForEach(library.availableFormats, id: \.self) { Text($0).tag(String?.some($0)) }
                }
            }

            if case .folder = library.source {
                Toggle("Subfolders", isOn: $library.includeSubfolders)
                    .toggleStyle(.checkbox)
            }

            if library.filter.isActive {
                Button("Clear") { library.filter = Filter() }
            }
        }
        .padding(.vertical, 1)
    }
}

/// Compact pull-down whose label always shows the current choice.
private struct FilterMenu<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        Menu {
            content.pickerStyle(.inline).labelsHidden()
        } label: {
            Text(title)
        }
        .fixedSize()
    }
}
