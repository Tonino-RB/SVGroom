import AppKit
import SVGroomCore
import SwiftUI

/// Simulation and Compare modes: the focused file as it would be plotted on another sheet,
/// at another size, with other pens. The file is never modified.
struct SimulationView: View {
    @Environment(Library.self) private var library

    var body: some View {
        if let item = library.focused {
            SimulationContent(item: item, overrides: library.layerOverrides, settings: library.simulation,
                              compare: library.previewMode == .compare)
                .id(item.id)
        } else {
            ContentUnavailableView("No SVG Selected", systemImage: "square.dashed")
        }
    }
}

private struct SimulationContent: View {
    @Environment(Library.self) private var library
    let item: SVGItem
    let overrides: [Int: Bool]
    let settings: SimulationSettings
    let compare: Bool

    var body: some View {
        Group {
            if item.missing {
                ContentUnavailableView("File not found", systemImage: "questionmark.square.dashed", description: Text(item.path))
            } else if let analysis = item.analysis {
                if let w = analysis.widthMM, let h = analysis.heightMM,
                   let layout = Simulator.layout(analysis, settings, visible: { library.isLayerVisible($0, in: analysis) }) {
                    panes(analysis, original: CGSize(width: w, height: h), layout: layout)
                } else {
                    ContentUnavailableView("Page size unknown", systemImage: "ruler",
                                           description: Text("The file has no width, height or viewBox to simulate from."))
                }
            } else {
                ProgressView("Analyzing…")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) { LoupeControls(item: item) }
    }

    @ViewBuilder
    private func panes(_ analysis: SVGAnalysis, original: CGSize, layout: SimulationLayout) -> some View {
        let simulated = CGSize(width: layout.canvas.width, height: layout.canvas.height)
        // Side by side, both sheets use the same mm scale so their sizes compare.
        let fit = compare ? CGSize(width: max(original.width, simulated.width), height: max(original.height, simulated.height))
                          : simulated
        let url = item.url, overrides = overrides, settings = settings
        HStack(spacing: 0) {
            if compare {
                SheetPane(title: "Original",
                          detail: describe(sheet: original, drawing: analysis.totals { library.isLayerVisible($0, in: analysis) }.bounds),
                          sheetMM: original, fitMM: fit,
                          key: PaneKey(path: item.path, modified: item.modified, overrides: overrides, settings: nil)) {
                    await LoupeRenderer.load(url, overrides: overrides)
                }
                Divider()
            }
            SheetPane(title: "Simulation",
                      detail: describe(sheet: simulated, drawing: layout.drawing),
                      warning: layout.fits ? nil : "The drawing goes off the sheet",
                      sheetMM: simulated, fitMM: fit,
                      key: PaneKey(path: item.path, modified: item.modified, overrides: overrides, settings: settings)) {
                await LoupeRenderer.simulate(url, overrides: overrides, layout: layout, settings: settings)
            }
        }
    }

    private func describe(sheet: CGSize, drawing: MMRect?) -> String {
        var s = "\(PaperFormat.match(widthMM: sheet.width, heightMM: sheet.height).label) · \(mm(sheet.width)) × \(mm(sheet.height)) mm"
        if let d = drawing { s += "\nDrawing \(mm(d.width)) × \(mm(d.height)) mm" }
        return s
    }
}

private func mm(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0...1))) }

struct PaneKey: Equatable {
    let path: String
    let modified: Date
    let overrides: [Int: Bool]
    let settings: SimulationSettings?
}

/// One sheet with its caption. Keeps the last image while a new one renders, so changing a
/// setting doesn't flicker.
struct SheetPane: View {
    @Environment(Library.self) private var library
    let title: String
    let detail: String
    var warning: String?
    let sheetMM: CGSize
    let fitMM: CGSize
    let key: PaneKey
    var onClick: (() -> Void)?
    var dragURLs: (() -> [URL])?
    let load: () async -> NSImage?
    @State private var image: NSImage?
    @State private var loaded = false

    var body: some View {
        @Bindable var library = library
        ZStack {
            PaperView(image: image, zoom: $library.loupeZoom, actualSize: $library.loupeActualSize,
                      sheetMM: sheetMM, fitMM: fitMM, onClick: onClick, dragURLs: dragURLs)
            if !loaded {
                ProgressView()
            } else if image == nil {
                Text("This SVG could not be rendered.").foregroundStyle(.secondary)
            }
        }
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary).monospacedDigit()
                if let warning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding(10)
        }
        .task(id: key) {
            let result = await load()
            guard !Task.isCancelled else { return }
            image = result
            loaded = true
        }
    }
}

