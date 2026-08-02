import Foundation
import GRDB

enum LibraryItemKind: String, Codable, CaseIterable, Sendable {
    case bookFolder = "book_folder"
    case archive = "archive"
    case collection = "collection"
    case mixed = "mixed"
    case model = "model"
    case unknown = "unknown"

    var isBook: Bool {
        self == .bookFolder || self == .archive
    }
}

enum MixedResolution: String, Codable, CaseIterable, Sendable {
    case pending
    case split
    case merge
    case skip
}

struct LibraryItem: Identifiable, Equatable, Hashable, Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "libraryItem"

    var id: UUID
    var relativePath: String
    var fingerprint: String
    var title: String
    var kind: LibraryItemKind
    var mixedResolution: MixedResolution
    var directImageCount: Int
    var isVirtual: Bool
    var coverKey: String?
    var progressPage: Int
    var pageCount: Int?
    var createdAt: Date
    var updatedAt: Date

    var url: URL? {
        isVirtual ? nil : AppPaths.libraryRoot.appendingPathComponent(relativePath)
    }

    var virtualParentURL: URL? {
        guard isVirtual, relativePath.hasSuffix(VirtualBook.suffix) else { return nil }
        let parentPath = String(relativePath.dropLast(VirtualBook.suffix.count))
        return AppPaths.libraryRoot.appendingPathComponent(parentPath)
    }

    static func new(
        relativePath: String,
        fingerprint: String,
        title: String,
        kind: LibraryItemKind
    ) -> LibraryItem {
        let now = Date()
        return LibraryItem(
            id: UUID(),
            relativePath: relativePath,
            fingerprint: fingerprint,
            title: title,
            kind: kind,
            mixedResolution: .pending,
            directImageCount: 0,
            isVirtual: false,
            coverKey: nil,
            progressPage: 0,
            pageCount: nil,
            createdAt: now,
            updatedAt: now
        )
    }
}

enum VirtualBook {
    static let suffix = "__direct_images__"

    static func relativePath(parent: String) -> String {
        parent.isEmpty ? suffix : parent + "/" + suffix
    }
}
