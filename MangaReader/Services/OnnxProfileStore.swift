import Combine
import Foundation

@MainActor
final class OnnxProfileStore: ObservableObject {
    let db: AppDatabase

    @Published var profiles: [ModelProfile] = []
    @Published var availableModels: [URL] = []

    init(db: AppDatabase) {
        self.db = db
        reload()
    }

    func reload() {
        profiles = (try? db.profiles()) ?? []
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: AppPaths.modelsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        availableModels = contents.filter { $0.pathExtension.lowercased() == "onnx" }
    }

    func createFromTemplate(_ template: ModelProfile, modelURL: URL) throws {
        var profile = template
        profile.id = UUID()
        profile.name = modelURL.deletingPathExtension().lastPathComponent
        profile.modelFileName = modelURL.lastPathComponent
        profile.isTemplate = false
        profile.updatedAt = Date()
        try db.save(profile)
        reload()
    }

    func save(_ profile: ModelProfile) throws {
        var updated = profile
        updated.isTemplate = false
        updated.updatedAt = Date()
        try db.save(updated)
        reload()
    }

    func delete(_ profile: ModelProfile) throws {
        try db.delete(profile)
        reload()
    }
}
