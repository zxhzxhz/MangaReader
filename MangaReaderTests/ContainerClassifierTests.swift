import XCTest
@testable import MangaReader

final class ContainerClassifierTests: XCTestCase {
    func testImageOnlyFolderIsBook() {
        let result = ContainerClassifier.classify(
            directImageCount: 5,
            childCount: 0,
            singleChildName: nil
        )
        XCTAssertEqual(result.kind, .book)
        XCTAssertFalse(result.shouldCollapseWrapper)
    }

    func testMixedFolderNeedsResolution() {
        let result = ContainerClassifier.classify(
            directImageCount: 2,
            childCount: 1,
            singleChildName: "Volume 2"
        )
        XCTAssertEqual(result.kind, .mixed)
    }

    func testSingleChildWrapperCollapses() {
        let result = ContainerClassifier.classify(
            directImageCount: 0,
            childCount: 1,
            singleChildName: "Volume"
        )
        XCTAssertTrue(result.shouldCollapseWrapper)
    }

    func testPathSafetyRejectsTraversal() {
        XCTAssertNil(PathSafety.sanitizedEntryPath("../evil.jpg"))
        XCTAssertNotNil(PathSafety.sanitizedEntryPath("folder/page.jpg"))
    }
}
