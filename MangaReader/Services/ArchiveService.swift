import Foundation
import SwiftArchive

struct ArchiveLimits {
    static let maxDepth = 4
    static let maxEntryCount = 20_000
    static let maxSingleEntryBytes: Int64 = 512 * 1024 * 1024
    static let maxEstimatedTotalBytes: Int64 = 2 * 1024 * 1024 * 1024
}

enum ArchiveServiceError: LocalizedError {
    case passwordRequired
    case invalidArchive(String)
    case limitReached(String)
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .passwordRequired:
            return "This archive requires a password."
        case .invalidArchive(let reason):
            return "The archive could not be read: \(reason)"
        case .limitReached(let reason):
            return "Archive limit reached: \(reason)"
        case .unsupportedFormat:
            return "This archive format is not supported."
        }
    }
}

actor ArchiveService {
    func listPages(for item: LibraryItem) async throws -> [ArchivePage] {
        guard let url = item.url, FileManager.default.fileExists(atPath: url.path) else {
            throw ArchiveServiceError.invalidArchive("file not found")
        }
        let password = KeychainStore.password(forBookID: item.id)
        let ext = url.pathExtension.lowercased()
        if ext == "rar" {
            return try await listRARPages(at: url, password: password, depth: 0, entryCount: 0)
        }
        return try await listLibArchivePages(at: url, password: password, depth: 0, entryCount: 0)
    }

    func pageData(for page: ArchivePage, in item: LibraryItem) async throws -> Data {
        guard let url = item.url else {
            throw ArchiveServiceError.invalidArchive("file not found")
        }
        let password = KeychainStore.password(forBookID: item.id)
        let parts = page.path.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty else {
            throw ArchiveServiceError.invalidArchive("empty page path")
        }
        let ext = url.pathExtension.lowercased()
        if ext == "rar" {
            return try await readRARPage(parts: parts, archiveURL: url, password: password)
        }
        return try await readLibArchivePage(parts: parts, archiveURL: url, password: password)
    }

    func extractArchive(_ item: LibraryItem, to destination: URL) async throws {
        guard let url = item.url else {
            throw ArchiveServiceError.invalidArchive("file not found")
        }
        let password = KeychainStore.password(forBookID: item.id)
        if url.pathExtension.lowercased() == "rar" {
            var error: NSError?
            guard let archive = URKArchive(url: url, error: &error) else {
                throw ArchiveServiceError.invalidArchive(error?.localizedDescription ?? "unable to open RAR")
            }
            if archive.isPasswordProtected {
                guard let password, !password.isEmpty else {
                    throw ArchiveServiceError.passwordRequired
                }
                archive.password = password
            }
            let ok = archive.extractFiles(to: destination.path, overwrite: true, error: &error)
            guard ok else {
                throw ArchiveServiceError.invalidArchive(error?.localizedDescription ?? "RAR extraction failed")
            }
        } else {
            try await Archive.extract(.fileURL(url), to: destination, options: .secure)
        }
    }

    private func listLibArchivePages(
        at url: URL,
        password: String?,
        depth: Int,
        entryCount: Int
    ) async throws -> [ArchivePage] {
        guard depth <= ArchiveLimits.maxDepth else {
            throw ArchiveServiceError.limitReached("recursion depth")
        }
        let reader = try await ArchiveReader(reading: .fileURL(url))
        defer { Task { await reader.close() } }
        do {
            var pages: [ArchivePage] = []
            var entriesSeen = entryCount
            var estimatedTotal: Int64 = 0

            while let entry = try await reader.nextEntry() {
                entriesSeen += 1
                guard entriesSeen <= ArchiveLimits.maxEntryCount else {
                    throw ArchiveServiceError.limitReached("entry count")
                }
                guard let safePath = PathSafety.sanitizedEntryPath(entry.path) else {
                    try await reader.skipData()
                    continue
                }

                if await reader.hasEncryptedEntries() == .yes || entry.isEncrypted {
                    if let password, !password.isEmpty {
                        try await reader.addPassphrase(password)
                    } else if entry.isEncrypted {
                        throw ArchiveServiceError.passwordRequired
                    }
                }

                var drained = false
                if entry.fileType == .regular {
                    if ContainerClassifier.isImageFile(safePath) {
                        guard entry.size <= ArchiveLimits.maxSingleEntryBytes else {
                            throw ArchiveServiceError.limitReached("single entry size")
                        }
                        pages.append(ArchivePage(path: safePath, size: entry.size, nestedDepth: depth))
                        estimatedTotal += entry.size
                        if estimatedTotal > ArchiveLimits.maxEstimatedTotalBytes {
                            throw ArchiveServiceError.limitReached("estimated total size")
                        }
                    } else if ContainerClassifier.isArchiveFile(safePath) && depth < ArchiveLimits.maxDepth {
                        let nestedURL = try await materializeNestedArchive(from: reader, entry: entry)
                        defer { try? FileManager.default.removeItem(at: nestedURL) }
                        drained = true
                        let nestedPages = try await listLibArchivePages(
                            at: nestedURL,
                            password: password,
                            depth: depth + 1,
                            entryCount: entriesSeen
                        )
                        for nestedPage in nestedPages {
                            pages.append(
                                ArchivePage(
                                    path: "\(safePath)|\(nestedPage.path)",
                                    size: nestedPage.size,
                                    nestedDepth: depth + 1
                                )
                            )
                        }
                    }
                }

                if !drained {
                    try await reader.skipData()
                }
            }
            return pages
        } catch {
            throw error
        }
    }

    private func materializeNestedArchive(from reader: ArchiveReader, entry: ArchiveEntry) async throws -> URL {
        let destination = AppPaths.extractedDirectory.appendingPathComponent("\(UUID().uuidString).archive")
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        do {
            var total: Int64 = 0
            for try await chunk in reader.dataStream(chunkSize: 64 * 1024) {
                total += Int64(chunk.count)
                guard total <= ArchiveLimits.maxSingleEntryBytes else {
                    throw ArchiveServiceError.limitReached("nested archive size")
                }
                try handle.write(contentsOf: chunk)
            }
            try handle.close()
            return destination
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    private func readLibArchivePage(parts: [String], archiveURL: URL, password: String?) async throws -> Data {
        if parts.count == 1 {
            let reader = try await ArchiveReader(reading: .fileURL(archiveURL))
            defer { Task { await reader.close() } }
            while let entry = try await reader.nextEntry() {
                guard let safePath = PathSafety.sanitizedEntryPath(entry.path) else {
                    try await reader.skipData()
                    continue
                }
                if await reader.hasEncryptedEntries() == .yes || entry.isEncrypted {
                    guard let password, !password.isEmpty else {
                        throw ArchiveServiceError.passwordRequired
                    }
                    try await reader.addPassphrase(password)
                }
                if safePath == parts[0] {
                    let bytes = try await reader.readAllData()
                    return Data(bytes)
                }
                try await reader.skipData()
            }
            throw ArchiveServiceError.invalidArchive("page not found")
        }

        let nestedURL = try await materializeEntryToFile(path: parts[0], archiveURL: archiveURL, password: password)
        defer { try? FileManager.default.removeItem(at: nestedURL) }
        do {
            return try await readLibArchivePage(
                parts: Array(parts.dropFirst()),
                archiveURL: nestedURL,
                password: password
            )
        } catch {
            throw error
        }
    }

    private func materializeEntryToFile(path: String, archiveURL: URL, password: String?) async throws -> URL {
        let destination = AppPaths.extractedDirectory.appendingPathComponent("\(UUID().uuidString).nested")
        let reader = try await ArchiveReader(reading: .fileURL(archiveURL))
        do {
            while let entry = try await reader.nextEntry() {
                guard let safePath = PathSafety.sanitizedEntryPath(entry.path) else {
                    try await reader.skipData()
                    continue
                }
                if await reader.hasEncryptedEntries() == .yes || entry.isEncrypted {
                    guard let password, !password.isEmpty else {
                        throw ArchiveServiceError.passwordRequired
                    }
                    try await reader.addPassphrase(password)
                }
                if safePath == path {
                    FileManager.default.createFile(atPath: destination.path, contents: nil)
                    let handle = try FileHandle(forWritingTo: destination)
                    var total: Int64 = 0
                    for try await chunk in reader.dataStream(chunkSize: 64 * 1024) {
                        total += Int64(chunk.count)
                        guard total <= ArchiveLimits.maxSingleEntryBytes else {
                            throw ArchiveServiceError.limitReached("nested archive size")
                        }
                        try handle.write(contentsOf: chunk)
                    }
                    try handle.close()
                    return destination
                }
                try await reader.skipData()
            }
            throw ArchiveServiceError.invalidArchive("nested archive not found")
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        defer { Task { await reader.close() } }
    }

    private func listRARPages(at url: URL, password: String?, depth: Int, entryCount: Int) async throws -> [ArchivePage] {
        guard depth <= ArchiveLimits.maxDepth else {
            throw ArchiveServiceError.limitReached("recursion depth")
        }
        var error: NSError?
        guard let archive = URKArchive(url: url, error: &error) else {
            throw ArchiveServiceError.invalidArchive(error?.localizedDescription ?? "unable to open RAR")
        }
        if archive.isPasswordProtected {
            guard let password, !password.isEmpty else {
                throw ArchiveServiceError.passwordRequired
            }
            archive.password = password
        }
        guard let fileInfo = archive.listFileInfo(&error) else {
            throw ArchiveServiceError.invalidArchive(error?.localizedDescription ?? "unable to list RAR")
        }

        var pages: [ArchivePage] = []
        var entriesSeen = entryCount
        var estimatedTotal: Int64 = 0
        for info in fileInfo {
            entriesSeen += 1
            guard entriesSeen <= ArchiveLimits.maxEntryCount else {
                throw ArchiveServiceError.limitReached("entry count")
            }
            guard !info.isDirectory else { continue }
            guard let safePath = PathSafety.sanitizedEntryPath(info.filename) else { continue }
            if ContainerClassifier.isImageFile(safePath) {
                guard info.uncompressedSize <= ArchiveLimits.maxSingleEntryBytes else {
                    throw ArchiveServiceError.limitReached("single entry size")
                }
                pages.append(ArchivePage(path: safePath, size: info.uncompressedSize, nestedDepth: depth))
                estimatedTotal += info.uncompressedSize
                if estimatedTotal > ArchiveLimits.maxEstimatedTotalBytes {
                    throw ArchiveServiceError.limitReached("estimated total size")
                }
            } else if ContainerClassifier.isArchiveFile(safePath) && depth < ArchiveLimits.maxDepth {
                var dataError: NSError?
                guard let data = archive.extractData(fromFile: safePath, error: &dataError) else {
                    throw ArchiveServiceError.invalidArchive(dataError?.localizedDescription ?? "nested RAR read failed")
                }
                guard Int64(data.count) <= ArchiveLimits.maxSingleEntryBytes else {
                    throw ArchiveServiceError.limitReached("nested archive size")
                }
                let nestedURL = AppPaths.extractedDirectory.appendingPathComponent("\(UUID().uuidString).rar")
                defer { try? FileManager.default.removeItem(at: nestedURL) }
                try data.write(to: nestedURL)
                let nestedPages = try await listRARPages(
                    at: nestedURL,
                    password: password,
                    depth: depth + 1,
                    entryCount: entriesSeen
                )
                for nestedPage in nestedPages {
                    pages.append(
                        ArchivePage(
                            path: "\(safePath)|\(nestedPage.path)",
                            size: nestedPage.size,
                            nestedDepth: depth + 1
                        )
                    )
                }
            }
        }
        return pages
    }

    private func readRARPage(parts: [String], archiveURL: URL, password: String?) async throws -> Data {
        if parts.count == 1 {
            var error: NSError?
            guard let archive = URKArchive(url: archiveURL, error: &error) else {
                throw ArchiveServiceError.invalidArchive(error?.localizedDescription ?? "unable to open RAR")
            }
            if archive.isPasswordProtected {
                guard let password, !password.isEmpty else {
                    throw ArchiveServiceError.passwordRequired
                }
                archive.password = password
            }
            guard let data = archive.extractData(fromFile: parts[0], error: &error) else {
                throw ArchiveServiceError.invalidArchive(error?.localizedDescription ?? "RAR page read failed")
            }
            return data
        }

        var error: NSError?
        guard let archive = URKArchive(url: archiveURL, error: &error) else {
            throw ArchiveServiceError.invalidArchive(error?.localizedDescription ?? "unable to open RAR")
        }
        if archive.isPasswordProtected {
            guard let password, !password.isEmpty else {
                throw ArchiveServiceError.passwordRequired
            }
            archive.password = password
        }
        guard let data = archive.extractData(fromFile: parts[0], error: &error) else {
            throw ArchiveServiceError.invalidArchive(error?.localizedDescription ?? "nested RAR read failed")
        }
        let nestedURL = AppPaths.extractedDirectory.appendingPathComponent("\(UUID().uuidString).rar")
        defer { try? FileManager.default.removeItem(at: nestedURL) }
        do {
            try data.write(to: nestedURL)
            return try await readRARPage(parts: Array(parts.dropFirst()), archiveURL: nestedURL, password: password)
        } catch {
            throw error
        }
    }
}
