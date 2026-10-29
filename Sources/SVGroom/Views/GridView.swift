import SwiftUI
import SVGroomCore

struct GridView: View {
    @Environment(Library.self) private var library
    let thumbSize: Double
    let onClick: () -> Void

    private let spacing = 12.0

    var body: some View {
        GeometryReader { geo in
            let columns = max(1, Int((geo.size.width - 2 * spacing + spacing) / (thumbSize + spacing)))
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns), spacing: spacing) {
                        ForEach(library.displayed) { item in
                            GridCell(item: item, size: thumbSize,
                                     selected: library.selection.contains(item.id),
                                     focused: library.focusedID == item.id)
                                .id(item.id)
                                .onTapGesture(count: 2) {
                                    library.focus(item.id)
                                    library.viewMode = .loupe
                                }
                                .simultaneousGesture(TapGesture().onEnded {
                                    library.click(item.id, modifiers: NSEvent.modifierFlags)
                                    onClick()
                                })
                                .contextMenu { ItemContextMenu(item: item) }
                        }
                    }
                    .padding(spacing)
                }
                .onChange(of: library.focusedID) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
                .onAppear {
                    if let id = library.focusedID { proxy.scrollTo(id, anchor: .center) }
                }
            }
            .onAppear { library.gridColumns = columns }
            .onChange(of: columns) { _, c in library.gridColumns = c }
        }
        .overlay {
            if library.displayed.isEmpty {
                if library.items.isEmpty {
                    ContentUnavailableView {
                        Label("No SVGs Yet", systemImage: "folder.badge.plus")
                    } description: {
                        Text("Add a folder: its SVG files and all its subfolders are catalogued.")
                    } actions: {
                        Button("Add Folder…") { library.addFolderPanel() }
                    }
                } else {
                    ContentUnavailableView("No Matching SVGs", systemImage: "line.3.horizontal.decrease.circle",
                                           description: Text("Try another folder or clear the filters."))
                }
            }
        }
    }
}

private struct GridCell: View {
    let item: SVGItem
    let size: Double
    let selected: Bool
    let focused: Bool
    private let plot = PlotSettingsStorage()
    @State private var thumb: NSImage?
    @State private var thumbLoaded = false

    private struct ThumbKey: Equatable {
        let path: String
        let modified: Date
        let pixels: Int
        let loadable: Bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack {
                if let thumb {
                    Image(nsImage: thumb)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .background(.white)
                        .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                } else if item.missing {
                    Image(systemName: "questionmark.square.dashed").font(.system(size: 34)).foregroundStyle(.secondary)
                } else if item.dataless {
                    Image(systemName: "icloud.and.arrow.down").font(.system(size: 30)).foregroundStyle(.secondary)
                        .help("Online-only file: not downloaded")
                } else if thumbLoaded {
                    Image(systemName: "doc.questionmark").font(.system(size: 30)).foregroundStyle(.secondary)
                        .help("No preview available")
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: size * 0.82)
            .overlay(alignment: .topTrailing) {
                if item.missing {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                        .help("File not found: \(item.path)")
                }
            }

            Text(item.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 5) {
                StarsView(rating: item.rating)
                LabelDot(label: item.label)
                Spacer(minLength: 0)
                FlagIcon(flag: item.flag).font(.caption)
            }

            HStack {
                Text(item.analysis?.format?.label ?? " ")
                Spacer(minLength: 4)
                if let a = item.analysis {
                    Text(PlotSettings.format(seconds: plot.value.seconds(a.fileTotals)))
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(selected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(focused ? Color.accentColor : .clear, lineWidth: 2))
        .opacity(item.flag == .rejected ? 0.4 : 1)
        .contentShape(Rectangle())
        .task(id: ThumbKey(path: item.path, modified: item.modified,
                           pixels: Thumbnailer.pixelSize(for: size), loadable: !item.missing && !item.dataless)) {
            guard !item.missing, !item.dataless else { thumb = nil; return }
            thumb = await Thumbnailer.shared.image(for: item.url, modified: item.modified,
                                                   pixels: Thumbnailer.pixelSize(for: size))
            thumbLoaded = true
        }
    }
}