/// Sheet, drawing size and pens for the simulation. Lives outside the browser's keyboard
/// shortcuts, so typing numbers here doesn't rate files.
struct SimulationBar: View {
    @Environment(Library.self) private var library

    var body: some View {
        @Bindable var library = library
        let analysis = library.focused?.analysis
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Menu(canvasTitle) {
                    Button("Same as File") { library.simulation.canvas = nil }
                    Divider()
                    ForEach(PaperFormat.all, id: \.name) { f in
                        Button(f.name) { setFormat(f, analysis) }
                    }
                }
                .fixedSize()
                .help("Sheet to plot on")
                if library.simulation.canvas != nil {
                    TextField("Width", value: canvasSide(\.width), format: .number).frame(width: 54)
                    Text("×")
                    TextField("Height", value: canvasSide(\.height), format: .number).frame(width: 54)
                    Text("mm").foregroundStyle(.secondary)
                    Button {
                        if let c = library.simulation.canvas {
                            library.simulation.canvas = SheetSize(width: c.height, height: c.width)
                        }
                    } label: { Image(systemName: "rotate.right") }
                        .help("Portrait / Landscape")
                }

                Divider().frame(height: 16)

                Toggle("Longest side", isOn: Binding(
                    get: { library.simulation.longestSideMM != nil },
                    set: { library.simulation.longestSideMM = $0 ? currentLongestSide(analysis) : nil }))
                    .toggleStyle(.checkbox)
                    .help("Scale the drawing so its longest side has this length, centred on the sheet")
                if library.simulation.longestSideMM != nil {
                    TextField("Length", value: Binding(get: { library.simulation.longestSideMM ?? 0 },
                                                       set: { library.simulation.longestSideMM = max(1, $0) }),
                              format: .number).frame(width: 54)
                    Text("mm").foregroundStyle(.secondary)
                }

                Divider().frame(height: 16)

                Text("Pen width")
                TextField("Pen width", value: $library.simulation.penWidthMM, format: .number).frame(width: 44)
                Stepper("Pen width", value: $library.simulation.penWidthMM, in: 0.05...5, step: 0.05).labelsHidden()
                Text("mm").foregroundStyle(.secondary)

                if let analysis {
                    Divider().frame(height: 16)
                    ForEach(analysis.layers.indices, id: \.self) { i in
                        ColorPicker(analysis.layers[i].name, selection: pen(i, fileColor: analysis.layers[i].color),
                                    supportsOpacity: false)
                            .fixedSize()
                    }
                    if analysis.unlayered.elements > 0 {
                        ColorPicker(analysis.layers.isEmpty ? "Pen" : "Outside layers",
                                    selection: pen(SimulationSettings.unlayered, fileColor: analysis.unlayered.color),
                                    supportsOpacity: false)
                            .fixedSize()
                    }
                    if !library.simulation.penColors.isEmpty {
                        Button("Reset Pens") { library.simulation.penColors = [:] }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .controlSize(.small)
        .font(.callout)
    }

    private var canvasTitle: String {
        guard let c = library.simulation.canvas else { return "Sheet: Same as File" }
        return "Sheet: " + PaperFormat.match(widthMM: c.width, heightMM: c.height).label
    }

    private func canvasSide(_ side: WritableKeyPath<SheetSize, Double>) -> Binding<Double> {
        Binding(get: { library.simulation.canvas?[keyPath: side] ?? 0 },
                set: { library.simulation.canvas?[keyPath: side] = max(1, $0) })
    }

    /// Keeps the orientation of the current sheet, or of the file's page.
    private func setFormat(_ f: PaperFormat, _ analysis: SVGAnalysis?) {
        let landscape = library.simulation.canvas.map { $0.width > $0.height }
            ?? analysis.map { ($0.widthMM ?? 0) > ($0.heightMM ?? 0) } ?? false
        library.simulation.canvas = landscape ? SheetSize(width: f.longMM, height: f.shortMM)
                                              : SheetSize(width: f.shortMM, height: f.longMM)
    }

    private func currentLongestSide(_ analysis: SVGAnalysis?) -> Double {
        guard let analysis, let b = analysis.totals(visible: { library.isLayerVisible($0, in: analysis) }).bounds else { return 200 }
        return max(b.width, b.height).rounded()
    }

    private func pen(_ index: Int, fileColor: String?) -> Binding<Color> {
        Binding(get: { (library.simulation.penColors[index] ?? fileColor).flatMap { Color(svg: $0) } ?? .black },
                set: { library.simulation.penColors[index] = $0.hex })
    }
}

private extension Color {
    var hex: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return String(format: "#%02x%02x%02x", Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
    }
}
