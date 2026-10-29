import SwiftUI
import SVGroomCore

struct InspectorView: View {
    @Environment(Library.self) private var library

    var body: some View {
        let targets = library.targetItems
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if targets.count > 1 {
                    MultiInspector(items: targets)
                } else if let item = library.focused {
                    ItemInspector(item: item)
                } else {
                    ContentUnavailableView("Nothing Selected", systemImage: "square.dashed")
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct Section<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content
        }
    }
}

private struct Row: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).multilineTextAlignment(.trailing).monospacedDigit().textSelection(.enabled)
        }
        .font(.callout)
    }
}

/// Rating, flag and label controls; act on the current selection.
private struct MetadataEditor: View {
    @Environment(Library.self) private var library
    let items: [SVGItem]

    private func common<T: Equatable>(_ k: (SVGItem) -> T) -> T? {
        guard let first = items.first.map(k) else { return nil }
        return items.allSatisfy { k($0) == first } ? first : nil
    }

    var body: some View {
        let flag = common(\.flag)
        let label = common(\.label)
        VStack(alignment: .leading, spacing: 10) {
            StarsEditor(rating: common(\.rating)) { library.setRating($0) }
            HStack(spacing: 14) {
                Button { library.setFlag(flag == .picked ? .none : .picked) } label: {
                    Label("Pick", systemImage: flag == .picked ? "flag.fill" : "flag")
                }
                .help("Picked (P)")
                Button { library.setFlag(flag == .rejected ? .none : .rejected) } label: {
                    Label("Reject", systemImage: flag == .rejected ? "xmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(flag == .rejected ? .red : .primary)
                }
                .help("Rejected (X)")
            }
            .buttonStyle(.borderless)
            HStack(spacing: 8) {
                ForEach(ColorLabel.allCases.dropFirst(), id: \.self) { l in
                    Button { library.toggleLabel(l) } label: {
                        Circle().fill(l.color).frame(width: 16, height: 16)
                            .overlay(Circle().strokeBorder(.primary, lineWidth: label == l ? 2 : 0))
                    }
                    .buttonStyle(.plain)
                    .help(l.key.map { "\(l.title) (\($0))" } ?? l.title)
                }
            }
        }
    }
}

private struct ItemInspector: View {
    @Environment(Library.self) private var library
    let item: SVGItem
    private let plot = PlotSettingsStorage()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name).font(.headline).textSelection(.enabled)
            Button { library.reveal([item]) } label: {
                Text(item.folder).font(.caption).lineLimit(2).truncationMode(.middle).multilineTextAlignment(.leading)
            }
            .buttonStyle(.link)
            .disabled(item.missing)
            .help("Reveal in Finder")
        }

        if item.missing {
            VStack(alignment: .leading, spacing: 8) {
                Label("File not found at its last known location.", systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                HStack {
                    Button("Locate…") { library.locatePanel(item) }
                    Button("Search Folder…") { library.findMissingPanel() }
                    Button("Remove") { library.removeMissingFromCatalog([item.id]) }
                }
                .controlSize(.small)
            }
        }

        MetadataEditor(items: [item])

        if let a = item.analysis {
            AnalysisSections(analysis: a, item: item)
        } else if item.missing {
            EmptyView()
        } else if library.didFailAnalysis(item) {
            Text("This file could not be read as SVG.").foregroundStyle(.secondary)
        } else if item.dataless && !isQueued {
            VStack(alignment: .leading, spacing: 6) {
                Label("Online-only file", systemImage: "icloud")
                Button("Download & Analyze") { library.analyzeNow(item) }.controlSize(.small)
            }
        } else {
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Analyzing…").foregroundStyle(.secondary) }
        }

        Section(title: "File") {
            Row(label: "Size", value: ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file))
            Row(label: "Modified", value: item.modified.formatted(date: .abbreviated, time: .shortened))
            Row(label: "Catalogued", value: item.added.formatted(date: .abbreviated, time: .omitted))
        }
    }

    /// The focused file is always analysed first, even when online-only.
    private var isQueued: Bool { library.focusedID == item.id && library.analysisPending > 0 }
}

private struct AnalysisSections: View {
    @Environment(Library.self) private var library
    let analysis: SVGAnalysis
    let item: SVGItem
    private let plot = PlotSettingsStorage()

