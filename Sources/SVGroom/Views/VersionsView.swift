import SVGroomCore
import SwiftUI

/// Versions mode: the focused file next to the files at the same place in its linked folders,
/// all at the same mm scale, optionally through the simulation settings.
struct VersionsView: View {
    @Environment(Library.self) private var library

    var body: some View {
        if let item = library.focused {
            let versions = library.versions(of: item)
            Group {
                if versions.isEmpty {
                    ContentUnavailableView("Not in a Linked Folder", systemImage: "link",
                                           description: Text("Right-click a folder › Link With… to compare its files with the same files in other folders."))
                } else {
                    sheets(versions, focused: item)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) { LoupeControls(item: item) }
        } else {
            ContentUnavailableView("No SVG Selected", systemImage: "square.dashed")
        }
    }

    @ViewBuilder
    private func sheets(_ versions: [LinkedVersion], focused: SVGItem) -> some View {
        let settings = library.versionsSimulated ? library.simulation : nil
        let sheets = versions.map { sheet(for: $0.item, settings: settings) }
        // Same mm scale everywhere, so sizes and line weights compare.
        let fit = sheets.compactMap { $0?.size }.reduce(CGSize.zero) {
            CGSize(width: max($0.width, $1.width), height: max($0.height, $1.height))
        }
        let columns = versions.count <= 3 ? versions.count : Int(Double(versions.count).squareRoot().rounded(.up))
        VStack(spacing: 0) {
            ForEach(Array(stride(from: 0, to: versions.count, by: columns)), id: \.self) { start in
                if start > 0 { Divider() }
                HStack(spacing: 0) {
                    ForEach(start..<min(start + columns, versions.count), id: \.self) { i in
                        if i > start { Divider() }
                        pane(versions[i], sheet: sheets[i], fit: fit, settings: settings, isFocused: versions[i].item?.id == focused.id)
                            .overlay {
                                if let id = versions[i].item?.id, id == library.selectedVersionID {
                                    Rectangle().strokeBorder(Color.accentColor, lineWidth: 3).allowsHitTesting(false)
                                }
                            }
                    }
                    // Keeps the last row's panes the same width as the others.
                    ForEach(0..<(start + columns - min(start + columns, versions.count)), id: \.self) { _ in
                        Divider()
                        Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
    }

    private struct Sheet {
        let size: CGSize
        let layout: SimulationLayout?
    }

    /// The sheet a version is shown on: its page, or the simulated sheet.
    private func sheet(for item: SVGItem?, settings: SimulationSettings?) -> Sheet? {
        guard let item, !item.missing, let a = item.analysis, let w = a.widthMM, let h = a.heightMM else { return nil }
        guard let settings else { return Sheet(size: CGSize(width: w, height: h), layout: nil) }
        guard let layout = Simulator.layout(a, settings, visible: { library.isLayerVisible($0, in: a) }) else { return nil }
        return Sheet(size: CGSize(width: layout.canvas.width, height: layout.canvas.height), layout: layout)
    }

    @ViewBuilder
    private func pane(_ version: LinkedVersion, sheet: Sheet?, fit: CGSize, settings: SimulationSettings?, isFocused: Bool) -> some View {
        let selected = version.item.map { $0.id == library.selectedVersionID } ?? false
        let title = (isFocused ? "● " : "") + (version.folder as NSString).lastPathComponent + (selected ? " — selected" : "")
        let overrides = library.layerOverrides
        if let item = version.item, !item.missing, let a = item.analysis, let sheet {
            let url = item.url
            SheetPane(title: title, detail: detail(a, sheet: sheet),
                      warning: sheet.layout.map { $0.fits ? nil : "The drawing goes off the sheet" } ?? nil,
                      sheetMM: sheet.size, fitMM: fit,
                      key: PaneKey(path: item.path, modified: item.modified, overrides: overrides, settings: settings),
                      onClick: { library.selectVersion(item.id) }, dragURLs: { [item.url] }) {
                if let layout = sheet.layout, let settings {
                    await LoupeRenderer.simulate(url, overrides: overrides, layout: layout, settings: settings)
                } else {
                    await LoupeRenderer.load(url, overrides: overrides)
                }
            }
            .help(item.path)
        } else {
            VStack(spacing: 6) {
                Text(title).font(.headline)
                if version.item == nil || version.item?.missing == true {
                    Text("No file at this place").foregroundStyle(.secondary)
                } else if version.item?.analysis == nil {
                    ProgressView("Analyzing…")
                } else {
                    Text("Page size unknown").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .help(version.folder)
        }
    }

    /// Plot figures are for the file as it is, so they are left out of simulated sheets.
    private func detail(_ a: SVGAnalysis, sheet: Sheet) -> String {
        var s = "\(PaperFormat.match(widthMM: sheet.size.width, heightMM: sheet.size.height).label) · \(mm(sheet.size.width)) × \(mm(sheet.size.height)) mm"
        if sheet.layout == nil {
            let t = a.totals { library.isLayerVisible($0, in: a) }
            s += "\n\(PlotSettings.format(seconds: t.seconds)) · pen down \((t.drawMM / 1000).formatted(.number.precision(.fractionLength(1)))) m · \(t.strokes.formatted()) lifts"
        }
        return s
    }
}

private func mm(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0...1))) }
