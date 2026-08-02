import Foundation
import UIKit

actor CoverService {
    let db: AppDatabase
    let pageSource: PageSourceService

    init(db: AppDatabase, pageSource: PageSourceService) {
        self.db = db
        self.pageSource = pageSource
    }

    func coverData(for item: LibraryItem) async -> Data? {
        if let coverKey = item.coverKey {
            let url = AppPaths.coverDirectory.appendingPathComponent(coverKey + ".jpg")
            if let data = try? Data(contentsOf: url) {
                return data
            }
        }
        let generatedURL = AppPaths.coverDirectory.appendingPathComponent(
            "generated-\(CacheKey.make([item.fingerprint])).jpg"
        )
        if let data = try? Data(contentsOf: generatedURL) {
            return data
        }
        guard let pages = try? await pageSource.pageReferences(for: item), let first = pages.first else {
            return nil
        }
        guard let image = try? await pageSource.image(for: item, page: first, maxDimension: 1024) else {
            return nil
        }
        guard let data = ImageService.jpegData(from: image, maxDimension: 1024, quality: 0.9) else {
            return nil
        }
        try? data.write(to: generatedURL, options: .atomic)
        return data
    }

    func setCustomCover(for item: LibraryItem, image: UIImage) throws {
        guard let data = ImageService.jpegData(from: image, maxDimension: 1024, quality: 0.9) else {
            throw CoverError.encodeFailed
        }
        let key = item.id.uuidString
        try data.write(to: AppPaths.coverDirectory.appendingPathComponent(key + ".jpg"), options: .atomic)
        var updated = item
        updated.coverKey = key
        updated.updatedAt = Date()
        try db.save(updated)
    }

    func clearCustomCover(for item: LibraryItem) throws {
        guard let coverKey = item.coverKey else { return }
        try? FileManager.default.removeItem(
            at: AppPaths.coverDirectory.appendingPathComponent(coverKey + ".jpg")
        )
        var updated = item
        updated.coverKey = nil
        updated.updatedAt = Date()
        try db.save(updated)
    }
}

enum CoverError: LocalizedError {
    case encodeFailed

    var errorDescription: String? {
        "Unable to encode the cover image."
    }
}
