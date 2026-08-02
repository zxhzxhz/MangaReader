import CryptoKit
import Foundation

enum Fingerprint {
    static let largeFileThreshold: Int64 = 256 * 1024 * 1024
    private static let sampleSize: Int64 = 4 * 1024 * 1024

    static func folderFingerprint(imageFiles: [(name: String, size: Int64)]) -> String {
        let ordered = imageFiles.sorted { NaturalSort.compare($0.name, $1.name) == .orderedAscending }
        var hasher = SHA256()
        for item in ordered {
            hasher.update(data: Data(item.name.utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: withUnsafeBytes(of: item.size.littleEndian) { Data($0) })
            hasher.update(data: Data([0]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func folderFingerprint(at url: URL) -> String {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return folderFingerprint(imageFiles: [])
        }
        let rootPath = url.standardizedFileURL.path
        var files: [(name: String, size: Int64)] = []
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }
            let path = fileURL.standardizedFileURL.path
            guard path.hasPrefix(rootPath + "/") else { continue }
            let relative = String(path.dropFirst(rootPath.count + 1))
            files.append((name: relative, size: Int64(values?.fileSize ?? 0)))
        }
        return folderFingerprint(imageFiles: files)
    }

    static func archiveFingerprint(at url: URL) throws -> String {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        let size = Int64(values.fileSize ?? 0)
        if size <= largeFileThreshold {
            return try fileDigest(at: url)
        }

        var hasher = SHA256()
        hasher.update(data: withUnsafeBytes(of: size.littleEndian) { Data($0) })
        try appendSample(from: url, offset: 0, count: sampleSize, to: &hasher)
        try appendSample(from: url, offset: max(0, size - sampleSize), count: sampleSize, to: &hasher)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func appendSample(from url: URL, offset: Int64, count: Int64, to hasher: inout SHA256) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(max(0, offset)))
        let data = try handle.read(upToCount: Int(count)) ?? Data()
        hasher.update(data: data)
    }

    private static func fileDigest(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
