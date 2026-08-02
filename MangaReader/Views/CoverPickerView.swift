import SwiftUI
import UIKit

struct CoverPickerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let item: LibraryItem

    @State private var pages: [PageReference] = []
    @State private var visibleLimit = 500
    @State private var selectedImage: UIImage?
    @State private var showCrop = false

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(pages.prefix(visibleLimit)) { page in
                        Button {
                            Task {
                                selectedImage = try? await model.pageSource.image(
                                    for: item,
                                    page: page,
                                    maxDimension: 1600
                                )
                                showCrop = selectedImage != nil
                            }
                        } label: {
                            ThumbnailCell(item: item, page: page)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()

                if visibleLimit < pages.count {
                    Button("Load More") {
                        visibleLimit += 500
                    }
                    .padding()
                }
            }
            .navigationTitle("Choose Cover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                pages = (try? await model.pageSource.pageReferences(for: item)) ?? []
            }
            .sheet(isPresented: $showCrop) {
                if let selectedImage {
                    CropViewControllerWrapper(
                        image: selectedImage,
                        onCancel: { showCrop = false },
                        onCrop: { image in
                            Task {
                                do {
                                    try await model.coverService.setCustomCover(for: item, image: image)
                                    await model.scanLibrary()
                                    dismiss()
                                } catch {
                                    model.errorMessage = error.localizedDescription
                                    dismiss()
                                }
                            }
                        }
                    )
                    .ignoresSafeArea()
                }
            }
        }
    }
}

private struct ThumbnailCell: View {
    @EnvironmentObject private var model: AppModel
    let item: LibraryItem
    let page: PageReference

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.secondarySystemBackground))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ProgressView()
            }
        }
        .aspectRatio(2 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: page.id) {
            if image == nil {
                image = try? await model.pageSource.image(for: item, page: page, maxDimension: 256)
            }
        }
    }
}
