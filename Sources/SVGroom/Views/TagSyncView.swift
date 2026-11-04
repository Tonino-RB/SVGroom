import SwiftUI

/// Review before syncing tags across linked folders: untagged files are filled in, and for each
/// file tagged differently in different folders, pick the version to copy or leave it untouched.
struct TagSyncView: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    let review: TagSyncReview
    /// Per conflict, the version whose tags the others get (nil: don't touch).
    @State private var choices: [Int?]

    init(review: TagSyncReview) {
        self.review = review
        _choices = State(initialValue: Array(repeating: nil, count: review.conflicts.count))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sync Tags").font(.title2.bold())
            Text(review.folders.map { ($0 as NSString).lastPathComponent }.joined(separator: " · "))
                .foregroundStyle(.secondary)

            if !review.copies.isEmpty {
                Label(review.copies.count == 1 ? "1 file without tags gets the tags of its linked versions."
                      : "\(review.copies.count) files without tags get the tags of their linked versions.",
                      systemImage: "arrow.right.doc.on.clipboard")
            }

            if !review.conflicts.isEmpty {
                Label(review.conflicts.count == 1 ? "1 file is tagged differently in the linked folders."
                      : "\(review.conflicts.count) files are tagged differently in the linked folders.",
                      systemImage: "exclamationmark.triangle")
                batchButtons
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(review.conflicts.indices, id: \.self) { i in
                            conflictRow(i)
                            Divider()
                        }
                    }
                }
            } else {
                Spacer(minLength: 0)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Apply") { library.applyTagSync(review, choices: choices) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 640, idealWidth: 860, minHeight: review.conflicts.isEmpty ? 0 : 520, idealHeight: 680)
    }

    /// Same choice for every conflict: a folder's version where it has tags, otherwise untouched.
    private var batchButtons: some View {
        HStack {
            Text("For all:").foregroundStyle(.secondary)
            ForEach(review.folders, id: \.self) { folder in
                Button("Use “\((folder as NSString).lastPathComponent)”") {
                    choices = review.conflicts.map { versions in
                        versions.firstIndex { $0.folder == folder && $0.item?.tags != nil }
                    }
                }
            }
            Button("Don’t Touch") { choices = choices.map { _ in nil } }
        }
    }

    private func conflictRow(_ i: Int) -> some View {
        let versions = review.conflicts[i]
        return VStack(alignment: .leading, spacing: 6) {
            Text(relativePath(versions[0])).font(.headline).lineLimit(1).truncationMode(.middle)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(versions.indices, id: \.self) { v in
                        VersionCard(version: versions[v], selected: choices[i] == v)
                            .onTapGesture { if versions[v].item?.tags != nil { choices[i] = v } }
                    }
                    Button { choices[i] = nil } label: {
                        Label("Don’t Touch", systemImage: choices[i] == nil ? "checkmark.circle.fill" : "circle")
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 60)
                }
            }
        }
    }

    private func relativePath(_ version: LinkedVersion) -> String {
        String(version.item?.path.dropFirst(version.folder.count + 1) ?? "")
    }
}

/// One version in a conflict: preview, folder and tags. Clicking a tagged one copies its tags to the others.
private struct VersionCard: View {
    let version: LinkedVersion
    let selected: Bool
    @State private var thumb: NSImage?

    private let size = 170.0

    var body: some View {
        let item = version.item
        VStack(alignment: .leading, spacing: 5) {
            ZStack {
                if let thumb {
                    Image(nsImage: thumb)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .background(.white)
                        .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                } else if item?.missing ?? true {
                    Image(systemName: "questionmark.square.dashed").font(.system(size: 30)).foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: size, height: size * 0.82)
            Text((version.folder as NSString).lastPathComponent).font(.caption.bold()).lineLimit(1)
            if let item, !item.keywords.isEmpty {
                Text(item.keywords.sorted().joined(separator: ", ")).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(spacing: 5) {
                if let item, item.tags != nil {
                    StarsView(rating: item.rating)
                    LabelDot(label: item.label)
                    SizeBadge(size: item.sizeTag)
                    Spacer(minLength: 0)
                    FlagIcon(flag: item.flag).font(.caption)
                } else {
                    Text("No tags").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(selected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .help(item?.path ?? version.folder)
        .task(id: item?.path) {
            guard let item, !item.missing, !item.dataless else { return }
            thumb = await Thumbnailer.shared.image(for: item.url, modified: item.modified,
                                                   pixels: Thumbnailer.pixelSize(for: size))
        }
    }
}
