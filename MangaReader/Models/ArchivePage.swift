import Foundation

struct ArchivePage: Identifiable, Equatable, Codable, Sendable {
    var path: String
    var size: Int64
    var nestedDepth: Int

    var id: String {
        "\(nestedDepth):\(path)"
    }
}
