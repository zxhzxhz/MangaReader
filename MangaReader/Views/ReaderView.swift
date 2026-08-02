import SwiftUI
import UIKit

struct ReaderView: View {
    @EnvironmentObject private var model: AppModel
    let item: LibraryItem

    @State private var pages: [PageReference] = []
    @State private var currentPage = 0
    @State private var enhance = true
    @State private var rtl = false
    @State private var loadError: String?
    @State private var profile: ModelProfile?

    var body: some View {
        Group {
            if pages.isEmpty {
                if let loadError {
                    ContentUnavailableView("Unable to Open", systemImage: "exclamationmark.triangle", description: Text(loadError))
                } else {
                    ProgressView()
                }
            } else {
                TabView(selection: $currentPage) {
                    ForEach(Array(orderedPages.enumerated()), id: \.element.id) { index, page in
                        ReaderPageView(item: item, page: page, enhance: enhance, profile: profile)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    enhance.toggle()
                } label: {
                    Label(enhance ? "Enhance On" : "Enhance Off", systemImage: enhance ? "wand.and.stars" : "wand.and.stars.slash")
                }
                Button {
                    rtl.toggle()
                } label: {
                    Label(rtl ? "Right to Left" : "Left to Right", systemImage: "arrow.right.to.line")
                }
            }
        }
        .task {
            profile = model.globalProfile()
            enhance = profile != nil
            do {
                pages = try await model.pageSource.pageReferences(for: item)
                currentPage = min(max(0, item.progressPage), max(0, pages.count - 1))
            } catch {
                loadError = error.localizedDescription
            }
        }
        .onChange(of: currentPage) { _, newValue in
            let realIndex = rtl ? pages.count - 1 - newValue : newValue
            var updated = item
            updated.progressPage = realIndex
            updated.updatedAt = Date()
            try? model.db.save(updated)
        }
    }

    private var orderedPages: [PageReference] {
        rtl ? pages.reversed().map { $0 } : pages
    }
}

private struct ReaderPageView: View {
    @EnvironmentObject private var model: AppModel
    let item: LibraryItem
    let page: PageReference
    let enhance: Bool
    let profile: ModelProfile?

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image {
                ZoomableImageView(image: image)
            } else if failed {
                ContentUnavailableView("Page Failed", systemImage: "photo.badge.exclamationmark")
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .task(id: "\(page.id)-\(enhance)-\(profile?.profileHash ?? "none")") {
            await load()
        }
    }

    private func load() async {
        failed = false
        image = nil
        let key = CacheKey.make([page.id, profile?.profileHash ?? "none"])
        if enhance, let profile {
            if let cached = await CacheManager.shared.data(kind: .enhanced, bookID: item.id, key: key, ext: "jpg"),
               let cachedImage = UIImage(data: cached) {
                image = cachedImage
                return
            }
        }
        guard let base = try? await model.pageSource.image(for: item, page: page, maxDimension: 4096) else {
            failed = true
            return
        }
        if enhance, let profile {
            do {
                let enhanced = try await model.upscaleService.enhance(image: base, profile: profile)
                image = enhanced
                if let data = enhanced.jpegData(compressionQuality: 0.92) {
                    try? await CacheManager.shared.store(data, kind: .enhanced, bookID: item.id, key: key, ext: "jpg")
                }
            } catch {
                image = base
            }
        } else {
            image = base
        }
    }
}
