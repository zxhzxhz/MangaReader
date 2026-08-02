import Foundation

enum CacheKind: String {
    case thumbnail
    case extracted
    case enhanced
    case index

    var directory: URL {
        switch self {
        case .thumbnail:
            return AppPaths.thumbnailsDirectory
        case .extracted:
            return AppPaths.extractedDirectory
        case .enhanced:
            return AppPaths.enhancedDirectory
        case .index:
            return AppPaths.indexesDirectory
        }
    }
}

actor CacheManager {
    static let shared = CacheManager()

    private var limitBytes: Int64 = 5 * 1024 * 1024 * 1024

    func setLimit(gigabytes: Double) {
        limitBytes = Int64(max(1, min(50, gigabytes)) * 1024 * 1024 * 1024)
    }

    func cacheURL(kind: CacheKind, bookID: UUID, key: String, ext: String) -> URL {
        let name = "\(bookID.uuidString)-\(CacheKey.make([key])).\(ext)"
        return kind.directory.appendingPathComponent(name)
    }

    func store(_ data: Data, kind: CacheKind, bookID: UUID, key: String, ext: String) throws -> URL {
        let url = cacheURL(kind: kind, bookID: bookID, key: key, ext: ext)
        try data.write(to: url, options: .atomic)
        enforceLimit()
        return url
    }

    func data(kind: CacheKind, bookID: UUID, key: String, ext: String) -> Data? {
        let url = cacheURL(kind: kind, bookID: bookID, key: key, ext: ext)
        return try? Data(contentsOf: url)
    }

    func purge(bookID: UUID) {
        let prefix = bookID.uuidString + "-"
        for kind in [CacheKind.thumbnail, .enhanced, .index] {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: kind.directory,
                includingPropertiesForKeys: nil
            ) else {
                continue
            }
            for file in files where file.lastPathComponent.hasPrefix(prefix) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    func purgeAll() {
        for kind in [CacheKind.thumbnail, .extracted, .enhanced, .index] {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: kind.directory,
                includingPropertiesForKeys: nil
            ) else {
                continue
            }
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    func currentSize() -> Int64 {
        [CacheKind.thumbnail, .extracted, .enhanced, .index]
            .map { sizeOfDirectory($0.directory) }
            .reduce(0, +)
    }

    func enforceLimit() {
        guard currentSize() > limitBytes else { return }
        let files = allFiles()
            .compactMap { url -> (URL, Date)? in
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                return values?.contentModificationDate.map { (url, $0) }
            }
            .sorted { $0.1 < $1.1 }

        for item in files {
            guard currentSize() > limitBytes else { break }
            try? FileManager.default.removeItem(at: item.0)
        }
    }

    private func sizeOfDirectory(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true {
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return total
    }

    private func allFiles() -> [URL] {
        [CacheKind.thumbnail, .extracted, .enhanced, .index].flatMap { kind in
            (try? FileManager.default.contentsOfDirectory(
                at: kind.directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
            )) ?? []
        }
    }
}
