import Foundation

enum ContainerKind: String, Codable, CaseIterable, Sendable {
    case book
    case collection
    case mixed
    case unknown
}

struct ContainerClassification: Equatable, Sendable {
    let kind: ContainerKind
    let directImageCount: Int
    let childCount: Int
    let singleChildName: String?

    var shouldCollapseWrapper: Bool {
        childCount == 1 && directImageCount == 0 && singleChildName != nil
    }
}

enum ContainerClassifier {
    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "avif", "tif", "tiff"
    ]

    static let archiveExtensions: Set<String> = ["zip", "7z", "rar"]

    static func isImageFile(_ name: String) -> Bool {
        imageExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    static func isArchiveFile(_ name: String) -> Bool {
        archiveExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    static func classify(directImageCount: Int, childCount: Int, singleChildName: String?) -> ContainerClassification {
        let kind: ContainerKind
        if directImageCount > 0 && childCount > 0 {
            kind = .mixed
        } else if directImageCount > 0 {
            kind = .book
        } else if childCount > 0 {
            kind = .collection
        } else {
            kind = .unknown
        }
        return ContainerClassification(
            kind: kind,
            directImageCount: directImageCount,
            childCount: childCount,
            singleChildName: singleChildName
        )
    }
}

enum PathSafety {
    static func sanitizedEntryPath(_ rawPath: String) -> String? {
        var components = rawPath.split(separator: "/").map(String.init)
        if components.first == "" {
            return nil
        }
        guard !components.contains("..") else {
            return nil
        }
        if components.contains(where: { $0 == "." || $0.isEmpty }) {
            components = components.filter { $0 != "." && !$0.isEmpty }
        }
        guard !components.isEmpty else {
            return nil
        }
        return components.joined(separator: "/")
    }
}
