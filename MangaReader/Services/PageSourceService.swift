import Foundation
import UIKit

struct PageReference: Identifiable, Equatable, Sendable {
    let path: String

    var id: String {
        path
    }
}

actor PageSourceService {
    let db: AppDatabase
    let archiveService = ArchiveService()

    init(db: AppDatabase) {
        self.db = db
    }

    func pageReferences(for item: LibraryItem) async throws -> [PageReference] {
        if item.isVirtual {
            guard let parent = item.virtualParentURL else {
                return []
            }
            return FolderScanner.directImages(in: parent).map {
                PageReference(path: $0.lastPathComponent)
            }
        }

        if item.kind == .archive {
            if let cached = await cachedIndex(for: item) {
                return cached
            }
            let pages = try await archiveService.listPages(for: item)
            let references = pages.map { PageReference(path: $0.path) }
            if let encoded = try? JSONEncoder().encode(references) {
                try? await CacheManager.shared.store(
                    encoded,
                    kind: .index,
                    bookID: item.id,
                    key: item.fingerprint,
                    ext: "json"
                )
            }
            return references
        }

        if item.kind == .bookFolder, item.mixedResolution == .merge {
            return try await mergedPageReferences(for: item)
        }

        guard let url = item.url else {
            return []
        }
        return FolderScanner.pages(at: url).map { PageReference(path: $0.path) }
    }

    func image(for item: LibraryItem, page: PageReference, maxDimension: CGFloat? = nil) async throws -> UIImage {
        let data = try await pageData(for: item, page: page)
        guard let image = ImageService.decode(data) else {
            throw PageSourceError.cannotDecode(page.path)
        }
        if let maxDimension {
            let longest = max(image.size.width, image.size.height)
            if longest > maxDimension {
                let scale = maxDimension / longest
                let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                let format = UIGraphicsImageRendererFormat.default()
                format.scale = 1
                let renderer = UIGraphicsImageRenderer(size: target, format: format)
                return renderer.image { _ in
                    image.draw(in: CGRect(origin: .zero, size: target))
                }
            }
        }
        return image
    }

    func pageData(for item: LibraryItem, page: PageReference) async throws -> Data {
        if item.isVirtual {
            guard let parent = item.virtualParentURL else {
                throw PageSourceError.missingFile(page.path)
            }
            let url = parent.appendingPathComponent(page.path)
            guard let data = try? Data(contentsOf: url) else {
                throw PageSourceError.missingFile(page.path)
            }
            return data
        }

        if item.kind == .archive {
            let archivePage = ArchivePage(path: page.path, size: 0, nestedDepth: 0)
            return try await archiveService.pageData(for: archivePage, in: item)
        }

        if item.kind == .bookFolder, item.mixedResolution == .merge, page.path.contains("|") {
            guard let url = item.url else {
                throw PageSourceError.missingFile(page.path)
            }
            let parts = page.path.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            let archiveURL = url.appendingPathComponent(parts[0])
            var synthetic = LibraryItem.new(
                relativePath: FolderScanner.relativePath(of: archiveURL, from: AppPaths.libraryRoot),
                fingerprint: "",
                title: archiveURL.lastPathComponent,
                kind: .archive
            )
            let archiveRelative = FolderScanner.relativePath(of: archiveURL, from: AppPaths.libraryRoot)
            if let child = try? db.item(byRelativePath: archiveRelative) {
                synthetic.id = child.id
            } else {
                synthetic.id = item.id
            }
            let innerPath = parts.dropFirst().joined(separator: "|")
            let archivePage = ArchivePage(path: innerPath, size: 0, nestedDepth: 0)
            return try await archiveService.pageData(for: archivePage, in: synthetic)
        }

        guard let url = item.url else {
            throw PageSourceError.missingFile(page.path)
        }
        let fileURL = url.appendingPathComponent(page.path)
        guard let data = try? Data(contentsOf: fileURL) else {
            throw PageSourceError.missingFile(page.path)
        }
        return data
    }

    private func mergedPageReferences(for item: LibraryItem) async throws -> [PageReference] {
        guard let url = item.url else {
            return []
        }
        var references = FolderScanner.pages(at: url).map { PageReference(path: $0.path) }
        for archiveURL in FolderScanner.archives(in: url) {
            let relativeFromBook = FolderScanner.relativePath(of: archiveURL, from: url)
            let relativeFromLibrary = FolderScanner.relativePath(of: archiveURL, from: AppPaths.libraryRoot)
            guard let childItem = try? db.item(byRelativePath: relativeFromLibrary) else {
                continue
            }
            let pages = try await archiveService.listPages(for: childItem)
            references.append(contentsOf: pages.map {
                PageReference(path: "\(relativeFromBook)|\($0.path)")
            })
        }
        return NaturalSort.sorted(references) { $0.path }
    }

    private func cachedIndex(for item: LibraryItem) async -> [PageReference]? {
        guard let data = await CacheManager.shared.data(
            kind: .index,
            bookID: item.id,
            key: item.fingerprint,
            ext: "json"
        ) else {
            return nil
        }
        return try? JSONDecoder().decode([PageReference].self, from: data)
    }
}

enum PageSourceError: LocalizedError {
    case cannotDecode(String)
    case missingFile(String)

    var errorDescription: String? {
        switch self {
        case .cannotDecode(let path):
            return "Unable to decode page: \(path)"
        case .missingFile(let path):
            return "Page file is missing: \(path)"
        }
    }
}
