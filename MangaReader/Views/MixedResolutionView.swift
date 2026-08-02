import SwiftUI

struct MixedResolutionView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let item: LibraryItem

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "questionmark.folder")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text(item.title)
                    .font(.title2)
                    .multilineTextAlignment(.center)
                Text("This folder contains both page images and child folders or archives.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    resolve(.split)
                } label: {
                    Label("Images become a book, children stay separate", systemImage: "square.stack")
                }
                Button {
                    resolve(.merge)
                } label: {
                    Label("Merge everything into one book", systemImage: "rectangle.stack.badge.plus")
                }
                Button {
                    resolve(.skip)
                } label: {
                    Label("Skip for now", systemImage: "eye.slash")
                }
            }
            .padding()
            .navigationTitle("Resolve Folder")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func resolve(_ resolution: MixedResolution) {
        Task {
            do {
                try await model.scanner.resolveMixed(item, resolution: resolution)
                await model.scanLibrary()
                dismiss()
            } catch {
                model.errorMessage = error.localizedDescription
                dismiss()
            }
        }
    }
}
