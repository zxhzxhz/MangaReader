import XCTest
@testable import MangaReader

final class ArchiveLimitsTests: XCTestCase {
    func testLimitsMatchSpec() {
        XCTAssertEqual(ArchiveLimits.maxDepth, 4)
        XCTAssertEqual(ArchiveLimits.maxEntryCount, 20_000)
        XCTAssertEqual(ArchiveLimits.maxSingleEntryBytes, 512 * 1024 * 1024)
        XCTAssertEqual(ArchiveLimits.maxEstimatedTotalBytes, 2 * 1024 * 1024 * 1024)
    }

    func testBuiltInTemplatesCoverMajorModelFamilies() {
        let names = ModelProfile.builtInTemplates.map(\.name)
        XCTAssertTrue(names.contains { $0.contains("waifu2x") })
        XCTAssertTrue(names.contains { $0.contains("Real-ESRGAN 4x") })
        XCTAssertTrue(names.contains { $0.contains("AnimeSharpV4") })
    }
}
