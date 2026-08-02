import Foundation

actor FileOperationsService {
    let db: AppDatabase
    let archiveService: ArchiveService

    init(db: AppDatabase, archiveService: ArchiveService) {
        self.db = db
        self.archiveService = archiveService
    }

    func createFolder(named name: String, in parent: LibraryItem?) throws -> LibraryItem {
        let parentRelative = parent?.relativePath ?? ""
        let newRelative = parentRelative.isEmpty ? name : parentRelative + "/" + name
        let url = AppPaths.libraryRoot.appendingPathComponent(newRelative)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw FileOperationError.pathExists
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let item = LibraryItem.new(
            relativePath: newRelative,
            fingerprint: Fingerprint.folderFingerprint(imageFiles: []),
            title: name,
            kind: .collection
        )
        try db.save(item)
        return item
    }

    func rename(_ item: LibraryItem, to newName: String) throws {
        guard let url = item.url else {
            throw FileOperationError.missingPath
        }
        let newURL = url.deletingLastPathComponent().appendingPathComponent(newName)
        guard !FileManager.default.fileExists(atPath: newURL.path) else {
            throw FileOperationError.pathExists
        }
        try FileManager.default.moveItem(at: url, to: newURL)
        let oldRelative = item.relativePath
        let newRelative = relativePath(for: newURL)
        try db.updateRelativePathPrefix(from: oldRelative, to: newRelative)
        if var renamed = try db.item(byRelativePath: newRelative) {
            renamed.title = newName
            renamed.updatedAt = Date()
            try db.save(renamed)
        }
    }

    func move(_ item: LibraryItem, toFolder parent: LibraryItem?) throws {
        guard let url = item.url else {
            throw FileOperationError.missingPath
        }
        let parentRelative = parent?.relativePath ?? ""
        let newURL = (parentRelative.isEmpty
            ? AppPaths.libraryRoot
            : AppPaths.libraryRoot.appendingPathComponent(parentRelative)
        ).appendingPathComponent(url.lastPathComponent)
        guard !FileManager.default.fileExists(atPath: newURL.path) else {
            throw FileOperationError.pathExists
        }
        try FileManager.default.moveItem(at: url, to: newURL)
        let oldRelative = item.relativePath
        let newRelative = relativePath(for: newURL)
        try db.updateRelativePathPrefix(from: oldRelative, to: newRelative)
    }

    func copy(_ item: LibraryItem, toFolder parent: LibraryItem?) throws -> LibraryItem {
        guard let url = item.url else {
            throw FileOperationError.missingPath
        }
        let parentRelative = parent?.relativePath ?? ""
        let oldRelative = relativePath(for: url)
        let newRelative = parentRelative.isEmpty
            ? url.lastPathComponent
            : parentRelative + "/" + url.lastPathComponent
        let newURL = AppPaths.libraryRoot.appendingPathComponent(newRelative)
        guard !FileManager.default.fileExists(atPath: newURL.path) else {
            throw FileOperationError.pathExists
        }
        if !item.isVirtual {
            try FileManager.default.copyItem(at: url, to: newURL)
        }

        let oldItems = try db.items(atOrUnder: oldRelative)
            .sorted { $0.relativePath.count < $1.relativePath.count }
        var rootCopy: LibraryItem?
        for old in oldItems {
            let suffix = old.relativePath == oldRelative
                ? ""
                : String(old.relativePath.dropFirst(oldRelative.count + 1))
            let copyRelative = suffix.isEmpty ? newRelative : newRelative + "/" + suffix
            var newItem = LibraryItem.new(
                relativePath: copyRelative,
                fingerprint: old.fingerprint,
                title: old.title,
                kind: old.kind
            )
            newItem.mixedResolution = old.mixedResolution
            newItem.directImageCount = old.directImageCount
            newItem.isVirtual = old.isVirtual
            if let oldCoverKey = old.coverKey {
                let newCoverKey = newItem.id.uuidString
                let source = AppPaths.coverDirectory.appendingPathComponent(oldCoverKey + ".jpg")
                let target = AppPaths.coverDirectory.appendingPathComponent(newCoverKey + ".jpg")
                if let data = try? Data(contentsOf: source) {
                    try? data.write(to: target)
                    newItem.coverKey = newCoverKey
                }
            }
            try db.save(newItem)
            if old.id == item.id {
                rootCopy = newItem
            }
        }
        guard let rootCopy else {
            throw FileOperationError.missingPath
        }
        return rootCopy
    }

    func delete(_ item: LibraryItem) async throws {
        if item.isVirtual {
            try? db.delete(item)
            await CacheManager.shared.purge(bookID: item.id)
            KeychainStore.deletePassword(forBookID: item.id)
            if let coverKey = item.coverKey {
                try? FileManager.default.removeItem(
                    at: AppPaths.coverDirectory.appendingPathComponent(coverKey + ".jpg")
                )
            }
            return
        }

        guard let url = item.url else {
            throw FileOperationError.missingPath
        }
        let items = try db.items(atOrUnder: item.relativePath)
        for child in items {
            try? db.delete(child)
            await CacheManager.shared.purge(bookID: child.id)
            KeychainStore.deletePassword(forBookID: child.id)
            if let coverKey = child.coverKey {
                try? FileManager.default.removeItem(
                    at: AppPaths.coverDirectory.appendingPathComponent(coverKey + ".jpg")
                )
            }
        }
        try FileManager.default.removeItem(at: url)
    }

    func extractArchive(_ item: LibraryItem) async throws -> LibraryItem {
        guard item.kind == .archive, let url = item.url else {
            throw FileOperationError.notAnArchive
        }
        let name = url.deletingPathExtension().lastPathComponent
        let destination = url.deletingLastPathComponent().appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw FileOperationError.pathExists
        }

        do {
            try await archiveService.extractArchive(item, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }

        let newRelative = relativePath(for: destination)
        let fingerprint = Fingerprint.folderFingerprint(at: destination)
        var newItem = LibraryItem.new(
            relativePath: newRelative,
            fingerprint: fingerprint,
            title: name,
            kind: .bookFolder
        )
        newItem.coverKey = item.coverKey
        newItem.progressPage = item.progressPage
        try db.save(newItem)
        try? db.delete(item)
        try? FileManager.default.removeItem(at: url)
        await CacheManager.shared.purge(bookID: item.id)
        KeychainStore.deletePassword(forBookID: item.id)
        return newItem
    }

    private func relativePath(for url: URL) -> String {
        let root = AppPaths.libraryRoot.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(root + "/") else {
            return url.lastPathComponent
        }
        return String(path.dropFirst(root.count + 1))
    }
}

enum FileOperationError: LocalizedError {
    case pathExists
    case missingPath
    case notAnArchive

    var errorDescription: String? {
        switch self {
        case .pathExists:
            return "An item with that name already exists."
        case .missingPath:
            return "The item path is missing."
        case .notAnArchive:
            return "This item is not an archive."
        }
    }
}
