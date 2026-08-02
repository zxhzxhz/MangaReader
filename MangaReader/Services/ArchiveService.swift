import Foundation
import libarchive

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
        return try listLibArchivePages(at: url, password: password, depth: 0, entryCount: 0)
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
        return try readLibArchivePage(parts: parts, archiveURL: url, password: password)
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
            try extractLibArchive(at: url, to: destination, password: password)
        }
    }

    // MARK: - libarchive C API

    private func listLibArchivePages(
        at url: URL,
        password: String?,
        depth: Int,
        entryCount: Int
    ) throws -> [ArchivePage] {
        guard depth <= ArchiveLimits.maxDepth else {
            throw ArchiveServiceError.limitReached("recursion depth")
        }
        let reader = try CLibArchiveReader()
        defer { reader.close() }
        if let password, !password.isEmpty {
            try reader.addPassphrase(password)
        }
        try reader.open(url: url)

        var pages: [ArchivePage] = []
        var entriesSeen = entryCount
        var estimatedTotal: Int64 = 0

        while let entry = try reader.nextEntry() {
            entriesSeen += 1
            guard entriesSeen <= ArchiveLimits.maxEntryCount else {
                throw ArchiveServiceError.limitReached("entry count")
            }
            guard let safePath = PathSafety.sanitizedEntryPath(entry.path) else {
                try reader.skipData()
                continue
            }
            if entry.isEncrypted {
                guard let password, !password.isEmpty else {
                    throw ArchiveServiceError.passwordRequired
                }
            }

            var drained = false
            if entry.isRegular {
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
                    let nestedURL = try materializeNestedArchive(from: reader, password: password)
                    drained = true
                    defer { try? FileManager.default.removeItem(at: nestedURL) }
                    let nestedPages = try listLibArchivePages(
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
                try reader.skipData()
            }
        }
        return pages
    }

    private func materializeNestedArchive(from reader: CLibArchiveReader, password: String?) throws -> URL {
        let destination = AppPaths.extractedDirectory.appendingPathComponent("\(UUID().uuidString).archive")
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        do {
            var total: Int64 = 0
            while true {
                let chunk = try reader.readData()
                if chunk.isEmpty { break }
                total += Int64(chunk.count)
                guard total <= ArchiveLimits.maxSingleEntryBytes else {
                    throw ArchiveServiceError.limitReached("nested archive size")
                }
                try handle.write(contentsOf: Data(chunk))
            }
            try handle.close()
            return destination
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    private func readLibArchivePage(parts: [String], archiveURL: URL, password: String?) throws -> Data {
        if parts.count == 1 {
            let reader = try CLibArchiveReader()
            defer { reader.close() }
            if let password, !password.isEmpty {
                try reader.addPassphrase(password)
            }
            try reader.open(url: archiveURL)
            while let entry = try reader.nextEntry() {
                guard let safePath = PathSafety.sanitizedEntryPath(entry.path) else {
                    try reader.skipData()
                    continue
                }
                if entry.isEncrypted {
                    guard let password, !password.isEmpty else {
                        throw ArchiveServiceError.passwordRequired
                    }
                }
                if safePath == parts[0] {
                    return try readAllData(from: reader)
                }
                try reader.skipData()
            }
            throw ArchiveServiceError.invalidArchive("page not found")
        }

        let nestedURL = try materializeEntryToFile(path: parts[0], archiveURL: archiveURL, password: password)
        defer { try? FileManager.default.removeItem(at: nestedURL) }
        return try readLibArchivePage(
            parts: Array(parts.dropFirst()),
            archiveURL: nestedURL,
            password: password
        )
    }

    private func materializeEntryToFile(path: String, archiveURL: URL, password: String?) throws -> URL {
        let destination = AppPaths.extractedDirectory.appendingPathComponent("\(UUID().uuidString).nested")
        let reader = try CLibArchiveReader()
        defer { reader.close() }
        if let password, !password.isEmpty {
            try reader.addPassphrase(password)
        }
        try reader.open(url: archiveURL)

        do {
            while let entry = try reader.nextEntry() {
                guard let safePath = PathSafety.sanitizedEntryPath(entry.path) else {
                    try reader.skipData()
                    continue
                }
                if entry.isEncrypted {
                    guard let password, !password.isEmpty else {
                        throw ArchiveServiceError.passwordRequired
                    }
                }
                if safePath == path {
                    FileManager.default.createFile(atPath: destination.path, contents: nil)
                    let handle = try FileHandle(forWritingTo: destination)
                    var total: Int64 = 0
                    while true {
                        let chunk = try reader.readData()
                        if chunk.isEmpty { break }
                        total += Int64(chunk.count)
                        guard total <= ArchiveLimits.maxSingleEntryBytes else {
                            throw ArchiveServiceError.limitReached("nested archive size")
                        }
                        try handle.write(contentsOf: Data(chunk))
                    }
                    try handle.close()
                    return destination
                }
                try reader.skipData()
            }
            throw ArchiveServiceError.invalidArchive("nested archive not found")
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    private func readAllData(from reader: CLibArchiveReader) throws -> Data {
        var data = Data()
        while true {
            let chunk = try reader.readData()
            if chunk.isEmpty { break }
            data.append(contentsOf: chunk)
            if data.count > ArchiveLimits.maxSingleEntryBytes {
                throw ArchiveServiceError.limitReached("single entry size")
            }
        }
        return data
    }

    private func extractLibArchive(at url: URL, to destination: URL, password: String?) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let reader = try CLibArchiveReader()
        defer { reader.close() }
        if let password, !password.isEmpty {
            try reader.addPassphrase(password)
        }
        try reader.open(url: url)

        while let entry = try reader.nextEntry() {
            guard let safePath = PathSafety.sanitizedEntryPath(entry.path) else {
                try reader.skipData()
                continue
            }
            if entry.isEncrypted {
                guard let password, !password.isEmpty else {
                    throw ArchiveServiceError.passwordRequired
                }
            }
            let target = destination.appendingPathComponent(safePath)
            if entry.isDirectory {
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                try reader.skipData()
                continue
            }
            guard entry.isRegular else {
                try reader.skipData()
                continue
            }
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            FileManager.default.createFile(atPath: target.path, contents: nil)
            let handle = try FileHandle(forWritingTo: target)
            do {
                var total: Int64 = 0
                while true {
                    let chunk = try reader.readData()
                    if chunk.isEmpty { break }
                    total += Int64(chunk.count)
                    guard total <= ArchiveLimits.maxSingleEntryBytes else {
                        throw ArchiveServiceError.limitReached("single entry size")
                    }
                    try handle.write(contentsOf: Data(chunk))
                }
                try handle.close()
            } catch {
                try? handle.close()
                throw error
            }
        }
    }

    // MARK: - UnrarKit

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
        try data.write(to: nestedURL)
        return try await readRARPage(parts: Array(parts.dropFirst()), archiveURL: nestedURL, password: password)
    }
}

private enum CArchiveEncryptionState: Equatable {
    case yes
    case no
    case unknown
    case unsupported

    init(rawValue: Int32) {
        if rawValue >= 1 {
            self = .yes
        } else if rawValue == 0 {
            self = .no
        } else if rawValue == -1 {
            self = .unknown
        } else {
            self = .unsupported
        }
    }
}

private struct CArchiveEntry {
    let path: String
    let size: Int64
    let fileType: UInt32
    let isEncrypted: Bool

    var isRegular: Bool {
        fileType == 0o100000
    }

    var isDirectory: Bool {
        fileType == 0o040000
    }
}

private final class CLibArchiveReader {
    private let handle: OpaquePointer
    private var isClosed = false
    private var reachedEOF = false

    init() throws {
        guard let handle = archive_read_new() else {
            throw ArchiveServiceError.invalidArchive("unable to allocate libarchive reader")
        }
        self.handle = handle
        _ = archive_read_support_format_all(handle)
        _ = archive_read_support_filter_all(handle)
    }

    func addPassphrase(_ passphrase: String) throws {
        let rc = passphrase.withCString { archive_read_add_passphrase(handle, $0) }
        guard rc == ARCHIVE_OK || rc == ARCHIVE_WARN else {
            throw ArchiveServiceError.invalidArchive(errorString())
        }
    }

    func open(url: URL) throws {
        let rc = url.path.withCString { archive_read_open_filename(handle, $0, 64 * 1024) }
        guard rc == ARCHIVE_OK || rc == ARCHIVE_WARN else {
            throw ArchiveServiceError.invalidArchive(errorString())
        }
    }

    func nextEntry() throws -> CArchiveEntry? {
        guard !reachedEOF, !isClosed else { return nil }
        var entryPointer: OpaquePointer?
        let rc = archive_read_next_header(handle, &entryPointer)
        if rc == ARCHIVE_EOF {
            reachedEOF = true
            return nil
        }
        guard rc == ARCHIVE_OK || rc == ARCHIVE_WARN else {
            throw ArchiveServiceError.invalidArchive(errorString())
        }
        guard let entryPointer else {
            return nil
        }

        let path: String
        if let utf8 = archive_entry_pathname_utf8(entryPointer) {
            path = String(cString: utf8)
        } else if let raw = archive_entry_pathname(entryPointer) {
            path = String(cString: raw)
        } else {
            path = ""
        }
        let typeWord = UInt32(archive_entry_filetype(entryPointer)) & 0o170000
        return CArchiveEntry(
            path: path,
            size: Int64(archive_entry_size(entryPointer)),
            fileType: typeWord,
            isEncrypted: archive_entry_is_encrypted(entryPointer) != 0
        )
    }

    func readData(maxLength: Int = 64 * 1024) throws -> [UInt8] {
        guard !isClosed else { return [] }
        var chunk = [UInt8](repeating: 0, count: maxLength)
        let count = chunk.withUnsafeMutableBytes { buffer -> Int64 in
            guard let base = buffer.baseAddress else { return 0 }
            return Int64(archive_read_data(handle, base, buffer.count))
        }
        if count == 0 { return [] }
        if count < 0 {
            throw ArchiveServiceError.invalidArchive(errorString())
        }
        return Array(chunk.prefix(Int(count)))
    }

    func skipData() throws {
        let rc = archive_read_data_skip(handle)
        guard rc == ARCHIVE_OK || rc == ARCHIVE_WARN || rc == ARCHIVE_EOF else {
            throw ArchiveServiceError.invalidArchive(errorString())
        }
    }

    func hasEncryptedEntries() -> CArchiveEncryptionState {
        CArchiveEncryptionState(rawValue: archive_read_has_encrypted_entries(handle))
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        _ = archive_read_close(handle)
        _ = archive_read_free(handle)
    }

    deinit {
        if !isClosed {
            _ = archive_read_close(handle)
            _ = archive_read_free(handle)
        }
    }

    private func errorString() -> String {
        guard let cstr = archive_error_string(handle) else { return "unknown libarchive error" }
        return String(cString: cstr)
    }
}
