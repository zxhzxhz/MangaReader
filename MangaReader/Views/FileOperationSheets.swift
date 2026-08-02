import SwiftUI

struct RenameSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let item: LibraryItem
    @State private var name: String

    init(item: LibraryItem) {
        self.item = item
        _name = State(initialValue: item.title)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.never)
            }
            .navigationTitle("Rename")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            do {
                                try await model.fileOperations.rename(item, to: name)
                                await model.scanLibrary()
                                dismiss()
                            } catch {
                                model.errorMessage = error.localizedDescription
                                dismiss()
                            }
                        }
                    }
                }
            }
        }
    }
}

enum DestinationOperation {
    case move
    case copy
}

struct DestinationPickerSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let item: LibraryItem
    let operation: DestinationOperation
    @State private var parents: [LibraryItem] = []

    var body: some View {
        NavigationStack {
            List {
                Button("Root") {
                    perform(parent: nil)
                }
                ForEach(parents) { parent in
                    Button(parent.title) {
                        perform(parent: parent)
                    }
                }
            }
            .navigationTitle(operation == .move ? "Move To" : "Copy To")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                parents = model.items.filter {
                    $0.kind == .collection &&
                        $0.relativePath != item.relativePath &&
                        !$0.relativePath.hasPrefix(item.relativePath + "/")
                }
            }
        }
    }

    private func perform(parent: LibraryItem?) {
        Task {
            do {
                if operation == .move {
                    try await model.fileOperations.move(item, toFolder: parent)
                } else {
                    _ = try await model.fileOperations.copy(item, toFolder: parent)
                }
                await model.scanLibrary()
                dismiss()
            } catch {
                model.errorMessage = error.localizedDescription
                dismiss()
            }
        }
    }
}
