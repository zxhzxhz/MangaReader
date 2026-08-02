import Foundation

enum AppPaths {
    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var libraryRoot: URL {
        documentsDirectory
    }

    static var modelsDirectory: URL {
        documentsDirectory.appendingPathComponent("Models", isDirectory: true)
    }

    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MangaReader", isDirectory: true)
    }

    static var databaseURL: URL {
        supportDirectory.appendingPathComponent("library.sqlite")
    }

    static var coverDirectory: URL {
        supportDirectory.appendingPathComponent("Covers", isDirectory: true)
    }

    static var cacheRoot: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Derived", isDirectory: true)
    }

    static var thumbnailsDirectory: URL {
        cacheRoot.appendingPathComponent("Thumbnails", isDirectory: true)
    }

    static var extractedDirectory: URL {
        cacheRoot.appendingPathComponent("Extracted", isDirectory: true)
    }

    static var enhancedDirectory: URL {
        cacheRoot.appendingPathComponent("Enhanced", isDirectory: true)
    }

    static var indexesDirectory: URL {
        cacheRoot.appendingPathComponent("Indexes", isDirectory: true)
    }

    static func prepare() throws {
        try createDirectoryIfNeeded(modelsDirectory)
        try createDirectoryIfNeeded(supportDirectory)
        try createDirectoryIfNeeded(coverDirectory)
        try createDirectoryIfNeeded(cacheRoot)
        try createDirectoryIfNeeded(thumbnailsDirectory)
        try createDirectoryIfNeeded(extractedDirectory)
        try createDirectoryIfNeeded(enhancedDirectory)
        try createDirectoryIfNeeded(indexesDirectory)
    }

    private static func createDirectoryIfNeeded(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        if !exists {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } else if !isDirectory.boolValue {
            throw AppPathsError.pathIsFile(url.path)
        }
    }
}

enum AppPathsError: LocalizedError {
    case pathIsFile(String)

    var errorDescription: String? {
        switch self {
        case .pathIsFile(let path):
            return "Expected a directory but found a file: \(path)"
        }
    }
}
