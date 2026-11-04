import SwiftUI

/// Add, rename, reorder and delete the custom tags.
struct TagManagerView: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var newTag = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tags").font(.title2.bold())
            Text("Rename a tag by editing its name. Deleting a tag removes it from every file.")
                .foregroundStyle(.secondary)
            List {
                ForEach(library.keywordList, id: \.self) { k in
                    TagRow(name: k, count: library.keywordCount(k))
                }
                .onMove { library.moveKeywords(from: $0, to: $1) }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .overlay {
                if library.keywordList.isEmpty { Text("No tags yet").foregroundStyle(.secondary) }
            }
            HStack {
                TextField("New tag", text: $newTag).onSubmit(add)
                Button("Add", action: add).disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420, height: 440)
    }

    private func add() {
        library.addKeyword(newTag)
        newTag = ""
    }
}

private struct TagRow: View {
    @Environment(Library.self) private var library
    let name: String
    let count: Int
    @State private var text = ""

    var body: some View {
        HStack {
            TextField("Name", text: $text)
                .textFieldStyle(.plain)
                .onSubmit { library.renameKeyword(name, to: text) }
            Text(count == 1 ? "1 file" : "\(count) files").foregroundStyle(.secondary).monospacedDigit()
            Button { library.deleteKeyword(name) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Delete “\(name)” from the list and from every file")
        }
        .onAppear { text = name }
        .onChange(of: name) { text = name }
    }
}
