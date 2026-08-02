import XCTest
@testable import MangaReader

final class NaturalSortTests: XCTestCase {
    func testNumericSegmentsSortNaturally() {
        let values = ["page10.jpg", "page2.jpg", "page1.jpg"]
        let sorted = NaturalSort.sorted(values) { $0 }
        XCTAssertEqual(sorted, ["page1.jpg", "page2.jpg", "page10.jpg"])
    }

    func testStableForEqualStrings() {
        XCTAssertEqual(NaturalSort.compare("same", "same"), .orderedSame)
    }
}