    var body: some View {
        let settings = plot.value
        let totals = analysis.totals { library.isLayerVisible($0, in: analysis) }

        Section(title: "Document") {
            if let w = analysis.widthMM, let h = analysis.heightMM {
                Row(label: "Size", value: "\(Self.mm(w)) × \(Self.mm(h)) mm")
                Row(label: "Format", value: analysis.format?.label ?? "—")
            } else {
                Row(label: "Size", value: "Unknown (no width/height)")
            }
        }

        Section(title: "Plot Estimate") {
            Text(PlotSettings.format(seconds: settings.seconds(totals)))
                .font(.system(size: 26, weight: .semibold, design: .rounded))
            Row(label: "Pen down", value: Self.distance(totals.drawMM))
            Row(label: "Pen up", value: Self.distance(totals.travelMM))
            Row(label: "Pen lifts", value: totals.strokes.formatted())
            Row(label: "Elements", value: totals.elements.formatted())
            if let b = totals.bounds {
                Row(label: "Drawing extent", value: "\(Self.mm(b.width)) × \(Self.mm(b.height)) mm")
                if let w = analysis.widthMM, let h = analysis.heightMM {
                    Row(label: "Margins L T R B",
                        value: [b.minX, b.minY, w - b.maxX, h - b.maxY].map { Self.mm($0) }.joined(separator: "  "))
                }
            }
            warnings(totals)
        }

        if !analysis.layers.isEmpty {
            Section(title: "Layers") {
                ForEach(Array(analysis.layers.enumerated()), id: \.offset) { i, layer in
                    LayerRow(layer: layer, visible: library.isLayerVisible(i, in: analysis),
                             time: settings.seconds(layer)) { library.setLayer(i, visible: $0, in: analysis) }
                }
                if analysis.unlayered.elements > 0 {
                    Text("+ \(analysis.unlayered.elements) element(s) outside layers")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !library.layerOverrides.isEmpty {
                    Button("Reset to File Visibility") { library.layerOverrides = [:] }.controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder private func warnings(_ totals: LayerStats) -> some View {
        let notes = [
            analysis.exceedsPage(totals) ? "Drawing extends past the page" : nil,
            analysis.textCount > 0 ? "\(analysis.textCount) text element(s) — convert to paths to plot" : nil,
            analysis.imageCount > 0 ? "\(analysis.imageCount) bitmap image(s) — not plottable" : nil,
            analysis.useCount > 0 ? "\(analysis.useCount) <use> clone(s) — not counted" : nil,
        ].compactMap { $0 }
        ForEach(notes, id: \.self) { note in
            Label(note, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    static func mm(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0...1))) }

    static func distance(_ mm: Double) -> String {
        mm >= 1000 ? "\((mm / 1000).formatted(.number.precision(.fractionLength(2)))) m" : "\(Int(mm.rounded())) mm"
    }
}

private struct LayerRow: View {
    let layer: LayerStats
    let visible: Bool
    let time: Double
    let setVisible: (Bool) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button { setVisible(!visible) } label: {
                Image(systemName: visible ? "eye" : "eye.slash")
                    .frame(width: 18)
                    .foregroundStyle(visible ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .help(visible ? "Hide in preview and estimate" : "Show in preview and estimate")

            Circle()
                .fill(layer.color.flatMap { Color(svg: $0) } ?? .clear)
                .overlay(Circle().strokeBorder(.secondary.opacity(0.5), lineWidth: 0.5))
                .frame(width: 10, height: 10)
                .help(layer.color ?? "No stroke colour")

            VStack(alignment: .leading, spacing: 1) {
                Text(layer.name).lineLimit(1).italic(layer.hiddenInFile)
                Text("\(layer.strokes) strokes · \(AnalysisSections.distance(layer.drawMM))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Text(PlotSettings.format(seconds: time)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
        }
        .opacity(visible ? 1 : 0.55)
        .font(.callout)
    }
}

private struct MultiInspector: View {
    @Environment(Library.self) private var library
    let items: [SVGItem]
    private let plot = PlotSettingsStorage()

    var body: some View {
        let analysed = items.compactMap(\.analysis)
        let seconds = analysed.reduce(0) { $0 + plot.value.seconds($1.fileTotals) }
        let draw = analysed.reduce(0) { $0 + $1.fileTotals.drawMM }

        Text("\(items.count) SVGs selected").font(.headline)
        MetadataEditor(items: items)
        Section(title: "Plot Estimate") {
            Text(PlotSettings.format(seconds: seconds))
                .font(.system(size: 26, weight: .semibold, design: .rounded))
            Row(label: "Pen down", value: AnalysisSections.distance(draw))
            if analysed.count < items.count {
                Text("\(items.count - analysed.count) file(s) not analysed yet").font(.caption).foregroundStyle(.secondary)
            }
        }
        Section(title: "Files") {
            Row(label: "Total size", value: ByteCountFormatter.string(fromByteCount: items.reduce(0) { $0 + $1.fileSize }, countStyle: .file))
            Button("Reveal in Finder") { library.reveal(items) }.controlSize(.small)
        }
    }
}
