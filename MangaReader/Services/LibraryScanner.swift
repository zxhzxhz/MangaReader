import Foundation

struct DiscoveredNode {
    let relativePath: String
    let title: String
    let kind: LibraryItemKind
    let fingerprint: String
    let directImageCount: Int
}

actor LibraryScanner {
    let db: AppDatabase

    init(db: AppDatabase) {
        self.db = db
    }

    func scan() throws {
        let discovered = try discoverChildren(of: AppPaths.libraryRoot, relativePath: "")
        try reconcile(discovered)
    }

    func resolveMixed(_ item: LibraryItem, resolution: MixedResolution) throws {
        guard let url = item.url, item.kind == .mixed else {
            return
        }
        var updated = item
        updated.mixedResolution = resolution
        updated.updatedAt = Date()

        switch resolution {
        case .merge:
            updated.kind = .bookFolder
            updated.directImageCount = 0
            updated.fingerprint = Fingerprint.folderFingerprint(at: url)
            let descendants = try db.items(under: item.relativePath)
            for descendant in descendants where descendant.isVirtual {
                try db.delete(descendant)
            }

        case .split:
            updated.kind = .collection
            updated.directImageCount = FolderScanner.directImages(in: url).count
            try ensureVirtualBook(for: updated, at: url)

        case .pending, .skip:
            break
        }

        try db.save(updated)
    }

    private func ensureVirtualBook(for item: LibraryItem, at url: URL) throws {
        let virtualPath = VirtualBook.relativePath(parent: item.relativePath)
        if try db.item(byRelativePath: virtualPath) != nil {
            return
        }
        let direct = FolderScanner.directImages(in: url)
        let fingerprint = Fingerprint.folderFingerprint(
            imageFiles: direct.map { url in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                return (name: url.lastPathComponent, size: Int64(size))
            }
        )
        var virtual = LibraryItem.new(
            relativePath: virtualPath,
            fingerprint: fingerprint,
            title: "Images",
            kind: .bookFolder
        )
        virtual.isVirtual = true
        try db.save(virtual)
    }

    private func discoverChildren(of url: URL, relativePath: String) throws -> [DiscoveredNode] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var nodes: [DiscoveredNode] = []
        for child in contents.sorted(by: { NaturalSort.compare($0.lastPathComponent, $1.lastPathComponent) == .orderedAscending }) {
            let name = child.lastPathComponent
            if name == "Models" {
                continue
            }
            let rel = relativePath.isEmpty ? name : relativePath + "/" + name
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == true {
                nodes.append(contentsOf: try discoverFolder(child, relativePath: rel))
            } else if ContainerClassifier.isArchiveFile(name) {
                if let node = archiveNode(url: child, relativePath: rel) {
                    nodes.append(node)
                }
            }
        }
        return nodes
    }

    private func discoverFolder(_ url: URL, relativePath: String) throws -> [DiscoveredNode] {
        let directImages = FolderScanner.directImages(in: url)
        let children = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let childFolders = children.filter { url in
            url.lastPathComponent != "Models" &&
                ((try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false)
        }
        let childArchives = children.filter { !$0.hasDirectoryPath && ContainerClassifier.isArchiveFile($0.lastPathComponent) }

        if let existing = try db.item(byRelativePath: relativePath) {
            if existing.mixedResolution == .merge {
                var nodes = [node(
                    url: url,
                    relativePath: relativePath,
                    kind: .bookFolder,
                    directImageCount: 0
                )]
                for child in childFolders + childArchives {
                    let rel = relativePath + "/" + child.lastPathComponent
                    if child.hasDirectoryPath {
                        nodes.append(contentsOf: try discoverFolder(child, relativePath: rel))
                    } else {
                        if let node = archiveNode(url: child, relativePath: rel) {
                            nodes.append(node)
                        }
                    }
                }
                return nodes
            }
            if existing.mixedResolution == .split {
                var nodes = [node(
                    url: url,
                    relativePath: relativePath,
                    kind: .collection,
                    directImageCount: directImages.count
                )]
                for child in childFolders + childArchives {
                    let rel = relativePath + "/" + child.lastPathComponent
                    if child.hasDirectoryPath {
                        nodes.append(contentsOf: try discoverFolder(child, relativePath: rel))
                    } else {
                        nodes.append(try archiveNode(url: child, relativePath: rel))
                    }
                }
                return nodes
            }
        }

        let classification = ContainerClassifier.classify(
            directImageCount: directImages.count,
            childCount: childFolders.count + childArchives.count,
            singleChildName: childFolders.count == 1 && childArchives.isEmpty
                ? childFolders[0].lastPathComponent
                : nil
        )

        if classification.shouldCollapseWrapper {
            return [node(
                url: url,
                relativePath: relativePath,
                kind: .bookFolder,
                directImageCount: 0
            )]
        }

        switch classification.kind {
        case .book:
            return [node(
                url: url,
                relativePath: relativePath,
                kind: .bookFolder,
                directImageCount: 0
            )]

        case .collection:
            var nodes = [node(
                url: url,
                relativePath: relativePath,
                kind: .collection,
                directImageCount: 0
            )]
            for child in childFolders + childArchives {
                let rel = relativePath + "/" + child.lastPathComponent
                if child.hasDirectoryPath {
                    nodes.append(contentsOf: try discoverFolder(child, relativePath: rel))
                } else {
                    if let node = archiveNode(url: child, relativePath: rel) {
                        nodes.append(node)
                    }
                }
            }
            return nodes

        case .mixed:
            return [node(
                url: url,
                relativePath: relativePath,
                kind: .mixed,
                directImageCount: directImages.count
            )]

        case .unknown:
            return [node(
                url: url,
                relativePath: relativePath,
                kind: .collection,
                directImageCount: 0
            )]
        }
    }

    private func node(
        url: URL,
        relativePath: String,
        kind: LibraryItemKind,
        directImageCount: Int
    ) -> DiscoveredNode {
        let fingerprint = kind == .archive
            ? (try? Fingerprint.archiveFingerprint(at: url)) ?? ""
            : Fingerprint.folderFingerprint(at: url)
        return DiscoveredNode(
            relativePath: relativePath,
            title: url.lastPathComponent,
            kind: kind,
            fingerprint: fingerprint,
            directImageCount: directImageCount
        )
    }

    private func archiveNode(url: URL, relativePath: String) -> DiscoveredNode? {
        guard let fingerprint = try? Fingerprint.archiveFingerprint(at: url) else {
            return nil
        }
        return DiscoveredNode(
            relativePath: relativePath,
            title: url.lastPathComponent,
            kind: .archive,
            fingerprint: fingerprint,
            directImageCount: 0
        )
    }

    private func reconcile(_ discovered: [DiscoveredNode]) throws {
        let dbItems = try db.allItems()
        let discoveredByPath = Dictionary(uniqueKeysWithValues: discovered.map { ($0.relativePath, $0) })
        var migratedIDs = Set<UUID>()
        var usedFingerprints = Set<String>()

        for node in discovered {
            var updated: LibraryItem
            if let existing = dbItems.first(where: { $0.relativePath == node.relativePath }) {
                updated = existing
            } else if let match = dbItems.first(where: {
                $0.fingerprint == node.fingerprint &&
                    !$0.isVirtual &&
                    !discoveredByPath.keys.contains($0.relativePath) &&
                    !migratedIDs.contains($0.id)
            }), usedFingerprints.insert(node.fingerprint).inserted {
                updated = match
                migratedIDs.insert(match.id)
            } else {
                updated = LibraryItem.new(
                    relativePath: node.relativePath,
                    fingerprint: node.fingerprint,
                    title: node.title,
                    kind: node.kind
                )
            }

            updated.relativePath = node.relativePath
            updated.title = node.title
            updated.kind = node.kind
            updated.fingerprint = node.fingerprint
            updated.directImageCount = node.directImageCount
            updated.updatedAt = Date()
            try db.save(updated)
        }

        for item in dbItems where
            !item.isVirtual &&
            !discoveredByPath.keys.contains(item.relativePath) &&
            !migratedIDs.contains(item.id) {
            try db.delete(item)
        }
    }
}
