import Foundation

struct FolderPage {
    let path: String
    let url: URL
    let size: Int64
}

enum FolderScanner {
    static func directImages(in url: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents
            .filter { url in
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
                return values?.isRegularFile == true && ContainerClassifier.isImageFile(url.lastPathComponent)
            }
            .sorted { NaturalSort.compare($0.lastPathComponent, $1.lastPathComponent) == .orderedAscending }
    }

    static func allImages(in root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        let urls = enumerator.compactMap { $0 as? URL }.filter { url in
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            return values?.isRegularFile == true && ContainerClassifier.isImageFile(url.lastPathComponent)
        }
        return NaturalSort.sorted(urls) { relativePath(of: $0, from: root) }
    }

    static func archives(in root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return enumerator.compactMap { $0 as? URL }.filter { url in
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            return values?.isRegularFile == true && ContainerClassifier.isArchiveFile(url.lastPathComponent)
        }
    }

    static func pages(at root: URL) -> [FolderPage] {
        allImages(in: root).compactMap { url -> FolderPage? in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            return FolderPage(
                path: relativePath(of: url, from: root),
                url: url,
                size: Int64(values?.fileSize ?? 0)
            )
        }
    }

    static func relativePath(of url: URL, from root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else {
            return url.lastPathComponent
        }
        return String(path.dropFirst(rootPath.count + 1))
    }
}
