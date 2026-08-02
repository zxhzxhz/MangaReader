import Foundation
import GRDB

enum ProfileColorSpace: String, Codable, CaseIterable, Sendable {
    case rgb
    case bgr
}

enum ProfileNormalization: String, Codable, CaseIterable, Sendable {
    case zeroToOne
    case zeroTo255
}

enum ProfileAlphaMode: String, Codable, CaseIterable, Sendable {
    case ignore
    case separate
}

enum ExecutionProvider: String, Codable, CaseIterable, Sendable {
    case auto
    case coreML
    case cpu
}

struct ModelProfile: Identifiable, Equatable, Hashable, Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "modelProfile"

    var id: UUID
    var name: String
    var modelFileName: String
    var scale: Int
    var inputName: String
    var outputName: String
    var tileSize: Int
    var overlap: Int
    var colorSpace: ProfileColorSpace
    var normalization: ProfileNormalization
    var alphaMode: ProfileAlphaMode
    var denoiseLevel: Int?
    var executionProvider: ExecutionProvider
    var isTemplate: Bool
    var updatedAt: Date

    var modelURL: URL? {
        AppPaths.modelsDirectory.appendingPathComponent(modelFileName)
    }

    var profileHash: String {
        CacheKey.make([
            name,
            modelFileName,
            String(scale),
            inputName,
            outputName,
            String(tileSize),
            String(overlap),
            colorSpace.rawValue,
            normalization.rawValue,
            alphaMode.rawValue,
            denoiseLevel.map(String.init) ?? "none",
            executionProvider.rawValue
        ])
    }

    static func template(
        name: String,
        modelFileName: String = "model.onnx",
        scale: Int,
        inputName: String = "input",
        outputName: String = "output",
        tileSize: Int = 256,
        overlap: Int = 8,
        colorSpace: ProfileColorSpace = .rgb,
        normalization: ProfileNormalization = .zeroToOne,
        alphaMode: ProfileAlphaMode = .ignore,
        denoiseLevel: Int? = nil,
        executionProvider: ExecutionProvider = .auto
    ) -> ModelProfile {
        ModelProfile(
            id: UUID(),
            name: name,
            modelFileName: modelFileName,
            scale: scale,
            inputName: inputName,
            outputName: outputName,
            tileSize: tileSize,
            overlap: overlap,
            colorSpace: colorSpace,
            normalization: normalization,
            alphaMode: alphaMode,
            denoiseLevel: denoiseLevel,
            executionProvider: executionProvider,
            isTemplate: true,
            updatedAt: Date()
        )
    }

    static let builtInTemplates: [ModelProfile] = [
        template(name: "waifu2x 2x (anime)", scale: 2, denoiseLevel: 0),
        template(name: "waifu2x 2x (photo)", scale: 2, denoiseLevel: 0),
        template(name: "Real-ESRGAN 2x", scale: 2),
        template(name: "Real-ESRGAN 3x", scale: 3),
        template(name: "Real-ESRGAN 4x", scale: 4),
        template(name: "AnimeSharpV4 (custom)", scale: 2)
    ]
}
